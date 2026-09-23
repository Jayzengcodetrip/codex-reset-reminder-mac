import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications

enum ResetReminderPreferences {
    static let launchAtLoginKey = "resetReminder.launchAtLogin"
    static let notificationStatusKey = "resetReminder.notificationStatus"
    static let loginStatusKey = "resetReminder.loginStatus"
    static let notificationAction = Notification.Name("ResetReminder.notificationAction")
    static let loginAction = Notification.Name("ResetReminder.loginAction")
    static let showAction = Notification.Name("ResetReminder.showAction")
    static let showSummaryAction = Notification.Name("ResetReminder.showSummaryAction")
}

enum ResetNotificationText {
    static func announcement(from records: [ResetRecord], now: Date, pending: [ResetAnnouncement]? = nil) -> ResetAnnouncement? {
        if let newestPending = pending?.reversed().first(where: { announcement in
            records.contains { $0.announcement.id == announcement.id }
        }) {
            return newestPending
        }
        return ResetAnnouncementSummary.select(from: records, now: now)
            ?? records.max(by: {
                ($0.announcement.announcedAt ?? .distantPast) < ($1.announcement.announcedAt ?? .distantPast)
            })?.announcement
    }

    static func body(announcement: ResetAnnouncement, now: Date, count: Int) -> String {
        var lines = [announcement.title]
        let normalizedStatus = announcement.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if ["completed", "confirmed", "propagated"].contains(normalizedStatus) {
            lines.append("来源已确认重置完成")
        } else if ["cancelled", "canceled"].contains(normalizedStatus) {
            lines.append("来源已取消这次重置")
        } else if let target = ResetScheduleTiming.target(for: announcement) {
            lines.append(ResetScheduleTiming.targetText(for: announcement, language: .chinese))
            if let beijingWeekday = ResetScheduleTiming.beijingWeekdayText(for: announcement, language: .chinese) {
                lines.append(beijingWeekday)
            }
            if target.countdownDeadline > now {
                lines.append(ResetAnnouncementSummary.countdownText(for: announcement, now: now, language: .chinese))
            } else {
                lines.append("预计时间已过，执行状态请查看公告")
            }
        } else {
            lines.append("重置时间待公布，暂时无法计算倒计时")
        }
        if count > 1 { lines.append("共 \(count) 条更新，点击查看") }
        lines.append("来源：NextReset 公开接口")
        return lines.joined(separator: "\n")
    }
}

@MainActor
final class ResetExperienceCoordinator: NSObject, UNUserNotificationCenterDelegate {
    let monitor: ResetMonitor
    var onStatusChange: ((Int, Int, String, [ResetAnnouncement]) -> Void)?
    var onShowSummary: (() -> Void)?
    private let notificationCenter = UNUserNotificationCenter.current()
    private var detailWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []

    override init() {
        // Only public announcements and local read flags go into this file.
        // No account data, tokens, or quota responses are persisted here.
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stateURL = documents.appendingPathComponent("Codex/QuotaReminderState/announcements.json")
        monitor = ResetMonitor(stateURL: stateURL)
        super.init()
    }

    func start() {
        notificationCenter.delegate = self
        monitor.onChange = { [weak self] in self?.publishStatus() }
        monitor.onNotify = { [weak self] records in self?.notify(records) }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: ResetReminderPreferences.notificationAction, object: nil, queue: .main
        ) { [weak self] notification in
            let test = notification.userInfo?["test"] as? Bool ?? false
            Task { @MainActor in await self?.configureNotifications(sendTest: test) }
        })
        observers.append(center.addObserver(
            forName: ResetReminderPreferences.loginAction, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.configureLoginItem() }
        })
        observers.append(center.addObserver(
            forName: ResetReminderPreferences.showAction, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.showAnnouncements() }
        })
        observers.append(center.addObserver(
            forName: ResetReminderPreferences.showSummaryAction, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.onShowSummary?() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == Bundle.main.bundleIdentifier else { return }
            Task { @MainActor in await self?.updateNotificationStatus() }
        })
        publishStatus()
        monitor.start()
        configureLoginItem()
        Task { await configureNotifications(sendTest: false) }
    }

    func stop() {
        monitor.stop()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }

    func showAnnouncements() {
        if detailWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 670),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            window.title = "重置公告 · 额度提醒"
            window.minSize = NSSize(width: 640, height: 600)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ResetAnnouncementsView(monitor: monitor))
            window.center()
            detailWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        detailWindow?.makeKeyAndOrderFront(nil)
        // Opening the window itself must not mark any announcement read.
    }

    private func publishStatus() {
        let pending = monitor.pendingAnnouncements
        let status = ResetCheckPresentation.compactText(
            isChecking: monitor.isChecking, errorMessage: monitor.errorMessage,
            lastSuccessfulCheck: monitor.lastSuccessfulCheck, hasPending: !pending.isEmpty,
            unreadCount: monitor.unreadCount,
            language: AppLanguage.fromStoredValue(UserDefaults.standard.string(forKey: AppLanguage.storageKey)),
            hasNewPreannouncement: monitor.hasNewPreannouncement
        )
        onStatusChange?(monitor.unreadCount, monitor.awayUnreadCount, status, pending)
    }

    private func notify(_ records: [ResetRecord]) {
        let now = Date.now
        guard let announcement = ResetNotificationText.announcement(from: records, now: now, pending: monitor.pendingAnnouncements) else { return }
        let content = UNMutableNotificationContent()
        content.title = records.count == 1 ? "重置公告有更新" : "有 \(records.count) 条重置动态"
        content.body = ResetNotificationText.body(announcement: announcement, now: now, count: records.count)
        content.sound = .default
        content.threadIdentifier = "nextreset-announcements"
        // Ledger deduplication precedes this call. OS delivery never clears unread.
        let request = UNNotificationRequest(identifier: "reset-\(UUID().uuidString)", content: content, trigger: nil)
        notificationCenter.add(request) { error in
            guard error != nil else { return }
            DispatchQueue.main.async {
                UserDefaults.standard.set("弹出通知未送达，公告已保留在窗口", forKey: ResetReminderPreferences.notificationStatusKey)
            }
        }
    }

    private func configureNotifications(sendTest: Bool) async {
        let settings = await notificationCenter.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
        }
        await updateNotificationStatus()
        guard sendTest else { return }
        let current = await notificationCenter.notificationSettings()
        guard current.authorizationStatus == .authorized || current.authorizationStatus == .provisional else {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "【测试】额度提醒已连接"
        content.body = "这是一条测试通知。公开接口出现新公告后，会在这里提醒你；此测试不会制造未读公告。"
        content.sound = .default
        try? await notificationCenter.add(UNNotificationRequest(
            identifier: "reset-reminder-test", content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        ))
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        let delivered = await notificationCenter.deliveredNotifications()
        UserDefaults.standard.set(
            delivered.contains(where: { $0.request.identifier == "reset-reminder-test" })
                ? "测试已送达系统通知中心" : "测试已提交，暂未在通知中心确认",
            forKey: ResetReminderPreferences.notificationStatusKey
        )
    }

    private func updateNotificationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        let status: String
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            status = settings.alertSetting == .enabled
                ? "系统通知已允许" : "通知已允许，横幅需在系统设置中开启"
        case .denied: status = "系统通知尚未允许 · 未读公告仍会保留"
        case .notDetermined: status = "等待系统通知授权"
        default: status = "请检查系统通知设置"
        }
        UserDefaults.standard.set(status, forKey: ResetReminderPreferences.notificationStatusKey)
    }

    private func configureLoginItem() {
        let enabled = UserDefaults.standard.bool(forKey: ResetReminderPreferences.launchAtLoginKey)
        do {
            if enabled, [.notRegistered, .notFound].contains(SMAppService.mainApp.status) {
                try SMAppService.mainApp.register()
            } else if !enabled, [.enabled, .requiresApproval].contains(SMAppService.mainApp.status) {
                try SMAppService.mainApp.unregister()
            }
            let status: String
            switch SMAppService.mainApp.status {
            case .enabled: status = "登录后自动启动已开启"
            case .requiresApproval: status = "请在系统「登录项」中允许自动启动"
            case .notRegistered: status = "登录后自动启动已关闭"
            default: status = "自动启动暂不可用，请保留应用所在位置"
            }
            UserDefaults.standard.set(status, forKey: ResetReminderPreferences.loginStatusKey)
        } catch {
            UserDefaults.standard.set("自动启动设置未完成，可在系统「登录项」中添加本应用", forKey: ResetReminderPreferences.loginStatusKey)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor [weak self] in
            self?.showAnnouncements()
            completionHandler()
        }
    }
}

struct ResetReminderSettingsView: View {
    @AppStorage(ResetReminderPreferences.launchAtLoginKey) private var launchAtLogin = true
    @AppStorage(ResetReminderPreferences.notificationStatusKey) private var notificationStatus = "正在检查通知设置…"
    @AppStorage(ResetReminderPreferences.loginStatusKey) private var loginStatus = "正在检查自动启动…"

    var body: some View {
        Section("重置公告提醒") {
            Text("免费公开接口 · 每 2 分钟检查 · 仅新公告和更新弹出提醒")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("查看倒计时") { NotificationCenter.default.post(name: ResetReminderPreferences.showSummaryAction, object: nil) }
                Button("查看公告") { NotificationCenter.default.post(name: ResetReminderPreferences.showAction, object: nil) }
                Button("测试通知") {
                    NotificationCenter.default.post(name: ResetReminderPreferences.notificationAction, object: nil, userInfo: ["test": true])
                }
            }
            Text(notificationStatus).font(.caption).foregroundStyle(.secondary)
            Toggle("登录后自动启动", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, _ in
                    NotificationCenter.default.post(name: ResetReminderPreferences.loginAction, object: nil)
                }
            Text(loginStatus).font(.caption).foregroundStyle(.secondary)
            Text("窗口收起／恢复：⌥⌘N。退出应用会暂停检查。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
