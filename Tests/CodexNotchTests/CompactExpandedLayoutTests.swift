import AppKit
import XCTest
@testable import CodexNotch

@MainActor
final class CompactExpandedLayoutTests: XCTestCase {
    func testEmptyManualHomeUsesOneLineAndDoesNotReserveLegacyBlankCanvas() async {
        let manual = ResetAnnouncementEntriesView.height(timedCount: 0, hasUndated: false,
            hasDelivery: true, deliveryOrigin: .manualConfirmation)
        let official = ResetAnnouncementEntriesView.height(timedCount: 0, hasUndated: false,
            hasDelivery: true, deliveryOrigin: .publicAnnouncement)
        XCTAssertLessThan(manual, official)
        let panel = layout(contentHeight: NotchExpandedLayout.quotaContentHeight + manual + 8)
        XCTAssertLessThanOrEqual(panel.quotaExpandedFrame.height, 270)
        XCTAssertEqual(panel.quotaExpandedFrame.width, 420)
        XCTAssertEqual(panel.quotaExpandedFrame.maxY, panel.compactFrame.maxY)
        XCTAssertEqual(ResetAnnouncementEntriesView.deliveryAgeHeading(origin: .manualConfirmation,
            language: .chinese), "距上次重置已过 ")
        XCTAssertTrue(ResetAnnouncementEntriesView.deliveryFootnote(origin: .manualConfirmation,
            language: .chinese).isEmpty)
    }

    func testEmptyStateReservesOnlyVisibleRowsAndKeepsRestartAvailableWithoutEvidence() async {
        let plain = ResetTopPresentation(announcements: [], didResetToday: false)
        let withUnread = ResetAnnouncementEntriesView.height(for: plain, unreadCount: 2)
        XCTAssertEqual(withUnread - ResetAnnouncementEntriesView.height(for: plain), 14)
        XCTAssertEqual(ResetAnnouncementEntryView.emptyHeight, 48)
        XCTAssertGreaterThan(ResetAnnouncementEntriesView.height(for: plain), ResetAnnouncementEntryView.emptyHeight)
        let restarted = ResetTopPresentation.make(pending: [], records: [], now: Date(timeIntervalSince1970: 1_800_000_030),
            manualTimerRestartedAt: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(ResetAnnouncementEntriesView.height(for: restarted), ResetAnnouncementEntriesView.height(for: plain))
        XCTAssertEqual(restarted.secondsSinceLastDelivery, 30)
        XCTAssertTrue(ResetAnnouncementEntriesView.deliveryFootnote(origin: .manualTimerRestart, language: .chinese).isEmpty)
        XCTAssertEqual(ResetAnnouncementEntryView.emptyHeadline(didResetToday: true, origin: .manualTimerRestart,
            language: .chinese), "暂无最新重置预告")
    }

    func testDatedPreviewsKeepTheirReadableRowsWhileExtraPreviewsScroll() async {
        let two = ResetAnnouncementEntriesView.height(timedCount: 2, hasUndated: false, hasDelivery: false)
        XCTAssertGreaterThanOrEqual(two, ResetAnnouncementEntryView.announcementHeight * 2)
        let many = ResetAnnouncementEntriesView.height(timedCount: 8, hasUndated: true,
            hasDelivery: true, hasUnconfirmed: true)
        XCTAssertEqual(many, ResetAnnouncementEntriesView.maximumHeight)
        XCTAssertGreaterThan(ResetAnnouncementEntryView.announcementHeight, ResetAnnouncementEntryView.emptyHeight)
    }

    func testCreditAndQuotaExpansionGrowOnlyDownwardByTheirContentHeight() async {
        let compact = NotchExpandedLayout.quotaContentSize()
        let detail = NotchExpandedLayout.quotaContentSize(isResetScheduleExpanded: true,
            resetCreditCount: 2, hasFiveHourWindow: true)
        let creditList = NotchExpandedLayout.resetScheduleDetailSpacing
            + NotchExpandedLayout.resetScheduleDetailVerticalPadding * 2
            + NotchExpandedLayout.resetScheduleRowHeight * 2
            + NotchExpandedLayout.conversationSeparatorHeight
        XCTAssertEqual(detail.height - compact.height,
            creditList + NotchExpandedLayout.fiveHourQuotaContentHeight)
        let before = layout(contentHeight: compact.height)
        let after = layout(contentHeight: detail.height)
        XCTAssertEqual(before.compactFrame, after.compactFrame)
        XCTAssertEqual(before.quotaExpandedFrame.maxY, after.quotaExpandedFrame.maxY)
        XCTAssertLessThan(after.quotaExpandedFrame.minY, before.quotaExpandedFrame.minY)
    }

    private func layout(contentHeight: CGFloat) -> NotchLayout {
        NotchGeometry.layout(metrics: NotchScreenMetrics(
            frame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: NSRect(x: 0, y: 0, width: 1512, height: 949),
            safeAreaInsets: NSEdgeInsets(top: 32, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: NSRect(x: 0, y: 950, width: 663, height: 32),
            auxiliaryTopRightArea: NSRect(x: 848, y: 950, width: 664, height: 32)),
            quotaExpandedSize: NSSize(width: 420, height: contentHeight))
    }
}
