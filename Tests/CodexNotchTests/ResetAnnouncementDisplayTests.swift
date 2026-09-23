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
                       "距计划重置还有 1 小时 30 分")
        let soon = announcement(scheduledFor: now.addingTimeInterval(1), status: "scheduled")
        XCTAssertEqual(ResetAnnouncementDisplay.timingText(soon, now: now, language: .chinese),
                       "距计划重置还有 1 分钟")
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
