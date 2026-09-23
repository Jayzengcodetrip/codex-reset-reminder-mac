import Foundation

/// Deterministic behavior checks for machines with Command Line Tools but no XCTest.
/// Uses only local public-content fixtures; never starts monitoring or requests notifications.
enum ResetSelfCheck {
    @MainActor
    static func run() async throws -> Int {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else { throw CheckError(message: message) }
            checks += 1
        }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func post(_ id: String) -> ResetAnnouncement {
            ResetAnnouncement(id: id, title: "额度更新", summary: "公开公告测试内容", sourceURL: nil,
                              announcedAt: now, scheduledFor: nil, kind: "regular", scope: "unspecified", status: nil)
        }
        func snapshot(_ posts: [ResetAnnouncement], fresh: Bool = true) -> NextResetSnapshot {
            NextResetSnapshot(announcements: posts, sourceCheckedAt: now, sourceIsFresh: fresh)
        }
        var ledger = ResetLedger()
        var pending = post("pending")
        pending.status = "scheduled"
        let baselineChanges = ledger.ingest(snapshot([post("old"), pending]), at: now, occurredWhileAway: true)
        try check(baselineChanges.isEmpty, "Historical baseline must not notify")
        try check(ledger.records.filter(\.isUnread).map(\.id) == ["pending"], "Pending baseline must stay visible")
        try check(pending.scheduledFor == nil, "Unknown reset deadline must not be inferred")
        let first = ledger.ingest(snapshot([post("new")]), at: now, occurredWhileAway: false)
        try check(first.count == 1 && first[0].isUnread && !first[0].occurredWhileAway, "Awake new announcement must become unread")
        try check(ledger.ingest(snapshot([post("new")]), at: now, occurredWhileAway: false).isEmpty, "Same announcement must deduplicate")
        ledger.markRead(id: "new")
        var revision = post("new")
        revision.summary = "更正后的公告"
        revision.status = "completed"
        try check(ledger.ingest(snapshot([revision]), at: now, occurredWhileAway: false).count == 1, "Material revision must reopen unread")
        ledger.markRead(id: "new")
        var historyOnly = revision
        historyOnly.status = nil
        try check(ledger.ingest(snapshot([historyOnly]), at: now, occurredWhileAway: false).isEmpty, "Missing archive status must preserve confirmed completion")
        try check(ledger.records.first(where: { $0.id == "new" })?.announcement.status == "completed", "Confirmed status must remain visible")
        var oldCache = post("new")
        oldCache.status = "completed"
        // Check rollback against an actually stored material version.
        var cacheLedger = ResetLedger()
        _ = cacheLedger.ingest(snapshot([oldCache]), at: now, occurredWhileAway: true)
        _ = cacheLedger.ingest(snapshot([revision]), at: now, occurredWhileAway: false)
        cacheLedger.markRead(id: "new")
        try check(cacheLedger.ingest(snapshot([oldCache]), at: now, occurredWhileAway: false).isEmpty, "Previously seen cache version must not replay")
        try check(cacheLedger.records[0].announcement.summary == revision.summary, "Old cache must not replace newer content")
        var delayed = post("delayed")
        delayed.announcedAt = now.addingTimeInterval(-86_400)
        let awayChanges = ledger.ingest(snapshot([delayed, post("away-new")]), at: now, occurredWhileAway: true)
        try check(awayChanges.count == 2 && awayChanges.allSatisfy(\.occurredWhileAway), "Catch-up must retain delayed indexed posts regardless of timestamp")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CodexNotch-selfcheck-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let disk = ResetLedgerStore(url: folder.appendingPathComponent("ledger.json"))
        try disk.save(ledger)
        var restored = try disk.load() ?? ResetLedger()
        try check(restored == ledger, "Disk round trip must retain versions and acknowledgement state")
        _ = restored.ingest(snapshot([], fresh: false), at: now, occurredWhileAway: false)
        try check(restored.records.filter { $0.isUnread && $0.occurredWhileAway }.count == 3, "Removed archive entries must retain unread state")
        try check(!restored.sourceIsFresh, "Upstream diagnostic metadata must remain available")

        let metadata: [String: Any] = ["fresh": true, "checked_at": "2026-09-12T13:16:03Z",
                                      "x_source": ["fresh": true, "checked_at": "2026-09-12T13:07:27Z"]]
        let fixturePost: [String: Any] = ["id": "fixture", "title": ["zh": "重置已完成", "en": "Reset complete"],
                                         "summary": ["zh": "以账户实际用量为准"], "announcedAt": "2026-09-12T08:09:17.000Z",
                                         "sourceUrl": "https://x.com/thsottiaux/status/fixture", "kind": "regular", "scope": "unspecified"]
        let scheduledPost: [String: Any] = ["id": "scheduled-fixture", "title": ["en": "Reset planned"], "summary": ["en": "Time unknown"]]
        let status = try JSONSerialization.data(withJSONObject: ["latest_update": fixturePost,
                            "latest_confirmed_reset": fixturePost, "scheduled": scheduledPost, "meta": metadata])
        let archive = try JSONSerialization.data(withJSONObject: ["data": [fixturePost], "meta": metadata])
        let decoded = try NextResetClient.decode(status: status, archive: archive)
        try check(decoded.announcements.count == 2, "Status must supplement the complete archive")
        try check(decoded.announcements.allSatisfy { $0.scheduledFor == nil }, "Publication timestamp must never become reset deadline")
        try check(decoded.announcements.first(where: { $0.id == "fixture" })?.title == "重置已完成", "Chinese title must be preferred")
        let envelope: [String: Any] = ["event": fixturePost, "scheduledFor": "2026-09-23T07:00:00.000Z"]
        func envelopeStatus(_ value: Any) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["latest_update": fixturePost,
                "scheduled": value, "meta": metadata])
        }
        let enveloped = try NextResetClient.decode(status: envelopeStatus(envelope), archive: archive)
        try check(enveloped.announcements.count == 1, "Wrapped scheduled event must merge with the same archive ID")
        let recovered = enveloped.announcements[0]
        try check(recovered.status == "scheduled", "Wrapped preannouncement must retain scheduled status")
        try check(recovered.scheduledFor == ISO8601DateFormatter().date(from: "2026-09-23T07:00:00Z"),
                  "Wrapped preannouncement must use its explicit envelope deadline")
        try check(recovered.announcedAt == decoded.announcements.first(where: { $0.id == "fixture" })?.announcedAt,
                  "Wrapped preannouncement must preserve publication time separately")
        let noDeadline = try NextResetClient.decode(status: envelopeStatus(["event": scheduledPost]), archive: archive)
        try check(noDeadline.announcements.first(where: { $0.id == "scheduled-fixture" })?.scheduledFor == nil,
                  "Wrapped event without a deadline must not invent one")
        do {
            _ = try NextResetClient.decode(status: envelopeStatus(["event": "invalid"]), archive: archive)
            throw CheckError(message: "Malformed wrapped event must not silently discard announcements")
        } catch is CheckError { throw CheckError(message: "Malformed wrapped event must not silently discard announcements") }
        catch { checks += 1 }
        do {
            _ = try NextResetClient.decode(status: status, archive: Data("{}".utf8))
            throw CheckError(message: "Invalid archive must not be accepted as empty")
        } catch is CheckError { throw CheckError(message: "Invalid archive must not be accepted as empty") }
        catch { checks += 1 }

        let memory = CheckStore()
        var incoming = [post("monitor-old")]
        var failFetch = false
        var notifications = 0
        let monitor = ResetMonitor(store: memory, fetchSnapshot: {
            if failFetch { throw URLError(.notConnectedToInternet) }
            return snapshot(incoming)
        }, now: { now }, idleSeconds: { 0 }, minimumRefreshInterval: 0)
        monitor.onNotify = { notifications += $0.count }
        try await refresh(monitor)
        try check(notifications == 0 && monitor.unreadCount == 0, "Monitor baseline must stay quiet")
        incoming.append(post("monitor-new"))
        memory.failSave = true
        try await refresh(monitor)
        try check(monitor.records.count == 1 && memory.ledger?.records.count == 1 && notifications == 0,
                  "Failed persistence must not advance memory or notify")
        try check(monitor.errorMessage != nil, "Persistence failure must be visible")
        memory.failSave = false
        try await refresh(monitor)
        try check(monitor.unreadCount == 1 && monitor.awayUnreadCount == 1 && notifications == 0,
                  "Retry must silently recover the missed update")
        incoming.append(post("monitor-awake"))
        try await refresh(monitor)
        try check(notifications == 1 && monitor.unreadCount == 2, "Awake update must notify only after successful persistence")
        memory.failSave = true
        monitor.markRead(id: "monitor-awake")
        try check(monitor.unreadCount == 2, "Failed acknowledgement must retain unread state")
        memory.failSave = false
        monitor.markRead(id: "monitor-awake")
        try check(monitor.unreadCount == 1, "Only selected announcement may be acknowledged")
        let priorSuccess = monitor.lastSuccessfulCheck
        failFetch = true
        try await refresh(monitor)
        try check(monitor.lastSuccessfulCheck == priorSuccess && !monitor.sourceIsFresh && monitor.records.count == 3,
                  "Failed fetch must retain saved records and last successful check")
        let restarted = ResetMonitor(store: memory, fetchSnapshot: { snapshot(incoming + [post("restart-new")]) },
                                     now: { now }, idleSeconds: { 0 }, minimumRefreshInterval: 0)
        restarted.onNotify = { notifications += $0.count }
        try await refresh(restarted)
        try check(restarted.awayUnreadCount == 2 && notifications == 1, "Restart must catch up silently and preserve unread")
        var clock = now
        var fetches = 0
        let throttled = ResetMonitor(store: CheckStore(), fetchSnapshot: { fetches += 1; return snapshot([]) },
                                     now: { clock }, idleSeconds: { 0 }, minimumRefreshInterval: 60)
        defer { throttled.stop() }
        try await refresh(throttled)
        try await refresh(throttled)
        try check(fetches == 1, "Rapid refresh must respect 60-second source interval")
        clock.addTimeInterval(60)
        try await refresh(throttled)
        try check(fetches == 2, "Queued refresh must become available after source interval")
        let delayedStore = CheckStore()
        var delayedPosts = [post("delayed-source-old")]
        var delayedNotifications = 0
        let delayedMonitor = ResetMonitor(store: delayedStore, fetchSnapshot: {
            snapshot(delayedPosts, fresh: false)
        }, now: { now }, idleSeconds: { 0 }, minimumRefreshInterval: 0)
        delayedMonitor.onNotify = { delayedNotifications += $0.count }
        try await refresh(delayedMonitor)
        try check(delayedMonitor.errorMessage == nil && delayedMonitor.lastSuccessfulCheck == now,
                  "Successfully read interface must not report an error for upstream X diagnostic delay")
        try check(!delayedMonitor.sourceIsFresh, "Hiding upstream diagnostics must not falsify saved metadata")
        delayedPosts.append(post("delayed-source-new"))
        try await refresh(delayedMonitor)
        try check(delayedMonitor.errorMessage == nil && delayedNotifications == 1 && delayedMonitor.unreadCount == 1,
                  "New interface records must still notify when upstream X diagnostics report delay")
        let completedBody = ResetNotificationText.body(title: "已完成公告", scheduledFor: now.addingTimeInterval(3600),
                                                       now: now, count: 1, status: "completed")
        try check(!completedBody.contains("还剩") && completedBody.contains("来源已确认重置完成"),
                  "Completed notification must suppress an obsolete future countdown")
        let paddedCompletedBody = ResetNotificationText.body(title: "已完成公告", scheduledFor: now.addingTimeInterval(3600),
                                                             now: now, count: 1, status: " COMPLETED \n")
        try check(paddedCompletedBody == completedBody,
                  "Whitespace and capitalization must not turn a completed notification into a countdown")
        let unknownBody = ResetNotificationText.body(title: "新公告", scheduledFor: nil, now: now, count: 1)
        try check(!unknownBody.contains("还剩"), "Unknown schedule must not create a notification countdown")
        try check(unknownBody.contains("时间待公布"), "Undated notification must explain why no countdown is available")
        let futureBody = ResetNotificationText.body(title: "新预告", scheduledFor: now.addingTimeInterval(5_400), now: now, count: 1)
        try check(futureBody.contains("北京时间") && futureBody.contains("还剩 1小时30分钟") && futureBody.contains("接口时间"),
                  "Advance notification must include the Beijing deadline and time remaining with source attribution")
        var terminalDetail = post("terminal-detail")
        terminalDetail.scheduledFor = now.addingTimeInterval(3600)
        terminalDetail.status = " COMPLETED \n"
        try check(ResetAnnouncementDisplay.timingText(terminalDetail, now: now, language: .chinese) == "来源已确认重置完成",
                  "Detail completion must normalize source whitespace and suppress countdowns")
        terminalDetail.status = " CANCELLED \n"
        try check(ResetAnnouncementDisplay.timingText(terminalDetail, now: now, language: .chinese) == "来源已取消这次重置",
                  "Detail cancellation must normalize source whitespace and suppress countdowns")
        var advance = post("advance")
        advance.scheduledFor = now.addingTimeInterval(5_400)
        advance.status = "scheduled"
        advance.announcedAt = now.addingTimeInterval(-60)
        let advanceRecord = ResetRecord(id: advance.id, announcement: advance, isUnread: true, occurredWhileAway: false)
        let newerRecord = ResetRecord(id: "newer", announcement: post("newer"), isUnread: true, occurredWhileAway: false)
        try check(ResetNotificationText.announcement(from: [advanceRecord, newerRecord], now: now)?.id == advance.id,
                  "Mixed notification batch must prioritize a real future deadline over a newer undated update")
        try check(ResetNotificationText.announcement(from: [newerRecord], now: now)?.id == "newer",
                  "A batch without a pending reset must still notify its latest update")
        let second = ResetAnnouncement(id: "second", title: "另一场重置", summary: "公开测试", sourceURL: nil,
                                   announcedAt: now, scheduledFor: now.addingTimeInterval(10_800),
                                   kind: "regular", scope: "unspecified", status: "scheduled")
        var multiLedger = ResetLedger()
        _ = multiLedger.ingest(snapshot([advance]), at: now, occurredWhileAway: false)
        let secondChanges = multiLedger.ingest(snapshot([advance, second]), at: now, occurredWhileAway: false)
        let simultaneousPending = multiLedger.pendingAnnouncements
        try check(simultaneousPending.count == 2 && Set(simultaneousPending.map(\.id)) == [advance.id, second.id],
                  "Independent pending resets must preserve both countdowns")
        try check(ResetNotificationText.announcement(from: multiLedger.records, now: now, pending: simultaneousPending)?.id == "second",
                  "Mixed notification batch must prioritize the latest changed pending preannouncement")
        try check(ResetNotificationText.announcement(from: secondChanges, now: now, pending: simultaneousPending)?.id == "second",
                  "The new second preannouncement must be notified without replacing the first")
        try check(ResetAnnouncementEntriesView.height(for: 0) == 96 && ResetAnnouncementEntriesView.height(for: 1) == 96,
                  "Empty and single-announcement cards must preserve the existing layout height")
        try check(ResetAnnouncementEntriesView.height(for: 2) == 200 && ResetAnnouncementEntriesView.height(for: 5) == 200,
                  "Two countdowns fit above quota and further countdowns scroll within bounded height")
        let pendingStore = CheckStore()
        var pendingPosts = [advance]
        var pendingNotifications = 0
        let pendingMonitor = ResetMonitor(store: pendingStore, fetchSnapshot: { snapshot(pendingPosts) },
            now: { now }, idleSeconds: { 0 }, minimumRefreshInterval: 0)
        pendingMonitor.onNotify = { pendingNotifications += $0.count }
        try await refresh(pendingMonitor)
        try check(pendingMonitor.hasNewPreannouncement && pendingMonitor.pendingAnnouncements.count == 1,
                  "The first successful discovery can expose a new pending preannouncement")
        try await refresh(pendingMonitor)
        try check(!pendingMonitor.hasNewPreannouncement && pendingMonitor.pendingAnnouncements.count == 1,
                  "No additional preannouncement must not hide the existing countdown")
        pendingPosts.append(second)
        pendingStore.failSave = true
        try await refresh(pendingMonitor)
        try check(pendingMonitor.pendingAnnouncements.count == 1 && !pendingMonitor.hasNewPreannouncement
                  && pendingNotifications == 0 && pendingMonitor.errorMessage != nil,
                  "Failed save must not publish a second countdown or claim a successful check")
        pendingStore.failSave = false
        try await refresh(pendingMonitor)
        try check(pendingMonitor.pendingAnnouncements.count == 2 && pendingMonitor.hasNewPreannouncement && pendingNotifications == 0,
                  "Recovery must persist both countdowns and catch up silently")
        try await refresh(pendingMonitor)
        try check(!pendingMonitor.hasNewPreannouncement && pendingMonitor.pendingAnnouncements.count == 2,
                  "A following unchanged check reports no new preannouncement while preserving both countdowns")
        var changedTime = second
        changedTime.scheduledFor = now.addingTimeInterval(11_000)
        pendingPosts = [advance, changedTime]
        try await refresh(pendingMonitor)
        try check(!pendingMonitor.hasNewPreannouncement && pendingMonitor.pendingAnnouncements.count == 2 && pendingNotifications == 1,
                  "A time correction updates and notifies the existing card without inventing another preannouncement")
        let utc = ISO8601DateFormatter().date(from: "2026-09-12T20:09:00Z")!
        try check(ResetAnnouncementDisplay.beijingDate(utc) == "2026-09-13 04:09", "Beijing dates must convert correctly across UTC dates")
        return checks + (try ResetAnnouncementSummary.runSelfChecks()) + (try ResetCheckPresentation.runSelfChecks())
            + (try ResetPendingAnnouncements.runSelfChecks())
    }

    @MainActor private static func refresh(_ monitor: ResetMonitor) async throws {
        monitor.refresh()
        for _ in 0..<200 {
            if !monitor.isChecking { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        throw CheckError(message: "Local fixture refresh timed out")
    }

    private struct CheckError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private final class CheckStore: ResetLedgerStoring {
        var ledger: ResetLedger?
        var failSave = false
        func load() throws -> ResetLedger? { ledger }
        func save(_ candidate: ResetLedger) throws {
            if failSave { throw CocoaError(.fileWriteNoPermission) }
            ledger = candidate
        }
    }
}
