import Foundation
import XCTest
@testable import CodexNotch

@MainActor
final class ResetManualTimerRestartMonitorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRepeatedExplicitClicksRestartClockWithoutNotificationsOrAnnouncementChanges() {
        let store = TimerRestartMemoryStore(ledger: initialLedger())
        var clock = now
        let monitor = ResetMonitor(store: store, fetchSnapshot: { self.snapshot() }, now: { clock })
        let originalRecords = monitor.records
        let originalPending = monitor.pendingAnnouncements
        var notifications = 0
        monitor.onNotify = { _ in notifications += 1 }
        XCTAssertTrue(monitor.restartResetTimerManually())
        XCTAssertEqual(monitor.manualTimerRestartedAt, now)
        clock.addTimeInterval(100)
        XCTAssertTrue(monitor.restartResetTimerManually())
        XCTAssertEqual(monitor.manualTimerRestartedAt, clock)
        XCTAssertEqual(store.ledger?.manualTimerRestartedAt, clock)
        XCTAssertEqual(store.saveCount, 2)
        XCTAssertEqual(monitor.records, originalRecords)
        XCTAssertEqual(monitor.pendingAnnouncements, originalPending)
        XCTAssertFalse(monitor.hasNewPreannouncement)
        XCTAssertEqual(notifications, 0)
    }

    func testSaveFailureLeavesPreviousAnchorAndFeedStatusUntilSuccessfulRetry() {
        var initial = initialLedger()
        initial.manualTimerRestartedAt = now.addingTimeInterval(-60)
        let store = TimerRestartMemoryStore(ledger: initial)
        let monitor = ResetMonitor(store: store, fetchSnapshot: { self.snapshot() }, now: { self.now })
        let originalCheck = monitor.lastSuccessfulCheck
        store.beforeSave = {
            XCTAssertEqual(monitor.manualTimerRestartedAt, initial.manualTimerRestartedAt,
                           "The candidate must not be published before storage succeeds")
        }
        store.failSave = true
        XCTAssertFalse(monitor.restartResetTimerManually())
        XCTAssertEqual(monitor.manualTimerRestartedAt, initial.manualTimerRestartedAt)
        XCTAssertEqual(store.ledger, initial)
        XCTAssertEqual(monitor.lastSuccessfulCheck, originalCheck)
        XCTAssertEqual(monitor.records, initial.records)
        XCTAssertNil(monitor.errorMessage)
        XCTAssertNotNil(monitor.manualConfirmationErrorMessage)
        store.failSave = false
        XCTAssertTrue(monitor.restartResetTimerManually())
        XCTAssertEqual(monitor.manualTimerRestartedAt, now)
        XCTAssertEqual(store.ledger?.manualTimerRestartedAt, now)
        XCTAssertNil(monitor.manualConfirmationErrorMessage)
        XCTAssertEqual(monitor.lastSuccessfulCheck, originalCheck)
    }

    func testSavedStandaloneClockSurvivesRestartAndFailedFeedCheck() async {
        let store = TimerRestartMemoryStore(ledger: initialLedger())
        let first = ResetMonitor(store: store, fetchSnapshot: { self.snapshot() }, now: { self.now })
        XCTAssertTrue(first.restartResetTimerManually())
        let restarted = ResetMonitor(store: store,
            fetchSnapshot: { throw URLError(.notConnectedToInternet) }, now: { self.now })
        defer { restarted.stop() }
        XCTAssertEqual(restarted.manualTimerRestartedAt, now)
        restarted.refresh()
        await finish(restarted)
        XCTAssertEqual(restarted.manualTimerRestartedAt, now)
        XCTAssertEqual(restarted.records, first.records)
        XCTAssertEqual(restarted.pendingAnnouncements, first.pendingAnnouncements)
        XCTAssertEqual(store.ledger?.manualTimerRestartedAt, now)
        XCTAssertNotNil(restarted.errorMessage)
    }

    func testRestartDuringInFlightRefreshSurvivesSuccessfulOldResponse() async {
        let store = TimerRestartMemoryStore(ledger: initialLedger())
        var continuation: CheckedContinuation<NextResetSnapshot, Error>?
        let monitor = ResetMonitor(store: store, fetchSnapshot: {
            try await withCheckedThrowingContinuation { continuation = $0 }
        }, now: { self.now }, idleSeconds: { 0 }, minimumRefreshInterval: 0)
        defer { monitor.stop() }
        let originalRecords = monitor.records
        var notifications = 0
        monitor.onNotify = { _ in notifications += 1 }
        monitor.refresh()
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        XCTAssertNotNil(continuation)
        XCTAssertTrue(monitor.restartResetTimerManually())
        continuation?.resume(returning: snapshot())
        await finish(monitor)
        XCTAssertEqual(monitor.manualTimerRestartedAt, now)
        XCTAssertEqual(store.ledger?.manualTimerRestartedAt, now)
        XCTAssertEqual(monitor.records, originalRecords)
        XCTAssertEqual(monitor.pendingAnnouncements.count, 1)
        XCTAssertEqual(notifications, 0)
    }

    func testUnreadLedgerLoadFailureAndInvalidSystemClockCannotOverwriteStorage() {
        let store = TimerRestartMemoryStore(ledger: initialLedger())
        store.failLoad = true
        let unreadable = ResetMonitor(store: store, fetchSnapshot: { self.snapshot() }, now: { self.now })
        XCTAssertFalse(unreadable.restartResetTimerManually())
        XCTAssertNotNil(unreadable.manualConfirmationErrorMessage)
        XCTAssertNil(store.ledger?.manualTimerRestartedAt)
        XCTAssertEqual(store.saveCount, 0)
        store.failLoad = false
        let invalid = ResetMonitor(store: store, fetchSnapshot: { self.snapshot() },
                                   now: { Date(timeIntervalSince1970: .nan) })
        XCTAssertFalse(invalid.restartResetTimerManually())
        XCTAssertNotNil(invalid.manualConfirmationErrorMessage)
        XCTAssertNil(store.ledger?.manualTimerRestartedAt)
        XCTAssertEqual(store.saveCount, 0)
    }

    private func initialLedger() -> ResetLedger {
        var ledger = ResetLedger()
        _ = ledger.ingest(snapshot(), at: now.addingTimeInterval(-120), occurredWhileAway: true)
        return ledger
    }

    private func snapshot() -> NextResetSnapshot {
        let post = ResetAnnouncement(id: "preview", title: "Synthetic reset preview", summary: "Synthetic fixture",
            sourceURL: URL(string: "https://x.com/thsottiaux/status/94001"),
            announcedAt: now.addingTimeInterval(-300), scheduledFor: now.addingTimeInterval(600),
            kind: "regular", scope: "unspecified", status: "scheduled")
        return NextResetSnapshot(announcements: [post], sourceCheckedAt: now, sourceIsFresh: true)
    }

    private func finish(_ monitor: ResetMonitor) async {
        for _ in 0..<100 {
            if !monitor.isChecking { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Synthetic refresh did not finish")
    }
}

private final class TimerRestartMemoryStore: ResetLedgerStoring {
    var ledger: ResetLedger?
    var failSave = false
    var failLoad = false
    var saveCount = 0
    var beforeSave: (() -> Void)?
    init(ledger: ResetLedger?) { self.ledger = ledger }
    func load() throws -> ResetLedger? {
        if failLoad { throw CocoaError(.fileReadNoPermission) }
        return ledger
    }
    func save(_ value: ResetLedger) throws {
        saveCount += 1
        beforeSave?()
        if failSave { throw CocoaError(.fileWriteNoPermission) }
        ledger = value
    }
}
