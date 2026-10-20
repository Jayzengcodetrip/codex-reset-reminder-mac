import Foundation
import XCTest
@testable import CodexNotch

final class ResetManualTimerRestartTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testStandaloneRestartPersistsWithoutChangingPublicRecordsOrPendingPreviews() throws {
        var ledger = initialLedger()
        let original = ledger
        let clickedAt = now.addingTimeInterval(0.75)
        XCTAssertTrue(ledger.restartResetTimerManually(at: clickedAt))
        XCTAssertEqual(ledger.records, original.records)
        XCTAssertEqual(ledger.versions, original.versions)
        XCTAssertEqual(ledger.pendingAnnouncements, original.pendingAnnouncements)
        XCTAssertEqual(ledger.lastSuccessfulCheck, original.lastSuccessfulCheck)
        XCTAssertEqual(ledger.schemaVersion, 1)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ResetLedgerStore(url: directory.appendingPathComponent("ledger.json"))
        try store.save(ledger)
        var restored = try XCTUnwrap(store.load())
        XCTAssertEqual(restored, ledger)
        XCTAssertTrue(restored.ingest(snapshot([]), at: now.addingTimeInterval(120),
                                      occurredWhileAway: false).isEmpty)
        XCTAssertEqual(restored.manualTimerRestartedAt, clickedAt)
        XCTAssertEqual(restored.records, original.records)
        XCTAssertEqual(restored.pendingAnnouncements, original.pendingAnnouncements)
    }

    func testSchemaOneWithoutStandaloneTimerStillLoadsAndRejectsInvalidClickDates() throws {
        let ledger = initialLedger()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger)) as? [String: Any])
        json.removeValue(forKey: "manualTimerRestartedAt")
        var restored = try JSONDecoder().decode(ResetLedger.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored, ledger)
        XCTAssertNil(restored.manualTimerRestartedAt)
        for interval in [Double.nan, .infinity, -.infinity, 0, -1] {
            XCTAssertFalse(restored.restartResetTimerManually(at: Date(timeIntervalSince1970: interval)))
            XCTAssertEqual(restored, ledger)
        }
    }

    func testStandaloneTimerNeverCompletesOrArchivesDatedAndUndatedPreviews() {
        let ledger = initialLedger()
        let result = ResetTopPresentation.make(pending: ledger.pendingAnnouncements, records: ledger.records,
            now: now.addingTimeInterval(91), manualTimerRestartedAt: now)
        XCTAssertEqual(result.latestDeliveryOrigin, .manualTimerRestart)
        XCTAssertEqual(result.secondsSinceLastDelivery, 91)
        XCTAssertFalse(result.didResetToday)
        XCTAssertEqual(result.announcements.map(\.id), ["dated"])
        XCTAssertEqual(result.undatedAnnouncements.map(\.id), ["undated"])
        XCTAssertTrue(result.archivedUndated.isEmpty)
        XCTAssertTrue(result.archivedForAccountReceipt.isEmpty)
        XCTAssertEqual(result.emptyText(language: .chinese), "暂无最新重置预告")
        XCTAssertTrue(ledger.records.allSatisfy { $0.manualCompletedAt == nil && $0.announcement.deliveryAt == nil })
    }

    func testOlderSignalsCannotMoveStandaloneTimerButNewerIndependentSignalsCan() {
        let clickedAt = now.addingTimeInterval(-60)
        for age: TimeInterval in [120, 60, 10] {
            let newer = age < 60
            let publicResult = ResetTopPresentation.make(pending: [], records: [record(delivery(age: age))], now: now,
                manualTimerRestartedAt: clickedAt)
            XCTAssertEqual(publicResult.latestDeliveryOrigin, newer ? .publicAnnouncement : .manualTimerRestart)
            XCTAssertEqual(publicResult.secondsSinceLastDelivery, newer ? 10 : 60)

            let receiptResult = ResetTopPresentation.make(pending: [], records: [], now: now,
                accountReceipt: AccountResetReceipt(grantedAt: now.addingTimeInterval(-age)),
                manualTimerRestartedAt: clickedAt)
            XCTAssertEqual(receiptResult.latestDeliveryOrigin, newer ? .accountReceipt : .manualTimerRestart)
            XCTAssertEqual(receiptResult.secondsSinceLastDelivery, newer ? 10 : 60)

            let recoveryResult = ResetTopPresentation.make(pending: [], records: [], now: now,
                accountRecovery: AccountQuotaRecoveryState(latestConfirmed: recovery(.weekly, age: age)),
                manualTimerRestartedAt: clickedAt)
            XCTAssertEqual(recoveryResult.latestDeliveryOrigin, newer ? .accountRecovery(.weekly) : .manualTimerRestart)
            XCTAssertEqual(recoveryResult.secondsSinceLastDelivery, newer ? 10 : 60)
        }
    }

    func testAnnouncementConfirmationAndUndoDoNotEraseStandaloneClock() {
        var ledger = initialLedger()
        XCTAssertTrue(ledger.restartResetTimerManually(at: now.addingTimeInterval(-60)))
        XCTAssertTrue(ledger.confirmResetManually(id: "dated", at: now.addingTimeInterval(-10)))
        let confirmed = ResetTopPresentation.make(pending: ledger.pendingAnnouncements, records: ledger.records, now: now,
            manualTimerRestartedAt: ledger.manualTimerRestartedAt)
        XCTAssertEqual(confirmed.latestDeliveryOrigin, .manualConfirmation)
        XCTAssertEqual(confirmed.secondsSinceLastDelivery, 10)
        XCTAssertTrue(ledger.undoManualResetConfirmation(id: "dated"))
        let undone = ResetTopPresentation.make(pending: ledger.pendingAnnouncements, records: ledger.records, now: now,
            manualTimerRestartedAt: ledger.manualTimerRestartedAt)
        XCTAssertEqual(undone.latestDeliveryOrigin, .manualTimerRestart)
        XCTAssertEqual(undone.secondsSinceLastDelivery, 60)
        XCTAssertEqual(undone.announcements.map(\.id), ["dated"])
    }

    func testRestartHidesOnlyOlderUnconfirmedAccountRecovery() {
        for age: TimeInterval in [120, 60, 10] {
            let pendingRecovery = recovery(.unconfirmed, age: age)
            let result = ResetTopPresentation.make(pending: [], records: [], now: now,
                accountRecovery: AccountQuotaRecoveryState(latestUnconfirmed: pendingRecovery),
                manualTimerRestartedAt: now.addingTimeInterval(-60))
            XCTAssertEqual(result.latestDeliveryOrigin, .manualTimerRestart)
            XCTAssertEqual(result.secondsSinceLastDelivery, 60)
            XCTAssertEqual(result.unconfirmedAccountRecovery, age < 60 ? pendingRecovery : nil)
        }
    }

    func testFutureAndInvalidSavedAnchorsCannotReplaceOfficialClockOrHideUnconfirmedRecovery() {
        let pendingRecovery = recovery(.unconfirmed, age: 120)
        let invalid = [Date(timeIntervalSince1970: .nan), Date(timeIntervalSince1970: .infinity),
                       Date(timeIntervalSince1970: -.infinity), Date(timeIntervalSince1970: 0),
                       Date(timeIntervalSince1970: -1), now.addingTimeInterval(60)]
        for anchor in invalid {
            let result = ResetTopPresentation.make(pending: [], records: [record(delivery(age: 3600))], now: now,
                accountRecovery: AccountQuotaRecoveryState(latestUnconfirmed: pendingRecovery),
                manualTimerRestartedAt: anchor)
            XCTAssertEqual(result.latestDeliveryOrigin, .publicAnnouncement)
            XCTAssertEqual(result.secondsSinceLastDelivery, 3600)
            XCTAssertEqual(result.unconfirmedAccountRecovery, pendingRecovery)
        }
    }

    private func initialLedger() -> ResetLedger {
        var ledger = ResetLedger()
        _ = ledger.ingest(snapshot([
            ResetAnnouncement(id: "dated", title: "Synthetic dated preview", summary: "Synthetic fixture",
                sourceURL: URL(string: "https://x.com/thsottiaux/status/93001"),
                announcedAt: now.addingTimeInterval(-300), scheduledFor: now.addingTimeInterval(3600),
                kind: "regular", scope: "broad", status: "scheduled"),
            ResetAnnouncement(id: "undated", title: "Synthetic undated preview", summary: "More resets coming",
                sourceURL: URL(string: "https://x.com/thsottiaux/status/93002"),
                announcedAt: now.addingTimeInterval(-200), scheduledFor: nil,
                kind: "regular", scope: "broad", status: "scheduled")
        ]), at: now.addingTimeInterval(-120), occurredWhileAway: true)
        return ledger
    }

    private func snapshot(_ posts: [ResetAnnouncement]) -> NextResetSnapshot {
        NextResetSnapshot(announcements: posts, sourceCheckedAt: now, sourceIsFresh: true)
    }

    private func delivery(age: TimeInterval) -> ResetAnnouncement {
        ResetAnnouncement(id: "delivery", title: "Synthetic public delivery", summary: "Synthetic fixture",
            sourceURL: URL(string: "https://x.com/thsottiaux/status/93003"),
            announcedAt: now.addingTimeInterval(-age), scheduledFor: nil,
            kind: "regular", scope: "broad", status: "completed",
            deliveryAt: now.addingTimeInterval(-age), deliveryKind: "regular")
    }

    private func record(_ announcement: ResetAnnouncement) -> ResetRecord {
        ResetRecord(id: announcement.id, announcement: announcement, isUnread: true, occurredWhileAway: true)
    }

    private func recovery(_ kind: AccountQuotaRecoveryKind, age: TimeInterval) -> AccountQuotaRecovery {
        AccountQuotaRecovery(observedFrom: now.addingTimeInterval(-age - 60),
            observedThrough: now.addingTimeInterval(-age), detectedAt: now.addingTimeInterval(-age),
            confirmedAt: now.addingTimeInterval(-age + 1), kind: kind,
            uncertainty: kind == .unconfirmed ? .insufficientEvidence : nil,
            redeemedAt: nil, publicCompletionID: nil)
    }
}
