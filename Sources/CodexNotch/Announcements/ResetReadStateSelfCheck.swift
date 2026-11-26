import Foundation

/// Executable regression checks for explicit acknowledgement. All state is
/// synthetic, storage is temporary, and notifications are captured in memory.
enum ResetReadStateSelfCheck {
    @MainActor
    static func run() async throws -> Int {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else { throw Failure(message: message) }
            checks += 1
        }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func post(_ id: String, age: TimeInterval, deadline: TimeInterval) -> ResetAnnouncement {
            ResetAnnouncement(id: id, title: "Synthetic \(id)", summary: "Synthetic acknowledgement fixture \(id)",
                sourceURL: URL(string: "https://example.com/reset/\(id)"),
                announcedAt: now.addingTimeInterval(-age), scheduledFor: now.addingTimeInterval(deadline),
                kind: "regular", scope: "unspecified", status: "scheduled")
        }
        let first = post("read-first", age: 100, deadline: 600)
        let second = post("read-second", age: 200, deadline: 1_200)
        let confirmed = post("read-confirmed", age: 300, deadline: -120)
        var initial = ResetLedger()
        initial.baselineCompleted = true
        initial.deliveryEvidenceBaselineCompleted = true
        initial.manualTimerRestartedAt = now.addingTimeInterval(-30)
        initial.lastSuccessfulCheck = now.addingTimeInterval(-10)
        initial.sourceCheckedAt = now.addingTimeInterval(-20)
        initial.sourceIsFresh = true
        initial.records = [
            ResetRecord(id: first.id, announcement: first, isUnread: true, occurredWhileAway: true),
            ResetRecord(id: second.id, announcement: second, isUnread: true, occurredWhileAway: false),
            ResetRecord(id: confirmed.id, announcement: confirmed, isUnread: false, occurredWhileAway: true,
                        manualCompletedAt: now.addingTimeInterval(-90))
        ]
        initial.versions = Dictionary(uniqueKeysWithValues: initial.records.map { ($0.id, [$0.announcement]) })
        let fixture = initial
        func snapshot(_ values: [ResetAnnouncement]? = nil) -> NextResetSnapshot {
            NextResetSnapshot(announcements: values ?? fixture.records.map(\.announcement),
                              sourceCheckedAt: now, sourceIsFresh: true)
        }
        func top(_ ledger: ResetLedger) -> ResetTopPresentation {
            ResetTopPresentation.make(pending: ledger.pendingAnnouncements, records: ledger.records, now: now,
                                      manualTimerRestartedAt: ledger.manualTimerRestartedAt)
        }

        var acknowledgement = initial
        acknowledgement.records.reverse()
        let unsorted = acknowledgement
        try check(acknowledgement.markAllRead(), "Bulk acknowledgement must change unread/away records")
        try check(acknowledgement.records.allSatisfy { !$0.isUnread && !$0.occurredWhileAway },
                  "Both unread and away flags must clear, including away-only records")
        try check(acknowledgement.records.map(\.id) == unsorted.records.map(\.id), "Bulk acknowledgement must not sort history")
        try check(acknowledgement.records.map(\.announcement) == unsorted.records.map(\.announcement), "Announcement content must not change")
        try check(acknowledgement.records.map(\.manualCompletedAt) == unsorted.records.map(\.manualCompletedAt), "Manual completion dates must not change")
        try check(acknowledgement.versions == unsorted.versions, "Announcement versions must not change")
        try check(acknowledgement.pendingAnnouncements == unsorted.pendingAnnouncements, "Reading must not complete a preview")
        try check(top(acknowledgement) == top(unsorted), "Reading must preserve countdown and elapsed presentation")
        try check(acknowledgement.lastSuccessfulCheck == unsorted.lastSuccessfulCheck
            && acknowledgement.sourceCheckedAt == unsorted.sourceCheckedAt
            && acknowledgement.sourceIsFresh == unsorted.sourceIsFresh, "Reading must preserve source-check metadata")
        try check(!acknowledgement.markAllRead(), "Repeated bulk acknowledgement must be a no-op")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexNotch-read-state-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = ResetLedgerStore(url: directory.appendingPathComponent("ledger.json"))
        try disk.save(initial)
        let diskMonitor = ResetMonitor(store: disk, fetchSnapshot: { snapshot() }, now: { now })
        defer { diskMonitor.stop() }
        try check(diskMonitor.markAllRead(), "Disk-backed bulk acknowledgement must succeed")
        let saved = try disk.load()
        try check(saved?.records == diskMonitor.records, "Acknowledgement must persist to the real temporary JSON file")
        let reloaded = ResetMonitor(store: disk, fetchSnapshot: { snapshot() }, now: { now },
                                    idleSeconds: { 0 }, minimumRefreshInterval: 0)
        defer { reloaded.stop() }
        var replayed = 0
        reloaded.onNotify = { replayed += $0.count }
        try check(reloaded.records == diskMonitor.records && !reloaded.canMarkAllRead, "Restart must retain all-read state")
        for _ in 0..<2 { try await refresh(reloaded) }
        try check(reloaded.unreadCount == 0 && reloaded.awayUnreadCount == 0 && replayed == 0,
                  "Unchanged snapshots after restart must not reopen or replay acknowledged records")
        try check(reloaded.pendingAnnouncements == initial.pendingAnnouncements
            && reloaded.manualTimerRestartedAt == initial.manualTimerRestartedAt, "Reload must retain previews and elapsed anchor")

        let memory = MemoryStore(ledger: initial)
        let failing = ResetMonitor(store: memory,
            fetchSnapshot: { throw URLError(.notConnectedToInternet) }, now: { now })
        defer { failing.stop() }
        try await refresh(failing)
        let feedError = failing.errorMessage
        try check(feedError != nil, "Synthetic offline check must establish a distinct source error")
        var publishedBeforeSave = false
        var unwantedNotifications = 0
        memory.beforeSave = { publishedBeforeSave = publishedBeforeSave || failing.records != fixture.records }
        failing.onNotify = { unwantedNotifications += $0.count }
        memory.failSave = true
        try check(!failing.markAllRead(), "Failed storage must report failed acknowledgement")
        try check(failing.records == initial.records && memory.ledger == initial, "Failed storage must retain published and persisted flags")
        try check(failing.readStateErrorMessage != nil && failing.errorMessage == feedError,
                  "Read-state error must be independent of source error")
        try check(failing.lastSuccessfulCheck == initial.lastSuccessfulCheck, "Read failure must not change successful-check time")
        failing.clearReadStateError()
        try check(failing.readStateErrorMessage == nil && failing.records == initial.records, "Dismissing read error must leave history untouched")
        memory.failSave = false
        try check(failing.markAllRead(), "A successful retry must acknowledge records")
        try check(!publishedBeforeSave, "Published state must change only after persistence succeeds")
        try check(failing.readStateErrorMessage == nil && failing.errorMessage == feedError, "Retry must clear only the read-state error")
        try check(failing.unreadCount == 0 && failing.awayUnreadCount == 0 && !failing.canMarkAllRead, "Successful acknowledgement must clear all badges")
        try check(memory.ledger?.records == failing.records && unwantedNotifications == 0, "Bulk reading must persist quietly")
        let saves = memory.saveCount
        try check(!failing.markAllRead() && memory.saveCount == saves, "Repeated all-read click must not write storage")

        let corruptURL = directory.appendingPathComponent("corrupt.json")
        let corrupt = Data("{synthetic unreadable ledger".utf8)
        try corrupt.write(to: corruptURL)
        let unreadable = ResetMonitor(store: ResetLedgerStore(url: corruptURL),
            fetchSnapshot: { snapshot() }, now: { now })
        defer { unreadable.stop() }
        let loadError = unreadable.errorMessage
        try check(!unreadable.canMarkAllRead && !unreadable.markAllRead(), "Load failure must disable bulk writes")
        unreadable.markRead(id: first.id)
        let retainedCorrupt = try Data(contentsOf: corruptURL)
        try check(retainedCorrupt == corrupt && unreadable.records.isEmpty, "Unreadable original ledger must not be overwritten")
        try check(unreadable.readStateErrorMessage != nil && unreadable.errorMessage == loadError, "Load failure must remain separate from read acknowledgement error")

        let inflightStore = MemoryStore(ledger: initial)
        var request = 0
        var continuation: CheckedContinuation<NextResetSnapshot, Error>?
        var incoming = initial.records.map(\.announcement)
        let inflight = ResetMonitor(store: inflightStore, fetchSnapshot: {
            request += 1
            if request == 2 {
                return try await withCheckedThrowingContinuation { continuation = $0 }
            }
            return snapshot(incoming)
        }, now: { now }, idleSeconds: { 0 }, minimumRefreshInterval: 0)
        defer { inflight.stop() }
        try await refresh(inflight) // Establish the intentionally quiet startup catch-up.
        var notices: [ResetRecord] = []
        inflight.onNotify = { notices.append(contentsOf: $0) }
        inflight.refresh()
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        guard let response = continuation else { throw Failure(message: "Synthetic request did not suspend") }
        let acknowledgedDuringRequest = inflight.markAllRead()
        incoming[0].scheduledFor = now.addingTimeInterval(7_200)
        let new = post("read-new", age: 0, deadline: 3_600)
        incoming.append(new)
        response.resume(returning: snapshot(incoming))
        try await finish(inflight)
        try check(acknowledgedDuringRequest, "Acknowledgement must work while a source request is in flight")
        try check(inflight.records.first { $0.id == second.id }?.isUnread == false
            && inflight.records.first { $0.id == second.id }?.occurredWhileAway == false,
                  "An older in-flight response must preserve acknowledgement of unchanged records")
        try check(Set(inflight.records.filter(\.isUnread).map(\.id)) == Set([first.id, new.id]),
                  "Post-click new records and material updates must still become unread")
        try check(Set(notices.map(\.id)) == Set([first.id, new.id]) && notices.count == 2,
                  "Active-use new and materially revised messages must still notify once")
        try check(inflightStore.ledger?.records == inflight.records, "Merged in-flight state must persist")
        try check(inflight.markAllRead(), "New update batch must support another explicit acknowledgement")
        let countBeforeRepeat = notices.count
        try await refresh(inflight)
        try check(inflight.unreadCount == 0 && notices.count == countBeforeRepeat,
                  "Repeated current snapshot must not replay the acknowledged material revision")

        let navigation = ResetAnnouncementsNavigation()
        navigation.selectRecord(id: second.id)
        navigation.filter = .undated
        try check(navigation.visibleRecords(from: initial.records, activePending: [second]).map(\.id) == [second.id],
                  "Pending filter must follow active previews")
        navigation.filter = .all
        try check(navigation.visibleRecords(from: failing.records, activePending: []).count == initial.records.count
            && navigation.selectedID == second.id,
                  "All-history filter must preserve history and selection")

        // Verify v0.2.18 manual preview dismissal, undated elapsed timer, and home status/error helpers.
        var undatedPost = post("dismiss-undated", age: 9_015, deadline: 600)
        undatedPost.scheduledFor = nil
        undatedPost.sourceURL = URL(string: "https://x.com/thsottiaux/status/991001")
        try check(ResetUndatedSummary.title(count: 1, language: .chinese) == "有 1 条待定预告",
                  "Undated summary title must stay concise")
        try check(ResetUndatedSummary.elapsedText(for: undatedPost, now: now, language: .chinese) == "预告已发出 02:30:15",
                  "Undated elapsed timer must count up from publication time")
        var dayOldPost = undatedPost
        dayOldPost.announcedAt = now.addingTimeInterval(-90_005)
        try check(ResetUndatedSummary.elapsedText(for: dayOldPost, now: now, language: .chinese) == "预告已发出 1天01:00:05",
                  "Undated elapsed timer must include whole days after 24 hours")
        var futurePost = undatedPost
        futurePost.announcedAt = now.addingTimeInterval(60)
        try check(ResetUndatedSummary.elapsedText(for: futurePost, now: now, language: .chinese) == nil,
                  "Future publication timestamp must not fabricate an elapsed timer")
        var missingPubPost = undatedPost
        missingPubPost.announcedAt = nil
        try check(ResetUndatedSummary.elapsedText(for: missingPubPost, now: now, language: .chinese) == nil,
                  "Missing publication timestamp must not fabricate an elapsed timer")
        try check(ResetCheckPresentation.homeStatusText(isChecking: false, errorMessage: nil,
            lastSuccessfulCheck: ISO8601DateFormatter().date(from: "2026-09-22T09:22:00Z")!, language: .chinese) == "17:22 已检查接口",
                  "Home status text must stay concise on successful check")
        try check(ResetCheckPresentation.homeErrorText(isChecking: false, errorMessage: "Timeout", language: .chinese) == "检查遇到问题",
                  "Home error text must surface active feed errors")
        try check(ResetCheckPresentation.homeErrorText(isChecking: true, errorMessage: "Timeout", language: .chinese) == nil,
                  "In-progress check must not display stale error text")

        let priorDelivery = ResetAnnouncement(id: "prior-delivery", title: "官方已重置", summary: "We have reset usage limits.",
            sourceURL: URL(string: "https://x.com/thsottiaux/status/990001"), announcedAt: now.addingTimeInterval(-86_400),
            scheduledFor: nil, kind: "regular", scope: "broad", status: "completed",
            deliveryAt: now.addingTimeInterval(-86_400), deliveryKind: "regular")
        var dismissLedger = ResetLedger()
        dismissLedger.baselineCompleted = true
        dismissLedger.deliveryEvidenceBaselineCompleted = true
        dismissLedger.records = [
            ResetRecord(id: undatedPost.id, announcement: undatedPost, isUnread: false, occurredWhileAway: false),
            ResetRecord(id: priorDelivery.id, announcement: priorDelivery, isUnread: false, occurredWhileAway: false)
        ]
        dismissLedger.versions = Dictionary(uniqueKeysWithValues: dismissLedger.records.map { ($0.id, [$0.announcement]) })
        let beforeDismissTop = top(dismissLedger)
        try check(beforeDismissTop.hasActivePreview && beforeDismissTop.secondsSinceLastDelivery == 86_400,
                  "Active undated preview must light the compact preview indicator")
        let dismissStore = MemoryStore(ledger: dismissLedger)
        let dismissMonitor = ResetMonitor(store: dismissStore, fetchSnapshot: {
            NextResetSnapshot(announcements: [undatedPost, priorDelivery], sourceCheckedAt: now, sourceIsFresh: true)
        }, now: { now }, idleSeconds: { 0 }, minimumRefreshInterval: 0)
        defer { dismissMonitor.stop() }
        dismissStore.failSave = true
        try check(!dismissMonitor.dismissPreviewManually(id: undatedPost.id)
                  && dismissMonitor.manualConfirmationErrorMessage != nil
                  && dismissMonitor.pendingAnnouncements.count == 1,
                  "Failed dismissal save must leave active previews unchanged and report an error")
        dismissStore.failSave = false
        try check(dismissMonitor.dismissPreviewManually(id: undatedPost.id)
                  && dismissMonitor.manualConfirmationErrorMessage == nil
                  && dismissMonitor.pendingAnnouncements.isEmpty,
                  "Dismissal must remove preview from pending list after atomic save")
        let dismissedTop = ResetTopPresentation.make(pending: dismissMonitor.pendingAnnouncements,
                                                     records: dismissMonitor.records, now: now)
        try check(!dismissedTop.hasActivePreview
                  && dismissedTop.secondsSinceLastDelivery == 86_400
                  && dismissedTop.latestDeliveryOrigin == .publicAnnouncement,
                  "Manual dismissal must turn off active preview indicator without changing reset elapsed timer")
        try check(dismissMonitor.records.first { $0.id == undatedPost.id }?.manualDismissedAt == now
                  && dismissMonitor.records.first { $0.id == undatedPost.id }?.manualCompletedAt == nil
                  && dismissMonitor.records.first { $0.id == undatedPost.id }?.announcement.status == "scheduled",
                  "Manual dismissal must preserve public announcement status and keep manualCompletedAt nil")
        try await refresh(dismissMonitor)
        try check(dismissMonitor.pendingAnnouncements.isEmpty
                  && dismissMonitor.records.first { $0.id == undatedPost.id }?.manualDismissedAt == now,
                  "Background refresh must not revive a manually dismissed preview")
        // Verify schema-one JSON compatibility when manualDismissedAt is absent.
        if let savedDismiss = dismissStore.ledger {
            var jsonObj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(savedDismiss)) as! [String: Any]
            var rows = jsonObj["records"] as! [[String: Any]]
            for idx in rows.indices { rows[idx].removeValue(forKey: "manualDismissedAt") }
            jsonObj["records"] = rows
            let decodedLegacy = try JSONDecoder().decode(ResetLedger.self, from: JSONSerialization.data(withJSONObject: jsonObj))
            try check(decodedLegacy.schemaVersion == 1 && decodedLegacy.records.allSatisfy { $0.manualDismissedAt == nil },
                      "Schema-one ledgers without manualDismissedAt must decode cleanly")
        }
        try check(dismissMonitor.undoManualPreviewDismissal(id: undatedPost.id)
                  && dismissMonitor.pendingAnnouncements.map(\.id) == [undatedPost.id],
                  "Undo dismissal must restore a non-terminal preview to the home card")
        let restoredTop = ResetTopPresentation.make(pending: dismissMonitor.pendingAnnouncements,
                                                    records: dismissMonitor.records, now: now)
        try check(restoredTop.hasActivePreview && restoredTop.secondsSinceLastDelivery == 86_400,
                  "Restoring a dismissed preview must keep elapsed reset timer unchanged")

        let singleStore = MemoryStore(ledger: initial)
        let single = ResetMonitor(store: singleStore, fetchSnapshot: { snapshot() }, now: { now })
        defer { single.stop() }
        singleStore.failSave = true
        single.markRead(id: first.id)
        try check(single.records == initial.records && singleStore.ledger == initial
            && single.readStateErrorMessage != nil && single.errorMessage == nil,
                  "Single-record read failure must use the same save-before-publish protection")
        singleStore.failSave = false
        single.markRead(id: first.id)
        try check(single.records.first { $0.id == first.id }?.isUnread == false
            && single.records.first { $0.id == second.id }?.isUnread == true
            && single.readStateErrorMessage == nil, "Single-record retry must change only the selected unread state")
        let singleSaves = singleStore.saveCount
        single.markRead(id: first.id)
        single.markRead(id: "missing")
        try check(singleStore.saveCount == singleSaves, "Repeated/missing single-record acknowledgement must not write")

        var awayOnly = initial
        awayOnly.records = [initial.records[2]]
        let awayMonitor = ResetMonitor(store: MemoryStore(ledger: awayOnly), fetchSnapshot: { snapshot() }, now: { now })
        defer { awayMonitor.stop() }
        try check(awayMonitor.unreadCount == 0 && awayMonitor.canMarkAllRead && awayMonitor.markAllRead()
            && !awayMonitor.records[0].occurredWhileAway, "An orphaned away flag must still be clearable")
        let emptyStore = MemoryStore(ledger: ResetLedger())
        let empty = ResetMonitor(store: emptyStore, fetchSnapshot: { snapshot() }, now: { now })
        defer { empty.stop() }
        try check(!empty.canMarkAllRead && !empty.markAllRead() && emptyStore.saveCount == 0,
                  "An empty ledger must not produce writes")
        return checks
    }

    @MainActor
    private static func refresh(_ monitor: ResetMonitor) async throws {
        monitor.refresh()
        try await finish(monitor)
    }

    @MainActor
    private static func finish(_ monitor: ResetMonitor) async throws {
        for _ in 0..<200 {
            if !monitor.isChecking { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        throw Failure(message: "Synthetic read-state refresh did not finish")
    }

    private struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { "Read-state self-check: \(message)" }
    }

    private final class MemoryStore: ResetLedgerStoring {
        var ledger: ResetLedger?
        var failSave = false
        var saveCount = 0
        var beforeSave: (() -> Void)?
        init(ledger: ResetLedger?) { self.ledger = ledger }
        func load() throws -> ResetLedger? { ledger }
        func save(_ value: ResetLedger) throws {
            saveCount += 1
            beforeSave?()
            if failSave { throw CocoaError(.fileWriteNoPermission) }
            ledger = value
        }
    }
}
