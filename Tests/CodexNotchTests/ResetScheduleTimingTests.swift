import Foundation
import XCTest
@testable import CodexNotch

final class ResetScheduleTimingTests: XCTestCase {
    private let parser = ISO8601DateFormatter()

    private func announcement(_ isoTime: String, title: String = "周二重置预告", summary: String = "周二") -> ResetAnnouncement {
        let scheduled = parser.date(from: isoTime)!
        return ResetAnnouncement(id: "weekday-post", title: title, summary: summary,
            sourceURL: nil, announcedAt: scheduled.addingTimeInterval(-3_600), scheduledFor: scheduled,
            kind: "regular", scope: "all", status: "scheduled")
    }

    func testDateBoundaryUsesLosAngelesTuesdayUntilWednesdayMidnight() {
        let post = announcement("2026-09-23T06:59:00Z")
        let target = ResetScheduleTiming.target(for: post)!
        XCTAssertTrue(target.isDateBoundaryEstimate)
        XCTAssertEqual(target.displayedTime, parser.date(from: "2026-09-23T06:59:00Z"))
        XCTAssertEqual(target.countdownDeadline, parser.date(from: "2026-09-23T07:00:00Z"))
        XCTAssertEqual(ResetScheduleTiming.targetText(for: post, language: .chinese),
                       "预计：洛杉矶周二 23:59（日期边界估算，非官方精确时刻）")
        XCTAssertEqual(ResetScheduleTiming.beijingWeekdayText(for: post, language: .chinese),
                       "对应北京：周三")

        let before = parser.date(from: "2026-09-23T06:58:30Z")!
        let lastMinute = parser.date(from: "2026-09-23T06:59:30Z")!
        let midnight = parser.date(from: "2026-09-23T07:00:00Z")!
        XCTAssertEqual(ResetScheduleTiming.losAngelesNowText(before, language: .chinese),
                       "洛杉矶现在：周二 23:58:30")
        XCTAssertEqual(ResetScheduleTiming.losAngelesNowText(lastMinute, language: .chinese),
                       "洛杉矶现在：周二 23:59:30")
        XCTAssertEqual(ResetScheduleTiming.losAngelesNowText(midnight, language: .chinese),
                       "洛杉矶现在：周三 00:00:00")
        for now in [before, lastMinute, midnight] {
            let text = ResetScheduleTiming.losAngelesNowText(now, language: .chinese)
            XCTAssertFalse(text.contains("9月"), text)
            XCTAssertFalse(text.contains("23日"), text)
        }
    }

    func testLegacyNextDayMidnightTimestampHasTheSameBoundary() {
        let post = announcement("2026-09-23T07:00:00Z")
        let target = ResetScheduleTiming.target(for: post)!
        XCTAssertTrue(target.isDateBoundaryEstimate)
        XCTAssertEqual(target.displayedTime, parser.date(from: "2026-09-23T06:59:00Z"))
        XCTAssertEqual(target.countdownDeadline, parser.date(from: "2026-09-23T07:00:00Z"))
    }

    func testAnExplicit2359PromiseIsNotExtendedToMidnight() {
        let post = announcement("2026-09-23T06:59:00Z", title: "Tuesday reset at 23:59 PDT", summary: "Exact time")
        let target = ResetScheduleTiming.target(for: post)!
        XCTAssertFalse(target.isDateBoundaryEstimate)
        XCTAssertEqual(target.countdownDeadline, post.scheduledFor)
        XCTAssertEqual(ResetScheduleTiming.targetText(for: post, language: .chinese),
                       "预计：洛杉矶周二 23:59（接口时间）")
        XCTAssertEqual(ResetAnnouncementSummary.countdownText(for: post,
            now: parser.date(from: "2026-09-23T06:58:30Z")!, language: .chinese), "还剩 0小时0分30秒")
        XCTAssertEqual(ResetAnnouncementSummary.countdownText(for: post,
            now: parser.date(from: "2026-09-23T06:59:00Z")!, language: .chinese),
            "预计时间已过 · 等待确认")
    }

    func testLosAngelesClockAndBoundaryRespectDaylightSavingTransitions() {
        let beforeSpringJump = parser.date(from: "2026-03-08T09:59:59Z")!
        let afterSpringJump = parser.date(from: "2026-03-08T10:00:00Z")!
        XCTAssertEqual(ResetScheduleTiming.losAngelesNowText(beforeSpringJump, language: .chinese),
                       "洛杉矶现在：周日 01:59:59")
        XCTAssertEqual(ResetScheduleTiming.losAngelesNowText(afterSpringJump, language: .chinese),
                       "洛杉矶现在：周日 03:00:00")

        let spring = announcement("2026-03-09T06:59:00Z", title: "周日重置预告", summary: "周日")
        XCTAssertEqual(ResetScheduleTiming.target(for: spring)?.countdownDeadline,
                       parser.date(from: "2026-03-09T07:00:00Z"))
        XCTAssertEqual(ResetScheduleTiming.targetText(for: spring, language: .chinese),
                       "预计：洛杉矶周日 23:59（日期边界估算，非官方精确时刻）")

        let fall = announcement("2026-11-02T07:59:00Z", title: "周日重置预告", summary: "周日")
        XCTAssertEqual(ResetScheduleTiming.target(for: fall)?.countdownDeadline,
                       parser.date(from: "2026-11-02T08:00:00Z"))
        XCTAssertEqual(ResetScheduleTiming.targetText(for: fall, language: .chinese),
                       "预计：洛杉矶周日 23:59（日期边界估算，非官方精确时刻）")
    }
}
