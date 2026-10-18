import Foundation
import XCTest
@testable import CodexNotch

@MainActor
final class ResetManualCompletionPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testManualCompletionUsesClickTimeAndExplicitLocalOrigin() async {
        let preview = announcement("preview", post: "91001", age: 300, pending: true)
        let manual = record(preview, confirmedAt: now)
        let previous = record(announcement("previous", post: "91002", age: 3600))
        let result = ResetTopPresentation.make(pending: [preview], records: [manual, previous], now: now)
        XCTAssertEqual(result.latestDeliveryOrigin, .manualConfirmation)
        XCTAssertEqual(result.secondsSinceLastDelivery, 0)
        XCTAssertTrue(result.announcements.isEmpty)
        XCTAssertEqual(result.emptyText(language: .chinese), "暂无最新重置预告")
        XCTAssertEqual(ResetAnnouncementEntryView.emptyHeadline(didResetToday: true,
            origin: result.latestDeliveryOrigin, language: .chinese), "暂无最新重置预告")
        XCTAssertEqual(ResetAnnouncementEntriesView.deliveryAgeHeading(origin: result.latestDeliveryOrigin,
            language: .chinese), "距上次重置已过 ")
        XCTAssertEqual(ResetAnnouncementEntriesView.deliveryFootnote(origin: result.latestDeliveryOrigin,
            language: .chinese), "人工确认完成 · 从点击确认时刻计时")
        let later = ResetTopPresentation.make(pending: [], records: [manual, previous],
                                              now: now.addingTimeInterval(91))
        XCTAssertEqual(later.secondsSinceLastDelivery, 91)
        XCTAssertEqual(manual.announcement.status, "scheduled")
        XCTAssertNil(manual.announcement.deliveryAt)
        XCTAssertTrue(manual.isUnread && manual.occurredWhileAway)
    }

    func testIndependentDatedAndUndatedPreviewsRemainAfterManualCompletion() async {
        let preview = announcement("selected", post: "91001", age: 300, pending: true)
        let dated = announcement("independent-dated", post: "91002", age: 200, pending: true)
        var undated = announcement("independent-undated", post: "91003", age: 100, pending: true)
        undated.scheduledFor = nil
        let records = [record(preview, confirmedAt: now.addingTimeInterval(-60)), record(dated), record(undated)]
        let pending = ResetPendingAnnouncements.pending(from: records)
        let result = ResetTopPresentation.make(pending: pending, records: records, now: now)
        XCTAssertEqual(result.announcements.map(\.id), [dated.id])
        XCTAssertEqual(result.undatedAnnouncements.map(\.id), [undated.id])
        XCTAssertTrue(result.archivedUndated.isEmpty)
        XCTAssertEqual(result.latestDeliveryOrigin, .manualConfirmation)
        XCTAssertEqual(result.secondsSinceLastDelivery, 60)
    }

    func testLateSamePostCompletionDoesNotRestartManualClock() async {
        let preview = announcement("preview", post: "91001", age: 300, pending: true)
        let samePost = announcement("different-feed-id", post: "91001", age: 10)
        let result = ResetTopPresentation.make(pending: [],
            records: [record(preview, confirmedAt: now.addingTimeInterval(-60)), record(samePost)], now: now)
        XCTAssertEqual(result.latestDeliveryOrigin, .manualConfirmation)
        XCTAssertEqual(result.secondsSinceLastDelivery, 60)
    }

    func testLateRelatedIDOrPostIDCompletionDoesNotRestartManualClock() async {
        let preview = announcement("preview", post: "91001", age: 300, pending: true)
        for relation in [preview.id, "91001"] {
            var completion = announcement("delivery", post: "91002", age: 10)
            completion.relatedAnnouncementIDs = [relation]
            let result = ResetTopPresentation.make(pending: [],
                records: [record(preview, confirmedAt: now.addingTimeInterval(-60)), record(completion)], now: now)
            XCTAssertEqual(result.latestDeliveryOrigin, .manualConfirmation, relation)
            XCTAssertEqual(result.secondsSinceLastDelivery, 60, relation)
        }
    }

    func testLaterIndependentOfficialResetStillUpdatesClock() async {
        let preview = announcement("preview", post: "91001", age: 300, pending: true)
        var related = announcement("related-delivery", post: "91002", age: 30)
        related.relatedAnnouncementIDs = [preview.id]
        let independent = announcement("independent-delivery", post: "91003", age: 10)
        let result = ResetTopPresentation.make(pending: [], records: [
            record(preview, confirmedAt: now.addingTimeInterval(-60)), record(related), record(independent)
        ], now: now)
        XCTAssertEqual(result.latestDeliveryOrigin, .publicAnnouncement)
        XCTAssertEqual(result.secondsSinceLastDelivery, 10)
    }

    func testUndoRestoresOfficialSourceAndPendingPreviewWithoutInventingDelivery() async {
        let preview = announcement("preview", post: "91001", age: 300, pending: true)
        let previous = announcement("previous", post: "91002", age: 3600)
        var ledger = ResetLedger()
        ledger.records = [record(preview), record(previous)]
        XCTAssertTrue(ledger.confirmResetManually(id: preview.id, at: now.addingTimeInterval(-60)))
        let confirmed = ResetTopPresentation.make(pending: ledger.pendingAnnouncements, records: ledger.records, now: now)
        XCTAssertEqual(confirmed.latestDeliveryOrigin, .manualConfirmation)
        XCTAssertTrue(ledger.undoManualResetConfirmation(id: preview.id))
        let undone = ResetTopPresentation.make(pending: ledger.pendingAnnouncements, records: ledger.records, now: now)
        XCTAssertEqual(undone.latestDeliveryOrigin, .publicAnnouncement)
        XCTAssertEqual(undone.secondsSinceLastDelivery, 3600)
        XCTAssertEqual(undone.announcements.map(\.id), [preview.id])
        XCTAssertEqual(ledger.records.first { $0.id == preview.id }?.announcement, preview)
    }

    func testOlderUnconfirmedRecoveryIsHiddenButNewerOneRemains() async {
        let manual = record(announcement("preview", post: "91001", age: 300, pending: true),
                            confirmedAt: now.addingTimeInterval(-60))
        for age: TimeInterval in [120, 60] {
            let result = ResetTopPresentation.make(pending: [], records: [manual], now: now,
                accountRecovery: AccountQuotaRecoveryState(latestUnconfirmed: recovery(.unconfirmed, age: age)))
            XCTAssertNil(result.unconfirmedAccountRecovery)
            XCTAssertEqual(result.latestDeliveryOrigin, .manualConfirmation)
            XCTAssertEqual(result.secondsSinceLastDelivery, 60)
        }
        let newer = recovery(.unconfirmed, age: 10)
        let result = ResetTopPresentation.make(pending: [], records: [manual], now: now,
            accountRecovery: AccountQuotaRecoveryState(latestUnconfirmed: newer))
        XCTAssertEqual(result.unconfirmedAccountRecovery, newer)
        XCTAssertEqual(result.latestDeliveryOrigin, .manualConfirmation)
        XCTAssertEqual(result.secondsSinceLastDelivery, 60)
    }

    func testRecoveryLinkedToSameManualEventCannotMoveManualClock() async {
        let preview = announcement("preview", post: "91001", age: 300, pending: true)
        var completion = announcement("delivery", post: "91002", age: 30)
        completion.relatedAnnouncementIDs = [preview.id]
        var personal = recovery(.officialTemporary, age: 10)
        personal.publicCompletionID = completion.id
        let result = ResetTopPresentation.make(pending: [], records: [
            record(preview, confirmedAt: now.addingTimeInterval(-60)), record(completion)
        ], now: now, accountRecovery: AccountQuotaRecoveryState(latestConfirmed: personal))
        XCTAssertEqual(result.latestDeliveryOrigin, .manualConfirmation)
        XCTAssertEqual(result.secondsSinceLastDelivery, 60)
    }

    func testLaterReceiptOrIndependentAccountRecoveryStillUpdatesClock() async {
        let manual = record(announcement("preview", post: "91001", age: 300, pending: true),
                            confirmedAt: now.addingTimeInterval(-60))
        let receipt = ResetTopPresentation.make(pending: [], records: [manual], now: now,
            accountReceipt: AccountResetReceipt(grantedAt: now.addingTimeInterval(-10)))
        XCTAssertEqual(receipt.latestDeliveryOrigin, .accountReceipt)
        XCTAssertEqual(receipt.secondsSinceLastDelivery, 10)
        let weekly = ResetTopPresentation.make(pending: [], records: [manual], now: now,
            accountRecovery: AccountQuotaRecoveryState(latestConfirmed: recovery(.weekly, age: 10)))
        XCTAssertEqual(weekly.latestDeliveryOrigin, .accountRecovery(.weekly))
        XCTAssertEqual(weekly.secondsSinceLastDelivery, 10)
    }

    func testInvalidAndFutureManualTimesDoNotReplaceConfirmedClock() async {
        let previous = record(announcement("previous", post: "91002", age: 3600))
        let preview = announcement("preview", post: "91001", age: 300, pending: true)
        let invalid = [Date(timeIntervalSince1970: .nan), Date(timeIntervalSince1970: .infinity),
                       Date(timeIntervalSince1970: -.infinity), Date(timeIntervalSince1970: 0),
                       Date(timeIntervalSince1970: -1), now.addingTimeInterval(60)]
        for time in invalid {
            let manual = record(preview, confirmedAt: time)
            let result = ResetTopPresentation.make(pending: [preview], records: [manual, previous], now: now)
            XCTAssertEqual(result.latestDeliveryOrigin, .publicAnnouncement)
            XCTAssertEqual(result.secondsSinceLastDelivery, 3600)
            XCTAssertEqual(result.announcements.map(\.id), [preview.id])
        }
    }

    private func announcement(_ id: String, post: String, age: TimeInterval,
                              pending: Bool = false) -> ResetAnnouncement {
        ResetAnnouncement(id: id, title: "Synthetic reset", summary: "Synthetic fixture",
            sourceURL: URL(string: "https://x.com/thsottiaux/status/\(post)"),
            announcedAt: now.addingTimeInterval(-age),
            scheduledFor: pending ? now.addingTimeInterval(3600) : nil,
            kind: "regular", scope: "broad", status: pending ? "scheduled" : "completed",
            deliveryAt: pending ? nil : now.addingTimeInterval(-age),
            deliveryKind: pending ? nil : "regular")
    }

    private func record(_ announcement: ResetAnnouncement, confirmedAt: Date? = nil) -> ResetRecord {
        ResetRecord(id: announcement.id, announcement: announcement, isUnread: true,
                    occurredWhileAway: true, manualCompletedAt: confirmedAt)
    }

    private func recovery(_ kind: AccountQuotaRecoveryKind, age: TimeInterval) -> AccountQuotaRecovery {
        AccountQuotaRecovery(observedFrom: now.addingTimeInterval(-age - 60),
            observedThrough: now.addingTimeInterval(-age), detectedAt: now.addingTimeInterval(-age),
            confirmedAt: now.addingTimeInterval(-age + 1), kind: kind,
            uncertainty: kind == .unconfirmed ? .insufficientEvidence : nil,
            redeemedAt: nil, publicCompletionID: nil)
    }
}
