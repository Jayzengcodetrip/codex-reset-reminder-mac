import Foundation
import XCTest
@testable import CodexNotch

@MainActor
final class AccountQuotaRecoveryPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func recovery(_ kind: AccountQuotaRecoveryKind, age: TimeInterval = 60) -> AccountQuotaRecovery {
        AccountQuotaRecovery(observedFrom: now.addingTimeInterval(-age - 60),
            observedThrough: now.addingTimeInterval(-age), detectedAt: now.addingTimeInterval(-age),
            confirmedAt: now.addingTimeInterval(-age + 30), kind: kind,
            uncertainty: kind == .unconfirmed ? .insufficientEvidence : nil,
            redeemedAt: kind == .manualCredit ? now.addingTimeInterval(-age - 10) : nil,
            publicCompletionID: kind == .officialTemporary ? "official-completion" : nil)
    }

    private func announcement(_ id: String, age: TimeInterval, kind: String = "regular",
                              status: String? = nil, scheduled: Bool = false,
                              source: String = "https://x.com/thsottiaux/status/90001") -> ResetAnnouncement {
        ResetAnnouncement(id: id, title: "Synthetic reset", summary: "Synthetic fixture",
            sourceURL: URL(string: source), announcedAt: now.addingTimeInterval(-age),
            scheduledFor: scheduled ? now.addingTimeInterval(3600) : nil,
            kind: kind, scope: "broad", status: status,
            deliveryAt: status == "completed" ? now.addingTimeInterval(-age) : nil,
            deliveryKind: status == "completed" ? kind : nil)
    }

    private func record(_ announcement: ResetAnnouncement) -> ResetRecord {
        ResetRecord(id: announcement.id, announcement: announcement, isUnread: true, occurredWhileAway: true)
    }

    func testManualWeeklyAndOfficialPersonalClocksShowTheirActualOrigin() async {
        let publicRecord = record(announcement("old", age: 3600, status: "completed"))
        for kind: AccountQuotaRecoveryKind in [.manualCredit, .weekly, .officialTemporary] {
            let result = ResetTopPresentation.make(pending: [], records: [publicRecord], now: now,
                accountRecovery: AccountQuotaRecoveryState(latestConfirmed: recovery(kind)))
            XCTAssertEqual(result.latestDeliveryOrigin, .accountRecovery(kind))
            XCTAssertEqual(result.secondsSinceLastDelivery, kind == .manualCredit ? 70 : 60)
            XCTAssertEqual(ResetAnnouncementEntriesView.deliveryAgeHeading(origin: result.latestDeliveryOrigin,
                                                                            language: .chinese), "距上次重置已过 ")
            XCTAssertEqual(ResetAnnouncementEntryView.emptyHeadline(didResetToday: true,
                origin: result.latestDeliveryOrigin, language: .chinese), "暂无最新重置预告")
        }
        XCTAssertTrue(ResetAnnouncementEntriesView.deliveryFootnote(origin: .accountRecovery(.manualCredit),
            language: .chinese).contains("兑换完成时间"))
        XCTAssertTrue(ResetAnnouncementEntriesView.deliveryFootnote(origin: .accountRecovery(.weekly),
            language: .chinese).contains("正常周重置"))
        XCTAssertTrue(ResetAnnouncementEntriesView.deliveryFootnote(origin: .accountRecovery(.officialTemporary),
            language: .chinese).contains("首次检测时间"))
    }

    func testAccountRecoveryDoesNotChangeAnyPreviewOrPublicLedgerState() async {
        let dated = announcement("dated", age: 200, status: "scheduled", scheduled: true)
        let undated = announcement("undated", age: 100, status: "scheduled")
        let records = [record(dated), record(undated)]
        let baseline = ResetTopPresentation.make(pending: [dated, undated], records: records, now: now)
        for kind: AccountQuotaRecoveryKind in [.manualCredit, .weekly, .officialTemporary, .unconfirmed] {
            let state = kind == .unconfirmed
                ? AccountQuotaRecoveryState(latestUnconfirmed: recovery(kind))
                : AccountQuotaRecoveryState(latestConfirmed: recovery(kind))
            let result = ResetTopPresentation.make(pending: [dated, undated], records: records, now: now,
                                                  accountRecovery: state)
            XCTAssertEqual(result.announcements, baseline.announcements)
            XCTAssertEqual(result.undatedAnnouncements, baseline.undatedAnnouncements)
            XCTAssertEqual(result.archivedUndated, baseline.archivedUndated)
            XCTAssertEqual(result.archivedForAccountReceipt, baseline.archivedForAccountReceipt)
            XCTAssertEqual(result.didResetToday, baseline.didResetToday)
            XCTAssertTrue(records.allSatisfy { $0.isUnread && $0.occurredWhileAway })
            XCTAssertTrue(records.allSatisfy { $0.announcement.status == "scheduled" })
        }
    }

    func testUnconfirmedRecoveryKeepsPreviousConfirmedTimerAndBoundedLayout() async {
        let oldPublic = record(announcement("old", age: 600, status: "completed"))
        let unknown = recovery(.unconfirmed)
        let result = ResetTopPresentation.make(pending: [], records: [oldPublic], now: now,
            accountRecovery: AccountQuotaRecoveryState(latestUnconfirmed: unknown))
        XCTAssertEqual(result.latestDeliveryOrigin, .publicAnnouncement)
        XCTAssertEqual(result.secondsSinceLastDelivery, 600)
        XCTAssertEqual(result.unconfirmedAccountRecovery, unknown)
        XCTAssertEqual(ResetAnnouncementEntriesView.unconfirmedHeading(language: .chinese),
                       "本账户额度已恢复 · 方式待确认")
        XCTAssertEqual(ResetAnnouncementEntriesView.height(for: result), 180)
        XCTAssertEqual(ResetAnnouncementEntriesView.height(timedCount: 2, hasUndated: true,
            hasDelivery: true, hasUnconfirmed: true), ResetAnnouncementEntriesView.maximumHeight)
    }

    func testNewerPublicOrCreditReceiptStillWinsAndFutureRecoveryIsIgnored() async {
        let publicRecord = record(announcement("newer", age: 10, status: "completed"))
        let state = AccountQuotaRecoveryState(latestConfirmed: recovery(.weekly))
        let publicResult = ResetTopPresentation.make(pending: [], records: [publicRecord], now: now,
                                                    accountRecovery: state)
        XCTAssertEqual(publicResult.latestDeliveryOrigin, .publicAnnouncement)
        let receiptResult = ResetTopPresentation.make(pending: [], records: [], now: now,
            accountReceipt: AccountResetReceipt(grantedAt: now.addingTimeInterval(-5)), accountRecovery: state)
        XCTAssertEqual(receiptResult.latestDeliveryOrigin, .accountReceipt)
        let future = ResetTopPresentation.make(pending: [], records: [], now: now,
            accountRecovery: AccountQuotaRecoveryState(latestConfirmed: recovery(.weekly, age: -60)))
        XCTAssertNil(future.secondsSinceLastDelivery)
    }

    func testPublicContextRequiresOfficialBroadDirectCompletion() async {
        var targeted = announcement("targeted", age: 60, status: "completed")
        targeted.scope = "targeted"
        var otherProduct = announcement("chatgpt-only", age: 60, status: "completed")
        otherProduct.scope = "chatgpt"
        var unknownAudience = announcement("limited-audience", age: 60, status: "completed")
        unknownAudience.scope = "pro-only"
        let valid = announcement("direct", age: 60, status: "completed")
        let inputs = [valid, announcement("banked", age: 60, kind: "banked", status: "completed"),
            announcement("unknown", age: 60, kind: "unknown", status: "completed"),
            announcement("scheduled", age: 60, status: "scheduled", scheduled: true),
            announcement("other-author", age: 60, status: "completed", source: "https://x.com/other/status/90002"),
            announcement("future", age: -60, status: "completed"), targeted, otherProduct, unknownAudience]
        let context = AccountQuotaRecoveryPublicContext.completions(from: inputs.map(record), now: now)
        XCTAssertEqual(context.map(\.id), ["direct"])
    }

    func testLaterAnnouncementForSameRecoveryDoesNotReplaceObservedAccountTime() async {
        var personal = recovery(.officialTemporary, age: 600)
        personal.publicCompletionID = "same-delivery"
        let same = record(announcement("same-delivery", age: 300, status: "completed"))
        let state = AccountQuotaRecoveryState(latestConfirmed: personal)
        let result = ResetTopPresentation.make(pending: [], records: [same], now: now,
                                              accountRecovery: state)
        XCTAssertEqual(result.latestDeliveryOrigin, .accountRecovery(.officialTemporary))
        XCTAssertEqual(result.secondsSinceLastDelivery, 600)
        let newerReceipt = ResetTopPresentation.make(pending: [], records: [same], now: now,
            accountReceipt: AccountResetReceipt(grantedAt: now.addingTimeInterval(-400)), accountRecovery: state)
        XCTAssertEqual(newerReceipt.latestDeliveryOrigin, .accountReceipt)
        XCTAssertEqual(newerReceipt.secondsSinceLastDelivery, 400)
        let different = record(announcement("later-different-delivery", age: 60, status: "completed"))
        let newer = ResetTopPresentation.make(pending: [], records: [same, different], now: now,
                                             accountRecovery: state)
        XCTAssertEqual(newer.latestDeliveryOrigin, .publicAnnouncement)
        XCTAssertEqual(newer.secondsSinceLastDelivery, 60)
    }
}
