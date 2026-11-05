import Foundation
import XCTest
@testable import CodexNotch

@MainActor
final class ResetMarkAllReadTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testBulkAcknowledgementPreservesHistoryOrderPreviewsAndElapsedClock() {
        var ledger = initialLedger()
        // Exercise acknowledgement independently of the normal publication sort.
        ledger.records.reverse()
        let original = ledger
        let originalPending = ledger.pendingAnnouncements
        let originalPresentation = presentation(ledger)

        XCTAssertTrue(ledger.markAllRead())
        XCTAssertTrue(ledger.records.allSatisfy { !$0.isUnread && !$0.occurredWhileAway })
        XCTAssertEqual(ledger.records.map(\.id), original.records.map(\.id))
        XCTAssertEqual(ledger.records.map(\.announcement), original.records.map(\.announcement))
        XCTAssertEqual(ledger.records.map(\.manualCompletedAt), original.records.map(\.manualCompletedAt))
        XCTAssertEqual(ledger.versions, original.versions)
        XCTAssertEqual(ledger.pendingAnnouncements, originalPending)
        XCTAssertEqual(presentation(ledger), originalPresentation)
        XCTAssertEqual(ledger.manualTimerRestartedAt, original.manualTimerRestartedAt)
        XCTAssertEqual(ledger.lastSuccessfulCheck, original.lastSuccessfulCheck)
        XCTAssertEqual(ledger.sourceCheckedAt, original.sourceCheckedAt)
        XCTAssertEqual(ledger.sourceIsFresh, original.sourceIsFresh)
        XCTAssertEqual(ledger.schemaVersion, original.schemaVersion)
        XCTAssertEqual(ledger.baselineCompleted, original.baselineCompleted)
        XCTAssertEqual(ledger.deliveryEvidenceBaselineCompleted, original.deliveryEvidenceBaselineCompleted)
        let acknowledged = ledger
        XCTAssertFalse(ledger.markAllRead())
        XCTAssertEqual(ledger, acknowledged)
    }

    func testSavedAcknowledgementSurvivesDiskReloadAndFailedFeedCheck() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexNotch-MarkAllRead-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ResetLedgerStore(url: directory.appendingPathComponent("ledger.json"))
        let initial = initialLedger()
        try store.save(initial)
        let first = ResetMonitor(store: store, fetchSnapshot: { self.snapshot() }, now: { self.now })
        defer { first.stop() }
        XCTAssertTrue(first.markAllRead())
        let saved = try XCTUnwrap(store.load())
        XCTAssertEqual(saved.records, first.records)
        XCTAssertEqual(saved.manualTimerRestartedAt, initial.manualTimerRestartedAt)
        XCTAssertEqual(saved.versions, initial.versions)

        let restarted = ResetMonitor(store: store,
            fetchSnapshot: { throw URLError(.notConnectedToInternet) }, now: { self.now })
        defer { restarted.stop() }
        XCTAssertEqual(restarted.records, first.records)
        XCTAssertFalse(restarted.canMarkAllRead)
        XCTAssertEqual(restarted.pendingAnnouncements, first.pendingAnnouncements)
        restarted.refresh()
        await finish(restarted)
        XCTAssertNotNil(restarted.errorMessage)
        XCTAssertEqual(restarted.unreadCount, 0)
        XCTAssertEqual(restarted.awayUnreadCount, 0)
        XCTAssertEqual(restarted.lastSuccessfulCheck, initial.lastSuccessfulCheck)
        XCTAssertEqual(try store.load(), saved)
    }

    func testSaveFailureKeepsPublishedStateAndFeedErrorThenRetryIsAtomicAndIdempotent() async {
        let initial = initialLedger()
        let store = MarkAllReadMemoryStore(ledger: initial)
        let monitor = ResetMonitor(store: store,
            fetchSnapshot: { throw URLError(.notConnectedToInternet) }, now: { self.now })
        defer { monitor.stop() }
        monitor.refresh()
        await finish(monitor)
        let feedError = monitor.errorMessage
        let successfulCheck = monitor.lastSuccessfulCheck
        let originalPending = monitor.pendingAnnouncements
        var notifications = 0
        monitor.onNotify = { _ in notifications += 1 }
        store.beforeSave = {
            XCTAssertEqual(monitor.records, initial.records,
                           "Do not publish a candidate before atomic storage succeeds")
        }
        store.failSave = true

        XCTAssertTrue(monitor.canMarkAllRead)
        XCTAssertFalse(monitor.markAllRead())
        XCTAssertEqual(monitor.records, initial.records)
        XCTAssertEqual(store.ledger, initial)
        XCTAssertNotNil(monitor.readStateErrorMessage)
        XCTAssertEqual(monitor.errorMessage, feedError)
        XCTAssertEqual(monitor.lastSuccessfulCheck, successfulCheck)
        monitor.clearReadStateError()
        XCTAssertNil(monitor.readStateErrorMessage)
        XCTAssertEqual(monitor.records, initial.records)

        store.failSave = false
        XCTAssertTrue(monitor.markAllRead())
        XCTAssertEqual(monitor.unreadCount, 0)
        XCTAssertEqual(monitor.awayUnreadCount, 0)
        XCTAssertFalse(monitor.canMarkAllRead)
        XCTAssertNil(monitor.readStateErrorMessage)
        XCTAssertEqual(monitor.pendingAnnouncements, originalPending)
        XCTAssertEqual(monitor.manualTimerRestartedAt, initial.manualTimerRestartedAt)
        XCTAssertEqual(monitor.errorMessage, feedError)
        XCTAssertEqual(monitor.lastSuccessfulCheck, successfulCheck)
        XCTAssertEqual(store.ledger?.records, monitor.records)
        let saves = store.saveCount
        store.beforeSave = { XCTFail("Already-read records must not trigger a storage write") }
        XCTAssertFalse(monitor.markAllRead())
        XCTAssertEqual(store.saveCount, saves)
        XCTAssertEqual(notifications, 0)
    }

    func testUnreadableLedgerCannotBeOverwrittenByBulkOrSingleAcknowledgement() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexNotch-UnreadableReadState-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("ledger.json")
        let invalidLedger = Data("{synthetic invalid ledger".utf8)
        try invalidLedger.write(to: url)
        let monitor = ResetMonitor(store: ResetLedgerStore(url: url),
            fetchSnapshot: { self.snapshot() }, now: { self.now })
        defer { monitor.stop() }
        let feedError = monitor.errorMessage
        XCTAssertNotNil(feedError)
        XCTAssertFalse(monitor.canMarkAllRead)
        XCTAssertFalse(monitor.markAllRead())
        XCTAssertNotNil(monitor.readStateErrorMessage)
        monitor.markRead(id: "first")
        XCTAssertEqual(monitor.errorMessage, feedError)
        XCTAssertTrue(monitor.records.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), invalidLedger)
    }

    func testInFlightRefreshPreservesOldAcknowledgementButNotNewOrRevisedMessages() async {
        let store = MarkAllReadMemoryStore(ledger: initialLedger())
        var requestCount = 0
        var continuation: CheckedContinuation<NextResetSnapshot, Error>?
        let monitor = ResetMonitor(store: store, fetchSnapshot: {
            requestCount += 1
            if requestCount == 1 { return self.snapshot() }
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }, now: { self.now }, idleSeconds: { 0 }, minimumRefreshInterval: 0)
        defer { monitor.stop() }
        // The first check is intentionally a quiet catch-up; test active-use
        // notifications only after that initial check completes.
        monitor.refresh()
        await finish(monitor)
        var notifications: [ResetRecord] = []
        monitor.onNotify = { notifications.append(contentsOf: $0) }
        monitor.refresh()
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        guard let response = continuation else {
            XCTFail("Synthetic request did not suspend")
            return
        }
        XCTAssertTrue(monitor.markAllRead())
        XCTAssertEqual(monitor.unreadCount, 0)
        var incoming = snapshot().announcements
        incoming[0].scheduledFor = now.addingTimeInterval(7_200)
        incoming.append(announcement(id: "new", publishedAgo: 0, deadlineIn: 3_600))
        response.resume(returning: NextResetSnapshot(announcements: incoming,
            sourceCheckedAt: now, sourceIsFresh: true))
        await finish(monitor)

        XCTAssertEqual(Set(monitor.records.filter(\.isUnread).map(\.id)), ["first", "new"])
        XCTAssertEqual(monitor.records.first { $0.id == "second" }?.isUnread, false)
        XCTAssertEqual(monitor.records.first { $0.id == "second" }?.occurredWhileAway, false)
        XCTAssertEqual(Set(notifications.map(\.id)), ["first", "new"])
        XCTAssertEqual(notifications.count, 2)
        XCTAssertTrue(monitor.canMarkAllRead)
        XCTAssertEqual(store.ledger?.records, monitor.records)
        XCTAssertEqual(store.ledger?.manualTimerRestartedAt, initialLedger().manualTimerRestartedAt)
    }

    func testSameSnapshotAfterRestartDoesNotReplayAcknowledgedMessages() async {
        let store = MarkAllReadMemoryStore(ledger: initialLedger())
        let first = ResetMonitor(store: store, fetchSnapshot: { self.snapshot() }, now: { self.now })
        defer { first.stop() }
        XCTAssertTrue(first.markAllRead())
        let restarted = ResetMonitor(store: store, fetchSnapshot: { self.snapshot() },
            now: { self.now }, idleSeconds: { 0 }, minimumRefreshInterval: 0)
        defer { restarted.stop() }
        var notificationCount = 0
        restarted.onNotify = { notificationCount += $0.count }
        for _ in 0..<2 {
            restarted.refresh()
            await finish(restarted)
        }
        XCTAssertEqual(restarted.records, first.records)
        XCTAssertEqual(restarted.unreadCount, 0)
        XCTAssertEqual(restarted.awayUnreadCount, 0)
        XCTAssertFalse(restarted.canMarkAllRead)
        XCTAssertEqual(notificationCount, 0)
    }

    func testUnreadAndAwayFiltersEmptyWithoutChangingSelectionOrHistory() {
        let store = MarkAllReadMemoryStore(ledger: initialLedger())
        let monitor = ResetMonitor(store: store, fetchSnapshot: { self.snapshot() }, now: { self.now })
        defer { monitor.stop() }
        let navigation = ResetAnnouncementsNavigation()
        navigation.selectRecord(id: "second", markRead: { _ in })
        navigation.filter = .unread
        XCTAssertFalse(navigation.visibleRecords(from: monitor.records, undated: []).isEmpty)
        navigation.filter = .away
        XCTAssertFalse(navigation.visibleRecords(from: monitor.records, undated: []).isEmpty)

        XCTAssertTrue(monitor.markAllRead())
        for filter in [ResetAnnouncementFilter.unread, .away] {
            navigation.filter = filter
            XCTAssertTrue(navigation.visibleRecords(from: monitor.records, undated: []).isEmpty)
            XCTAssertEqual(navigation.selectedID, "second")
        }
        navigation.filter = .all
        XCTAssertEqual(navigation.visibleRecords(from: monitor.records, undated: []).count, 3)
        XCTAssertEqual(navigation.selectedID, "second")
    }

    func testAwayOnlyFlagStillEnablesAcknowledgementAndEmptyLedgerDoesNotWrite() {
        var ledger = initialLedger()
        ledger.records = [ledger.records[2]]
        XCTAssertFalse(ledger.records[0].isUnread)
        XCTAssertTrue(ledger.records[0].occurredWhileAway)
        let store = MarkAllReadMemoryStore(ledger: ledger)
        let monitor = ResetMonitor(store: store, fetchSnapshot: { self.snapshot() }, now: { self.now })
        defer { monitor.stop() }
        XCTAssertEqual(monitor.unreadCount, 0)
        XCTAssertTrue(monitor.canMarkAllRead)
        XCTAssertTrue(monitor.markAllRead())
        XCTAssertFalse(monitor.records[0].occurredWhileAway)
        XCTAssertFalse(monitor.canMarkAllRead)

        let emptyStore = MarkAllReadMemoryStore(ledger: ResetLedger())
        let empty = ResetMonitor(store: emptyStore, fetchSnapshot: { self.snapshot() }, now: { self.now })
        defer { empty.stop() }
        XCTAssertFalse(empty.canMarkAllRead)
        XCTAssertFalse(empty.markAllRead())
        XCTAssertEqual(emptyStore.saveCount, 0)
    }

    func testSingleReadFailureUsesIndependentErrorAndPublishesOnlyAfterRetry() {
        let initial = initialLedger()
        let store = MarkAllReadMemoryStore(ledger: initial)
        let monitor = ResetMonitor(store: store, fetchSnapshot: { self.snapshot() }, now: { self.now })
        defer { monitor.stop() }
        store.beforeSave = { XCTAssertEqual(monitor.records, initial.records) }
        store.failSave = true
        monitor.markRead(id: "first")
        XCTAssertEqual(monitor.records, initial.records)
        XCTAssertEqual(store.ledger, initial)
        XCTAssertNotNil(monitor.readStateErrorMessage)
        XCTAssertNil(monitor.errorMessage)
        XCTAssertEqual(monitor.lastSuccessfulCheck, initial.lastSuccessfulCheck)
        store.failSave = false
        monitor.markRead(id: "first")
        XCTAssertNil(monitor.readStateErrorMessage)
        XCTAssertEqual(monitor.records.first { $0.id == "first" }?.isUnread, false)
        XCTAssertEqual(monitor.records.first { $0.id == "first" }?.occurredWhileAway, false)
        XCTAssertEqual(monitor.records.first { $0.id == "second" }?.isUnread, true)
        XCTAssertEqual(store.ledger?.records, monitor.records)
        let saves = store.saveCount
        monitor.markRead(id: "first")
        monitor.markRead(id: "missing")
        XCTAssertEqual(store.saveCount, saves)
    }

    private func initialLedger() -> ResetLedger {
        let first = announcement(id: "first", publishedAgo: 100, deadlineIn: 600)
        let second = announcement(id: "second", publishedAgo: 200, deadlineIn: 1_200)
        let confirmed = announcement(id: "confirmed", publishedAgo: 300, deadlineIn: -120)
        var ledger = ResetLedger()
        ledger.baselineCompleted = true
        ledger.deliveryEvidenceBaselineCompleted = true
        ledger.manualTimerRestartedAt = now.addingTimeInterval(-30)
        ledger.records = [
            ResetRecord(id: first.id, announcement: first, isUnread: true, occurredWhileAway: true),
            ResetRecord(id: second.id, announcement: second, isUnread: true, occurredWhileAway: false),
            ResetRecord(id: confirmed.id, announcement: confirmed, isUnread: false, occurredWhileAway: true,
                        manualCompletedAt: now.addingTimeInterval(-90))
        ]
        ledger.versions = Dictionary(uniqueKeysWithValues: ledger.records.map { ($0.id, [$0.announcement]) })
        ledger.lastSuccessfulCheck = now.addingTimeInterval(-10)
        ledger.sourceCheckedAt = now.addingTimeInterval(-20)
        ledger.sourceIsFresh = true
        return ledger
    }

    private func announcement(id: String, publishedAgo: TimeInterval, deadlineIn: TimeInterval) -> ResetAnnouncement {
        ResetAnnouncement(id: id, title: "Synthetic reset \(id)", summary: "Synthetic test fixture \(id)",
            sourceURL: URL(string: "https://example.com/reset/\(id)"),
            announcedAt: now.addingTimeInterval(-publishedAgo), scheduledFor: now.addingTimeInterval(deadlineIn),
            kind: "regular", scope: "unspecified", status: "scheduled")
    }

    private func snapshot() -> NextResetSnapshot {
        NextResetSnapshot(announcements: initialLedger().records.map(\.announcement),
            sourceCheckedAt: now, sourceIsFresh: true)
    }

    private func presentation(_ ledger: ResetLedger) -> ResetTopPresentation {
        ResetTopPresentation.make(pending: ledger.pendingAnnouncements, records: ledger.records, now: now,
                                  manualTimerRestartedAt: ledger.manualTimerRestartedAt)
    }

    private func finish(_ monitor: ResetMonitor) async {
        for _ in 0..<100 {
            if !monitor.isChecking { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Synthetic refresh did not finish")
    }
}

private final class MarkAllReadMemoryStore: ResetLedgerStoring {
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
