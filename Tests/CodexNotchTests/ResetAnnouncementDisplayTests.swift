import Foundation
import XCTest
@testable import CodexNotch

final class ResetAnnouncementDisplayTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_789_214_400)

    private func announcement(
        announcedAt: Date? = nil,
        scheduledFor: Date? = nil,
        status: String? = nil
    ) -> ResetAnnouncement {
        ResetAnnouncement(id: "public-post", title: "Reset update", summary: "Public announcement",
                          sourceURL: nil, announcedAt: announcedAt, scheduledFor: scheduledFor,
                          kind: "regular", scope: "unspecified", status: status)
    }

    func testPublicationTimestampNeverBecomesAResetDeadline() {
        let update = announcement(announcedAt: now.addingTimeInterval(3_600))
        XCTAssertEqual(ResetAnnouncementDisplay.timingText(update, now: now, language: .chinese),
                       "公告未提供明确重置时间")
        XCTAssertFalse(ResetAnnouncementDisplay.isCompleted(update))
    }

    func testElapsedScheduleDoesNotClaimResetCompleted() {
        let update = announcement(scheduledFor: now.addingTimeInterval(-1), status: "scheduled")
        XCTAssertEqual(ResetAnnouncementDisplay.timingText(update, now: now, language: .chinese),
                       "预计时间已过，待确认")
        XCTAssertFalse(ResetAnnouncementDisplay.isCompleted(update))
    }

    func testExplicitCompletionSuppressesAnyPendingCountdown() {
        let update = announcement(scheduledFor: now.addingTimeInterval(3_600), status: " COMPLETED \n")
        XCTAssertEqual(ResetAnnouncementDisplay.timingText(update, now: now, language: .chinese),
                       "来源已确认重置完成")
        XCTAssertTrue(ResetAnnouncementDisplay.isCompleted(update))
    }

    func testCancellationSuppressesAnyPendingCountdown() {
        let update = announcement(scheduledFor: now.addingTimeInterval(3_600), status: " CANCELLED \n")
        XCTAssertEqual(ResetAnnouncementDisplay.timingText(update, now: now, language: .chinese),
                       "来源已取消这次重置")
        XCTAssertFalse(ResetAnnouncementDisplay.isCompleted(update))
    }

    func testCountdownUsesProvidedDeadlineAndShowsFinalMinute() {
        let later = announcement(scheduledFor: now.addingTimeInterval(90 * 60), status: "scheduled")
        XCTAssertEqual(ResetAnnouncementDisplay.timingText(later, now: now, language: .chinese),
                       "还剩 1小时30分0秒")
        let soon = announcement(scheduledFor: now.addingTimeInterval(1), status: "scheduled")
        XCTAssertEqual(ResetAnnouncementDisplay.timingText(soon, now: now, language: .chinese),
                       "还剩 0小时0分1秒")
    }

    func testDateOnlyDetailTransitionsFromDayStartToDayEndAndThenStopsCounting() {
        let parser = ISO8601DateFormatter()
        let scheduled = parser.date(from: "2026-09-23T06:59:00Z")!
        let beforeDay = parser.date(from: "2026-09-22T06:59:59Z")!
        let startOfDay = parser.date(from: "2026-09-22T07:00:00Z")!
        let before = parser.date(from: "2026-09-23T06:59:30Z")!
        let midnight = parser.date(from: "2026-09-23T07:00:00Z")!
        let post = ResetAnnouncement(id: "weekday", title: "周二预告", summary: "周二重置",
            sourceURL: nil, announcedAt: parser.date(from: "2026-09-22T04:31:32Z")!, scheduledFor: scheduled,
            kind: "regular", scope: "all", status: "scheduled")
        XCTAssertEqual(ResetAnnouncementDisplay.timingText(post, now: beforeDay, language: .chinese),
                       "距预告日开始还剩 0小时0分1秒")
        XCTAssertEqual(ResetAnnouncementDisplay.timingText(post, now: startOfDay, language: .chinese),
                       "预告日内还剩 24小时0分0秒")
        XCTAssertEqual(ResetAnnouncementDisplay.timingText(post, now: before, language: .chinese),
                       "预告日内还剩 0小时0分30秒")
        XCTAssertEqual(ResetAnnouncementDisplay.timingText(post, now: midnight, language: .chinese),
                       "预告日已过 · 等待确认")
        XCTAssertFalse(ResetAnnouncementDisplay.isCompleted(post))
    }

    func testBeijingDisplayIgnoresSystemTimezoneAndConvertsAcrossDates() {
        let utc = ISO8601DateFormatter().date(from: "2026-09-12T20:09:00Z")!
        XCTAssertEqual(ResetAnnouncementDisplay.beijingDate(utc), "2026-09-13 04:09")
    }

    func testOriginalLinksRequireHTTPSAndAnExactPublicSourceHost() {
        let valid = URL(string: "https://x.com/thsottiaux/status/2098685367058612394")!
        XCTAssertEqual(ResetAnnouncementDisplay.safeSourceURL(valid), valid)
        let rejected = [
            "http://x.com/thsottiaux/status/123",
            "https://x.com.example.net/thsottiaux/status/123",
            "https://example.net/thsottiaux/status/123",
            "file:///tmp/announcement",
            "https://name:password@x.com/thsottiaux/status/123"
        ]
        for value in rejected {
            XCTAssertNil(ResetAnnouncementDisplay.safeSourceURL(URL(string: value)), value)
        }
    }
}
