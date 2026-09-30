import Foundation
import XCTest
@testable import CodexNotch

@MainActor
final class ResetAccountReceiptUITests: XCTestCase {
    func testEmptyHomeKeepsElapsedFooterForTodaysAccountCredit() async {
        let grant = AccountResetReceipt(grantedAt: Date(timeIntervalSince1970: 1_780_000_000))
        let presentation = ResetTopPresentation.make(
            pending: [], records: [], now: grant.grantedAt.addingTimeInterval(60), accountReceipt: grant)
        let noDelivery = ResetAnnouncementEntriesView.height(
            timedCount: 0, hasUndated: false, hasDelivery: false)
        let withDelivery = ResetAnnouncementEntriesView.height(
            timedCount: 0, hasUndated: false, hasDelivery: true)

        XCTAssertEqual(presentation.latestDeliveryOrigin, .accountReceipt)
        XCTAssertEqual(presentation.secondsSinceLastDelivery, 60)
        XCTAssertEqual(noDelivery, ResetAnnouncementEntryView.emptyHeight)
        XCTAssertEqual(withDelivery,
                       ResetAnnouncementEntryView.emptyHeight + ResetAnnouncementEntriesView.deliveryHeight + 8)
        XCTAssertEqual(ResetAnnouncementEntriesView.height(for: presentation), withDelivery)
        XCTAssertEqual(ResetAnnouncementEntryView.emptyHeadline(
            didResetToday: true, origin: .accountReceipt, language: .chinese),
            "暂无最新重置预告（本账户已收到重置券）")
        XCTAssertEqual(ResetAnnouncementEntriesView.deliveryAgeHeading(
            origin: .accountReceipt, language: .chinese), "距本账户收到重置券已过 ")
        XCTAssertEqual(ResetAnnouncementEntriesView.deliveryFootnote(
            origin: .accountReceipt, language: .chinese), "按本账户重置券发放时间计时，需自行使用")
        XCTAssertEqual(ResetAnnouncementDisplay.beijingTimestamp(
            ISO8601DateFormatter().date(from: "2026-09-29T18:46:26Z")!),
            "2026-09-30 02:46:26")
    }

    func testPublicDeliveryStillUsesSeparatePublicProvenance() async {
        XCTAssertEqual(ResetAnnouncementEntriesView.deliveryAgeHeading(
            origin: .publicAnnouncement, language: .chinese), "距上次重置已过 ")
        XCTAssertEqual(ResetAnnouncementEntriesView.deliveryFootnote(
            origin: .publicAnnouncement, language: .chinese), "按官方发放消息计时，不代表账户到账")
        XCTAssertEqual(ResetAnnouncementEntryView.emptyHeadline(
            didResetToday: true, origin: .publicAnnouncement, language: .chinese),
            "暂无最新重置预告（今天已重置）")
    }

    func testReceiptUpdateDoesNotNavigateOrMarkAnAnnouncementRead() async {
        let navigation = ResetAnnouncementsNavigation()
        var acknowledged: [String] = []
        navigation.filter = .away
        navigation.selectRecord(id: "unresolved-preview") { acknowledged.append($0) }
        let grant = AccountResetReceipt(grantedAt: Date(timeIntervalSince1970: 1_780_000_000),
                                        title: "Credit granted", description: nil)

        navigation.updateAccountReceipt(grant)

        XCTAssertEqual(navigation.accountReceipt, grant)
        XCTAssertEqual(navigation.filter, .away)
        XCTAssertEqual(navigation.selectedID, "unresolved-preview")
        XCTAssertEqual(acknowledged, ["unresolved-preview"])
    }
}
