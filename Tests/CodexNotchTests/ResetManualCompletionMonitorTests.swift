import Foundation
import XCTest
@testable import CodexNotch

@MainActor
final class ResetManualCompletionMonitorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFailedConfirmationAndUndoSaveLeaveMemoryAndTimerUnchanged() {
        let store = ManualCompletionMemoryStore(ledger: initialLedger())
        var clock = now
        let monitor = ResetMonitor(store: store, fetchSnapshot: { self.snapshot() }, now: { clock })
        var notifications = 0
        monitor.onNotify = { _ in notifications += 1 }
        let original = monitor.records
        store.failSave = true
        XCTAssertFalse(monitor.confirmResetManually(id: "preview"))
        XCTAssertEqual(monitor.records, original)
        XCTAssertEqual(monitor.pendingAnnouncements.count, 1)
        XCTAssertNotNil(monitor.manualConfirmationErrorMessage)
        XCTAssertNil(monitor.errorMessage)
        store.failSave = false
        XCTAssertTrue(monitor.confirmResetManually(id: "preview"))
        XCTAssertNil(monitor.manualConfirmationErrorMessage)
        XCTAssertEqual(monitor.records[0].manualCompletedAt, now)
        clock.addTimeInterval(100)
        XCTAssertFalse(monitor.confirmResetManually(id: "preview"))
        XCTAssertEqual(monitor.records[0].manualCompletedAt, now)
        store.failSave = true
        XCTAssertFalse(monitor.undoManualResetConfirmation(id: "preview"))
        XCTAssertEqual(monitor.records[0].manualCompletedAt, now)
        XCTAssertNotNil(monitor.manualConfirmationErrorMessage)
        XCTAssertTrue(monitor.pendingAnnouncements.isEmpty)
        store.failSave = false
        XCTAssertTrue(monitor.undoManualResetConfirmation(id: "preview"))
        XCTAssertNil(monitor.records[0].manualCompletedAt)
        XCTAssertNil(monitor.manualConfirmationErrorMessage)
        XCTAssertEqual(monitor.pendingAnnouncements.count, 1)
        XCTAssertEqual(notifications, 0)
    }

    func testSavedConfirmationSurvivesMonitorRestartWithoutNetwork() {
        let store = ManualCompletionMemoryStore(ledger: initialLedger())
        let monitor = ResetMonitor(store: store, fetchSnapshot: { throw URLError(.notConnectedToInternet) }, now: { self.now })
        XCTAssertTrue(monitor.confirmResetManually(id: "preview"))
        let restarted = ResetMonitor(store: store, fetchSnapshot: { throw URLError(.notConnectedToInternet) }, now: { self.now })
        XCTAssertTrue(restarted.pendingAnnouncements.isEmpty)
        XCTAssertEqual(restarted.records[0].manualCompletedAt, now)
        XCTAssertEqual(restarted.records[0].isUnread, monitor.records[0].isUnread)
    }

    func testConfirmationDuringInFlightRefreshIsNotOverwrittenByOldResponse() async {
        let store = ManualCompletionMemoryStore(ledger: initialLedger())
        var continuation: CheckedContinuation<NextResetSnapshot, Error>?
        let monitor = ResetMonitor(store: store, fetchSnapshot: {
            try await withCheckedThrowingContinuation { continuation = $0 }
        }, now: { self.now }, idleSeconds: { 0 }, minimumRefreshInterval: 0)
        defer { monitor.stop() }
        var notifications = 0
        monitor.onNotify = { _ in notifications += 1 }
        monitor.refresh()
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        XCTAssertNotNil(continuation)
        XCTAssertTrue(monitor.confirmResetManually(id: "preview"))
        continuation?.resume(returning: snapshot())
        await finish(monitor)
        XCTAssertEqual(monitor.records[0].manualCompletedAt, now)
        XCTAssertEqual(store.ledger?.records[0].manualCompletedAt, now)
        XCTAssertTrue(monitor.pendingAnnouncements.isEmpty)
        XCTAssertEqual(notifications, 0)
    }

    func testUndoDuringInFlightRefreshDoesNotRestoreSavedManualCompletion() async {
        var ledger = initialLedger()
        XCTAssertTrue(ledger.confirmResetManually(id: "preview", at: now))
        let store = ManualCompletionMemoryStore(ledger: ledger)
        var continuation: CheckedContinuation<NextResetSnapshot, Error>?
        let monitor = ResetMonitor(store: store, fetchSnapshot: {
            try await withCheckedThrowingContinuation { continuation = $0 }
        }, now: { self.now }, idleSeconds: { 0 }, minimumRefreshInterval: 0)
        defer { monitor.stop() }
        monitor.refresh()
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        XCTAssertNotNil(continuation)
        XCTAssertTrue(monitor.undoManualResetConfirmation(id: "preview"))
        continuation?.resume(returning: snapshot())
        await finish(monitor)
        XCTAssertNil(monitor.records[0].manualCompletedAt)
        XCTAssertNil(store.ledger?.records[0].manualCompletedAt)
        XCTAssertEqual(monitor.pendingAnnouncements.count, 1)
    }

    func testFailedLoadBlocksConfirmationWithoutReplacingUnreadLedger() {
        let store = ManualCompletionMemoryStore(ledger: initialLedger())
        store.failLoad = true
        let monitor = ResetMonitor(store: store, fetchSnapshot: { self.snapshot() }, now: { self.now })
        XCTAssertFalse(monitor.canConfirmResetManually(id: "preview"))
        XCTAssertFalse(monitor.confirmResetManually(id: "preview"))
        XCTAssertNotNil(monitor.manualConfirmationErrorMessage)
        XCTAssertNil(store.ledger?.records[0].manualCompletedAt)
        XCTAssertEqual(store.saveCount, 0)
    }

    private func initialLedger() -> ResetLedger {
        var ledger = ResetLedger()
        _ = ledger.ingest(snapshot(), at: now, occurredWhileAway: true)
        return ledger
    }

    private func snapshot() -> NextResetSnapshot {
        let post = ResetAnnouncement(id: "preview", title: "Synthetic reset preview", summary: "Synthetic original text",
                                    sourceURL: URL(string: "https://x.com/thsottiaux/status/90001"),
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

private final class ManualCompletionMemoryStore: ResetLedgerStoring {
    var ledger: ResetLedger?
    var failSave = false
    var failLoad = false
    var saveCount = 0
    init(ledger: ResetLedger?) { self.ledger = ledger }
    func load() throws -> ResetLedger? {
        if failLoad { throw CocoaError(.fileReadNoPermission) }
        return ledger
    }
    func save(_ value: ResetLedger) throws {
        saveCount += 1
        if failSave { throw CocoaError(.fileWriteNoPermission) }
        ledger = value
    }
}
