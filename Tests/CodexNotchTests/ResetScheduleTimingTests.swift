import Foundation
import XCTest
@testable import CodexNotch

final class ResetScheduleTimingTests: XCTestCase {
    private let parser = ISO8601DateFormatter()

    private func date(_ isoTime: String) -> Date { parser.date(from: isoTime)! }

    private func announcement(_ isoTime: String, title: String = "周二重置预告", summary: String = "周二",
                              announcedAt: String? = nil) -> ResetAnnouncement {
        let scheduled = date(isoTime)
        return ResetAnnouncement(id: "weekday-post", title: title, summary: summary,
            sourceURL: nil, announcedAt: announcedAt.map(date) ?? scheduled.addingTimeInterval(-3_600),
            scheduledFor: scheduled, kind: "regular", scope: "all", status: "scheduled")
    }

    func testDateOnlyPromiseHasThreeDistinctLosAngelesPhases() {
        // NextReset's 23:59 is a date marker, not a promise that Tibo named a minute.
        let post = announcement("2026-09-23T06:59:00Z", announcedAt: "2026-09-22T04:31:32Z")
        let target = ResetScheduleTiming.target(for: post)!
        XCTAssertTrue(target.isDateBoundaryEstimate)
        XCTAssertEqual(target.displayedTime, date("2026-09-23T06:59:00Z"))
        XCTAssertEqual(target.countdownDeadline, date("2026-09-23T07:00:00Z"))

        let published = date("2026-09-22T04:31:32Z") // Monday 21:31:32 LA
        let mondayLastSecond = date("2026-09-22T06:59:59Z")
        let tuesdayMidnight = date("2026-09-22T07:00:00Z")
        let tuesdayLastSecond = date("2026-09-23T06:59:59Z")
        let wednesdayMidnight = date("2026-09-23T07:00:00Z")

        XCTAssertEqual(ResetScheduleTiming.phase(for: post, now: published), .beforeDate(tuesdayMidnight))
        XCTAssertEqual(ResetAnnouncementSummary.countdownText(for: post, now: published, language: .chinese),
                       "距预告日开始还剩 2小时28分28秒")
        XCTAssertEqual(ResetScheduleTiming.phase(for: post, now: mondayLastSecond), .beforeDate(tuesdayMidnight))
        XCTAssertEqual(ResetAnnouncementSummary.countdownText(for: post, now: mondayLastSecond, language: .chinese),
                       "距预告日开始还剩 0小时0分1秒")
        XCTAssertEqual(ResetScheduleTiming.targetText(for: post, now: mondayLastSecond, language: .chinese),
                       "最早可能窗口：洛杉矶周二 00:00（日期估算，非官方时刻）")
        XCTAssertEqual(ResetScheduleTiming.quotaRiskText(for: post, now: mondayLastSecond, language: .chinese),
                       "不建议仅凭预告清空额度；实际重置可能延后。")
        XCTAssertEqual(ResetScheduleTiming.beijingWeekdayText(for: post, now: mondayLastSecond, language: .chinese),
                       "对应北京：周二")

        XCTAssertEqual(ResetScheduleTiming.phase(for: post, now: tuesdayMidnight), .duringDate(wednesdayMidnight))
        XCTAssertEqual(ResetAnnouncementSummary.countdownText(for: post, now: tuesdayMidnight, language: .chinese),
                       "预告日内还剩 24小时0分0秒")
        XCTAssertEqual(ResetScheduleTiming.targetText(for: post, now: tuesdayMidnight, language: .chinese),
                       "预告日截止参考：洛杉矶周二 23:59（日期估算，非官方时刻）")
        XCTAssertEqual(ResetScheduleTiming.quotaRiskText(for: post, now: tuesdayMidnight, language: .chinese),
                       "不建议仅凭预告清空额度；实际重置可能延后。")
        XCTAssertEqual(ResetScheduleTiming.beijingWeekdayText(for: post, now: tuesdayMidnight, language: .chinese),
                       "对应北京：周三")
        XCTAssertEqual(ResetScheduleTiming.phase(for: post, now: tuesdayLastSecond), .duringDate(wednesdayMidnight))
        XCTAssertEqual(ResetAnnouncementSummary.countdownText(for: post, now: tuesdayLastSecond, language: .chinese),
                       "预告日内还剩 0小时0分1秒")
        XCTAssertEqual(ResetScheduleTiming.phase(for: post, now: wednesdayMidnight), .afterDate)
        XCTAssertEqual(ResetAnnouncementSummary.countdownText(for: post, now: wednesdayMidnight, language: .chinese),
                       "预告日已过 · 等待确认")
        XCTAssertEqual(ResetScheduleTiming.targetText(for: post, now: wednesdayMidnight, language: .chinese),
                       "预告日已过 · 等待确认")
        XCTAssertNil(ResetScheduleTiming.quotaRiskText(for: post, now: wednesdayMidnight, language: .chinese))

        let clocks: [(Date, String)] = [
            (mondayLastSecond, "洛杉矶现在：周一 23:59:59"),
            (tuesdayMidnight, "洛杉矶现在：周二 00:00:00"),
            (tuesdayLastSecond, "洛杉矶现在：周二 23:59:59"),
            (wednesdayMidnight, "洛杉矶现在：周三 00:00:00")
        ]
        for (instant, expected) in clocks {
            let actual = ResetScheduleTiming.losAngelesNowText(instant, language: .chinese)
            XCTAssertEqual(actual, expected)
            XCTAssertFalse(actual.contains("9月"), actual)
            XCTAssertFalse(actual.contains("23日"), actual)
        }
    }

    func testLegacyNextDayMidnightTimestampStillHasTheThreePhases() {
        let post = announcement("2026-09-23T07:00:00Z", announcedAt: "2026-09-22T04:31:32Z")
        let target = ResetScheduleTiming.target(for: post)!
        XCTAssertTrue(target.isDateBoundaryEstimate)
        XCTAssertEqual(target.displayedTime, date("2026-09-23T06:59:00Z"))
        XCTAssertEqual(target.countdownDeadline, date("2026-09-23T07:00:00Z"))
        XCTAssertEqual(ResetScheduleTiming.phase(for: post, now: date("2026-09-22T06:59:59Z")),
                       .beforeDate(date("2026-09-22T07:00:00Z")))
        XCTAssertEqual(ResetScheduleTiming.phase(for: post, now: date("2026-09-22T07:00:00Z")),
                       .duringDate(date("2026-09-23T07:00:00Z")))
        XCTAssertEqual(ResetScheduleTiming.phase(for: post, now: date("2026-09-23T07:00:00Z")), .afterDate)
    }

    func test2359DateMarkerStaysDateOnlyWhenSourceRevisionOmitsTheWeekday() {
        var revised = announcement("2026-09-23T06:59:00Z", announcedAt: "2026-09-22T04:31:32Z")
        revised.title = "Codex reset update"
        revised.summary = "Source metadata changed"
        revised.sourceURL = URL(string: "https://x.com/thsottiaux/status/2102254445082116335")
        XCTAssertTrue(ResetScheduleTiming.target(for: revised)?.isDateBoundaryEstimate == true)
        XCTAssertEqual(ResetScheduleTiming.phase(for: revised, now: date("2026-09-22T06:59:59Z")),
                       .beforeDate(date("2026-09-22T07:00:00Z")))
        XCTAssertEqual(ResetAnnouncementSummary.countdownText(for: revised,
            now: date("2026-09-22T06:59:59Z"), language: .chinese),
            "距预告日开始还剩 0小时0分1秒")
        XCTAssertEqual(ResetScheduleTiming.phase(for: revised, now: date("2026-09-22T07:00:00Z")),
                       .duringDate(date("2026-09-23T07:00:00Z")))
    }

    func testGeneric235959WithoutWeekdayOrOriginalPostLinkRemainsExact() {
        let exact = announcement("2026-09-23T06:59:59Z", title: "Generic reset update",
                                 summary: "Source metadata changed")
        XCTAssertNil(exact.sourceURL)
        XCTAssertFalse(ResetScheduleTiming.target(for: exact)?.isDateBoundaryEstimate ?? true)
        XCTAssertEqual(ResetScheduleTiming.target(for: exact)?.countdownDeadline,
                       date("2026-09-23T06:59:59Z"))
        XCTAssertEqual(ResetScheduleTiming.phase(for: exact, now: date("2026-09-23T06:59:58Z")),
                       .beforeExact(date("2026-09-23T06:59:59Z")))
        XCTAssertEqual(ResetAnnouncementSummary.countdownText(for: exact,
            now: date("2026-09-23T06:59:58Z"), language: .chinese), "还剩 0小时0分1秒")
        XCTAssertEqual(ResetScheduleTiming.phase(for: exact, now: date("2026-09-23T06:59:59Z")),
                       .afterExact)
    }

    func testAnExplicit2359PromiseUsesOnlyItsExactDeadline() {
        let post = announcement("2026-09-23T06:59:00Z", title: "Tuesday reset at 23:59 PDT", summary: "Exact time")
        let target = ResetScheduleTiming.target(for: post)!
        XCTAssertFalse(target.isDateBoundaryEstimate)
        XCTAssertEqual(target.countdownDeadline, post.scheduledFor)
        XCTAssertEqual(ResetScheduleTiming.phase(for: post, now: date("2026-09-23T06:58:30Z")),
                       .beforeExact(date("2026-09-23T06:59:00Z")))
        XCTAssertEqual(ResetScheduleTiming.targetText(for: post, now: date("2026-09-23T06:58:30Z"), language: .chinese),
                       "预计：洛杉矶周二 23:59（接口时间）")
        XCTAssertNil(ResetScheduleTiming.quotaRiskText(for: post, now: date("2026-09-23T06:58:30Z"), language: .chinese))
        XCTAssertEqual(ResetAnnouncementSummary.countdownText(for: post,
            now: date("2026-09-23T06:58:30Z"), language: .chinese), "还剩 0小时0分30秒")
        XCTAssertEqual(ResetScheduleTiming.phase(for: post, now: date("2026-09-23T06:59:00Z")), .afterExact)
        XCTAssertEqual(ResetAnnouncementSummary.countdownText(for: post,
            now: date("2026-09-23T06:59:00Z"), language: .chinese),
            "预计时间已过 · 等待确认")
    }

    func testLosAngelesClockAndDatePhasesRespectDaylightSavingTransitions() {
        let beforeSpringJump = date("2026-03-08T09:59:59Z")
        let afterSpringJump = date("2026-03-08T10:00:00Z")
        XCTAssertEqual(ResetScheduleTiming.losAngelesNowText(beforeSpringJump, language: .chinese),
                       "洛杉矶现在：周日 01:59:59")
        XCTAssertEqual(ResetScheduleTiming.losAngelesNowText(afterSpringJump, language: .chinese),
                       "洛杉矶现在：周日 03:00:00")

        let spring = announcement("2026-03-09T06:59:00Z", title: "周日重置预告", summary: "周日",
                                  announcedAt: "2026-03-07T12:00:00Z")
        XCTAssertEqual(ResetScheduleTiming.target(for: spring)?.countdownDeadline,
                       date("2026-03-09T07:00:00Z"))
        XCTAssertEqual(ResetScheduleTiming.phase(for: spring, now: date("2026-03-08T08:00:00Z")),
                       .duringDate(date("2026-03-09T07:00:00Z")))
        XCTAssertEqual(ResetAnnouncementSummary.countdownText(for: spring,
            now: date("2026-03-08T08:00:00Z"), language: .chinese), "预告日内还剩 23小时0分0秒")

        let fall = announcement("2026-11-02T07:59:00Z", title: "周日重置预告", summary: "周日",
                                announcedAt: "2026-10-31T12:00:00Z")
        XCTAssertEqual(ResetScheduleTiming.target(for: fall)?.countdownDeadline,
                       date("2026-11-02T08:00:00Z"))
        XCTAssertEqual(ResetScheduleTiming.phase(for: fall, now: date("2026-11-01T07:00:00Z")),
                       .duringDate(date("2026-11-02T08:00:00Z")))
        XCTAssertEqual(ResetAnnouncementSummary.countdownText(for: fall,
            now: date("2026-11-01T07:00:00Z"), language: .chinese), "预告日内还剩 25小时0分0秒")
    }
}
