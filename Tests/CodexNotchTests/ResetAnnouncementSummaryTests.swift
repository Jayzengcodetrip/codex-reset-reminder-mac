import Foundation
import XCTest
@testable import CodexNotch

final class ResetAnnouncementSummaryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(_ id: String, deadlineOffset: TimeInterval? = nil, status: String? = "scheduled",
                        publishedOffset: TimeInterval = 0, unread: Bool = false) -> ResetRecord {
        ResetRecord(id: id,
            announcement: ResetAnnouncement(id: id, title: "重置预告", summary: "公开公告", sourceURL: nil,
                announcedAt: now.addingTimeInterval(publishedOffset),
                scheduledFor: deadlineOffset.map { now.addingTimeInterval($0) },
                kind: "regular", scope: "all", status: status),
            isUnread: unread, occurredWhileAway: false)
    }

    func testReadNoticeKeepsTheMainCardCountdown() {
        let pending = record("pending", deadlineOffset: 80_130)
        let selected = ResetAnnouncementSummary.select(from: [pending], now: now)
        XCTAssertEqual(selected?.id, pending.id)
        XCTAssertEqual(ResetAnnouncementSummary.headline(for: selected!, now: now, language: .chinese),
                       "临时重置 · 还剩 22小时15分30秒")
    }

    func testNearestFutureResetWinsOverUnreadHistoryAndNewerLaterReset() {
        let nearest = record("nearest", deadlineOffset: 60, publishedOffset: -3_600)
        let later = record("later", deadlineOffset: 7_200, unread: true)
        let history = record("history", status: "completed", unread: true)
        XCTAssertEqual(ResetAnnouncementSummary.select(from: [history, later, nearest], now: now)?.id, "nearest")
    }

    func testCompletedAndCancelledNoticesNeverDisplayAnActiveCountdown() {
        for status in ["completed", "confirmed", "propagated", "cancelled", "canceled"] {
            let terminal = record(status, deadlineOffset: 3_600, status: status)
            XCTAssertNil(ResetAnnouncementSummary.select(from: [terminal], now: now), status)
            XCTAssertFalse(ResetAnnouncementSummary.headline(for: terminal.announcement, now: now, language: .chinese).contains("还剩"), status)
        }
    }

    func testElapsedDeadlineRemainsAwaitingConfirmation() {
        let elapsed = record("elapsed", deadlineOffset: -1)
        XCTAssertEqual(ResetAnnouncementSummary.select(from: [elapsed], now: now)?.id, elapsed.id)
        XCTAssertEqual(ResetAnnouncementSummary.headline(for: elapsed.announcement, now: now, language: .chinese),
                       "预计时间已过 · 等待确认")
    }

    func testWatchWithoutDeadlineDoesNotUsePublicationTimeAsResetTime() {
        let pending = record("watch", status: "watch", publishedOffset: 3_600)
        XCTAssertEqual(ResetAnnouncementSummary.select(from: [pending], now: now)?.id, "watch")
        XCTAssertEqual(ResetAnnouncementSummary.headline(for: pending.announcement, now: now, language: .chinese),
                       "临时重置 · 时间待公布")
        XCTAssertEqual(ResetAnnouncementSummary.scheduleText(for: pending.announcement, language: .chinese),
                       "重置时间待公布")
    }

    func testBeijingScheduleCarriesPublicSourceCaveat() {
        var pending = record("scheduled").announcement
        pending.scheduledFor = ISO8601DateFormatter().date(from: "2026-09-23T07:00:00Z")!
        XCTAssertEqual(ResetAnnouncementSummary.scheduleText(for: pending, language: .chinese),
                       "9月23日 15:00（北京时间 · 接口时间）")
    }

    func testNewCompletionOnlySupersedesReliablyLinkedPreannouncement() {
        let old = record("old", deadlineOffset: -3_600, publishedOffset: -7_200)
        let unrelatedCompletion = record("other", status: "completed")
        XCTAssertEqual(ResetAnnouncementSummary.select(from: [old, unrelatedCompletion], now: now)?.id, "old")
        let linkedCompletion = record("old", status: "completed")
        XCTAssertNil(ResetAnnouncementSummary.select(from: [old, linkedCompletion], now: now))
    }

    func testDeterministicFallbackForUndatedPendingAnnouncements() {
        let older = record("older", status: "announced", publishedOffset: -60)
        let newest = record("newest", status: "pending")
        XCTAssertEqual(ResetAnnouncementSummary.select(from: [older, newest], now: now)?.id, "newest")
        XCTAssertEqual(ResetAnnouncementSummary.select(from: [newest, older], now: now)?.id, "newest")
    }

    func testExecutableRegressionChecks() throws {
        XCTAssertGreaterThanOrEqual(try ResetAnnouncementSummary.runSelfChecks(), 23)
    }
}
