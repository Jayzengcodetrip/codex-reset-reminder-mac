import AppKit
import Combine
import Foundation
import Network

@MainActor
final class ResetMonitor: ObservableObject {
    @Published private(set) var records: [ResetRecord] = []
    @Published private(set) var isChecking = false
    @Published private(set) var lastSuccessfulCheck: Date?
    @Published private(set) var sourceCheckedAt: Date?
    @Published private(set) var sourceIsFresh = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasNewPreannouncement = false
    var unreadCount: Int { records.filter(\.isUnread).count }
    var awayUnreadCount: Int { records.filter { $0.isUnread && $0.occurredWhileAway }.count }
    var pendingAnnouncements: [ResetAnnouncement] { ledger.pendingAnnouncements }
    var onChange: (() -> Void)?
    var onNotify: (([ResetRecord]) -> Void)?

    private let fetchSnapshot: () async throws -> NextResetSnapshot
    private let store: ResetLedgerStoring
    private let now: () -> Date
    private let idleSeconds: () -> TimeInterval
    private let minimumRefreshInterval: TimeInterval
    private var ledger = ResetLedger()
    private var storageLoadFailed = false
    private var timer: Timer?
    private var deferredRefresh: Timer?
    private var networkWasReachable: Bool?
    private var task: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var pendingCatchUp = true
    private var isAway = false
    private var lastAttempt: Date?
    private var refreshQueued = false
    private var isStarted = false
    private var generation = 0

    convenience init(stateURL: URL? = nil) {
        let defaultURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexNotch", isDirectory: true)
            .appendingPathComponent("reset-announcements.json")
        let client = NextResetClient()
        self.init(store: ResetLedgerStore(url: stateURL ?? defaultURL), fetchSnapshot: { try await client.fetch() })
    }

    init(store: ResetLedgerStoring,
         fetchSnapshot: @escaping () async throws -> NextResetSnapshot,
         now: @escaping () -> Date = Date.init,
         idleSeconds: @escaping () -> TimeInterval = {
             CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
         }, minimumRefreshInterval: TimeInterval = 60) {
        self.store = store
        self.fetchSnapshot = fetchSnapshot
        self.now = now
        self.idleSeconds = idleSeconds
        self.minimumRefreshInterval = minimumRefreshInterval
        do { ledger = try store.load() ?? ResetLedger() }
        catch {
            storageLoadFailed = true
            errorMessage = "无法读取本地公告记录，已保留原文件。请检查文件权限后重新打开应用。"
        }
        publishLedger()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification) { $0.becameAway() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.sessionDidResignActiveNotification) { $0.becameAway() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification) { $0.resumed() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.sessionDidBecomeActiveNotification) { $0.resumed() }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked")) { $0.becameAway() }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked")) { $0.resumed() }
        let network = NWPathMonitor()
        network.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let reachable = path.status == .satisfied
                let previous = self.networkWasReachable
                self.networkWasReachable = reachable
                if reachable {
                    if previous == false {
                        self.pendingCatchUp = true
                        self.refresh()
                    }
                } else {
                    self.pendingCatchUp = true
                    self.sourceIsFresh = false
                    self.errorMessage = "网络未连接；恢复后会补查公告。"
                    self.onChange?()
                }
            }
        }
        network.start(queue: DispatchQueue(label: "CodexNotch.ResetNetwork"))
        pathMonitor = network
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    func stop() {
        isStarted = false
        timer?.invalidate()
        timer = nil
        deferredRefresh?.invalidate()
        deferredRefresh = nil
        networkWasReachable = nil
        generation += 1
        task?.cancel()
        task = nil
        isChecking = false
        pathMonitor?.cancel()
        pathMonitor = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        pendingCatchUp = true
        refreshQueued = false
    }

    func refresh() {
        guard !storageLoadFailed else { return }
        guard task == nil else { refreshQueued = true; return }
        let checkTime = now()
        if let lastAttempt, checkTime.timeIntervalSince(lastAttempt) < minimumRefreshInterval {
            if deferredRefresh == nil {
                let delay = max(1, minimumRefreshInterval - checkTime.timeIntervalSince(lastAttempt))
                deferredRefresh = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        self?.deferredRefresh = nil
                        self?.refresh()
                    }
                }
            }
            return
        }
        deferredRefresh?.invalidate()
        deferredRefresh = nil
        if let lastAttempt, checkTime.timeIntervalSince(lastAttempt) > 300 { pendingCatchUp = true }
        lastAttempt = checkTime
        isChecking = true
        onChange?()
        generation += 1
        let requestGeneration = generation
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await self.fetchSnapshot()
                try Task.checkCancellation()
                guard self.generation == requestGeneration else { return }
                self.accept(snapshot)
            } catch is CancellationError {
                // Stop/sleep never turns an interrupted request into a completed check.
            } catch {
                guard self.generation == requestGeneration else { return }
                self.pendingCatchUp = true
                self.sourceIsFresh = false
                self.errorMessage = "公告检查失败：\(error.localizedDescription) 下次将继续补查。"
            }
            guard self.generation == requestGeneration else { return }
            self.isChecking = false
            self.task = nil
            self.onChange?()
            if self.refreshQueued {
                self.refreshQueued = false
                self.refresh()
            }
        }
    }

    func markRead(id: String) {
        guard ledger.records.contains(where: { $0.id == id && $0.isUnread }) else { return }
        var candidate = ledger
        candidate.markRead(id: id)
        do {
            try store.save(candidate)
            ledger = candidate
            publishLedger()
        } catch {
            errorMessage = "已读状态未能保存，公告仍保留为未读。"
            onChange?()
        }
    }

    private func accept(_ snapshot: NextResetSnapshot) {
        let wasAway = pendingCatchUp || isAway || idleSeconds() >= 300
        var candidate = ledger
        let changes = candidate.ingest(snapshot, at: now(), occurredWhileAway: wasAway)
        let previousPending = ledger.pendingAnnouncements
        let foundNewPreannouncement = candidate.pendingAnnouncements.contains { incoming in
            !previousPending.contains { ResetPendingAnnouncements.sameIdentity($0, incoming) }
        }
        do {
            try store.save(candidate)
            ledger = candidate
            pendingCatchUp = false
            hasNewPreannouncement = foundNewPreannouncement
            // Provider review diagnostics do not make a successfully saved interface check fail.
            errorMessage = nil
            publishLedger()
            if !wasAway && !changes.isEmpty { onNotify?(changes) }
        } catch {
            pendingCatchUp = true
            sourceIsFresh = false
            errorMessage = "公告记录未能保存；本次检查未完成，下次会重新补查。"
        }
    }

    private func publishLedger() {
        records = ledger.records
        lastSuccessfulCheck = ledger.lastSuccessfulCheck
        sourceCheckedAt = ledger.sourceCheckedAt
        sourceIsFresh = ledger.sourceIsFresh && ledger.sourceCheckedAt.map { now().timeIntervalSince($0) <= 45 * 60 } == true
        onChange?()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping @MainActor (ResetMonitor) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in if let self { action(self) } }
        }
        observers.append((center, token))
    }

    private func becameAway() {
        isAway = true
        pendingCatchUp = true
    }

    private func resumed() {
        isAway = false
        pendingCatchUp = true
        refresh()
    }
}
