import Foundation
import XCTest
@testable import CodexNotch

final class ResetTopPresentationTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    private func post(_ id: String = "tuesday", scheduled: String? = "2026-09-23T06:59:00Z",
                      status: String? = "scheduled", kind: String = "regular",
                      published: String = "2026-09-22T04:31:32Z", delivery: String? = nil,
                      title: String = "周二重置预告") -> ResetAnnouncement {
        var announcement = ResetAnnouncement(id: id, title: title, summary: title, sourceURL: nil,
            announcedAt: date(published), scheduledFor: scheduled.map(date),
            kind: kind, scope: "all", status: status)
        announcement.deliveryAt = delivery.map(date)
        return announcement
    }

    private func record(_ post: ResetAnnouncement) -> ResetRecord {
        ResetRecord(id: post.id, announcement: post, isUnread: false, occurredWhileAway: false)
    }

    private func state(pending: [ResetAnnouncement] = [], records: [ResetAnnouncement] = [],
                       at: String) -> ResetTopPresentation {
        .make(pending: pending, records: records.map(record), now: date(at))
    }

    func testElapsedClockFormatsEveryRequestedExampleAndDayBoundary() {
        for (seconds, expected) in [(271, "00:04:31"), (83071, "23:04:31"),
                                    (86791, "1天00:06:31"), (504451, "5天20:07:31"),
                                    (86399, "23:59:59"), (86400, "1天00:00:00")] {
            XCTAssertEqual(ResetTopPresentation.elapsedText(seconds: seconds, language: .chinese), expected)
        }
    }

    func testElapsedClockUsesLatestGeneralDeliveryNotCheckOrExpiredPreview() {
        let previous = post("previous", scheduled: nil, status: "rolling_out", delivery: "2026-09-22T06:00:00Z")
        let latest = post("latest", scheduled: nil, status: "rolling_out", delivery: "2026-09-22T06:59:59Z")
        var targeted = post("targeted", scheduled: nil, status: "rolling_out", delivery: "2026-09-22T07:00:00Z")
        targeted.scope = "limited"
        let snapshot = state(pending: [], records: [previous, latest, targeted], at: "2026-09-22T07:04:30Z")
        XCTAssertFalse(snapshot.didResetToday)
        XCTAssertEqual(snapshot.emptyText(language: .chinese), "暂无最新重置预告（距离上次重置已过00:04:31）")
        XCTAssertEqual(state(records: [latest], at: "2026-09-22T07:04:31Z").secondsSinceLastDelivery, 272)
    }

    func testDateOnlyCardSurvivesBothCountdownsUntilTheFinalSecond() {
        let notice = post()
        let expected: [(String, String)] = [
            ("2026-09-22T06:59:59Z", "距预告日开始还剩 0小时0分1秒"),
            ("2026-09-22T07:00:00Z", "预告日内还剩 24小时0分0秒"),
            ("2026-09-23T06:59:59Z", "预告日内还剩 0小时0分1秒")
        ]
        for (instant, text) in expected {
            let result = state(pending: [notice], at: instant)
            XCTAssertEqual(result.announcements, [notice])
            XCTAssertFalse(result.didResetToday)
            XCTAssertEqual(ResetAnnouncementSummary.countdownText(for: notice, now: date(instant), language: .chinese), text)
        }
    }

    func testExpiredUnfulfilledNoticeOnlyDisappearsFromTopAndDoesNotBecomeCompleted() {
        let notice = post()
        let records = [record(notice)]
        let result = ResetTopPresentation.make(pending: [notice], records: records,
                                               now: date("2026-09-23T07:00:00Z"))
        XCTAssertTrue(result.announcements.isEmpty)
        XCTAssertFalse(result.didResetToday)
        XCTAssertEqual(result.emptyText(language: .chinese), "暂无最新重置预告")
        XCTAssertEqual(records.first?.announcement.status, "scheduled")
        XCTAssertEqual(ResetPendingAnnouncements.pending(from: records), [notice])
    }

    func testCompletionBannerExpiresAtLosAngelesMidnightWithoutAnotherSourceCheck() {
        let completed = post(status: "completed", delivery: "2026-09-22T20:00:00Z")
        let today = state(records: [completed], at: "2026-09-23T06:59:59Z")
        XCTAssertTrue(today.didResetToday)
        XCTAssertEqual(today.emptyText(language: .chinese), "暂无最新重置预告（今天已重置）")
        let tomorrow = state(records: [completed], at: "2026-09-23T07:00:00Z")
        XCTAssertFalse(tomorrow.didResetToday)
        XCTAssertEqual(tomorrow.emptyText(language: .chinese), "暂无最新重置预告（距离上次重置已过11:00:00）")
    }

    func testTodayUsesLosAngelesCalendarEvenWhenBeijingHasChangedDates() {
        let completed = post(status: "completed", delivery: "2026-09-22T15:59:59Z")
        XCTAssertTrue(state(records: [completed], at: "2026-09-22T16:00:01Z").didResetToday)
        XCTAssertTrue(state(records: [completed], at: "2026-09-23T06:59:59Z").didResetToday)
        XCTAssertFalse(state(records: [completed], at: "2026-09-23T07:00:00Z").didResetToday)
    }

    func testExactTimeWaitsUntilItsLosAngelesDayEnds() {
        let exact = post(scheduled: "2026-09-22T19:30:00Z", title: "周二 12:30 PDT 重置")
        XCTAssertEqual(state(pending: [exact], at: "2026-09-22T19:30:00Z").announcements, [exact])
        XCTAssertEqual(ResetScheduleTiming.phase(for: exact, now: date("2026-09-22T19:30:00Z")), .afterExact)
        XCTAssertEqual(state(pending: [exact], at: "2026-09-23T06:59:59Z").announcements, [exact])
        XCTAssertTrue(state(pending: [exact], at: "2026-09-23T07:00:00Z").announcements.isEmpty)
    }

    func testUnknownScheduleRemainsVisible() {
        let unknown = post(scheduled: nil, status: "watch")
        XCTAssertEqual(state(pending: [unknown], at: "2026-10-01T07:00:00Z").announcements, [unknown])
    }

    func testCompletingOneNoticeDoesNotHideAnother() {
        let completed = post(status: "completed", delivery: "2026-09-22T20:00:00Z")
        let other = post("wednesday", scheduled: "2026-09-24T06:59:00Z", title: "周三重置预告")
        let result = state(pending: [other], records: [completed, other], at: "2026-09-22T21:00:00Z")
        XCTAssertEqual(result.announcements, [other])
        XCTAssertTrue(result.didResetToday)
        let expiredSibling = state(pending: [post(), other], at: "2026-09-23T07:00:00Z")
        XCTAssertEqual(expiredSibling.announcements, [other])
    }

    func testEachSupportedDeliveryStateCountsForRegularAndBanked() {
        for kind in ["regular", "banked"] {
            for status in ["completed", "confirmed", "propagated", "rolling_out", " COMPLETED "] {
                let delivered = post(status: status, kind: kind, delivery: "2026-09-22T20:00:00Z")
                let result = state(pending: [delivered], records: [delivered], at: "2026-09-22T21:00:00Z")
                XCTAssertTrue(result.didResetToday, "\(kind) \(status)")
                XCTAssertTrue(result.announcements.isEmpty)
            }
        }
        for status in ["scheduled", "pending", "cancelled", "canceled"] {
            let notDelivered = post(status: status, delivery: "2026-09-22T20:00:00Z")
            XCTAssertFalse(state(records: [notDelivered], at: "2026-09-22T21:00:00Z").didResetToday)
        }
    }

    func testFutureDeliveryEvidenceDoesNotCountEarly() {
        let future = post(status: "completed", delivery: "2026-09-22T22:00:00Z")
        XCTAssertFalse(state(records: [future], at: "2026-09-22T21:00:00Z").didResetToday)
        XCTAssertTrue(state(records: [future], at: "2026-09-22T22:00:00Z").didResetToday)
    }

    func testOldCacheDoesNotTreatAFirstCheckOrOriginalAnnouncementTimeAsDelivery() throws {
        let datedOriginal = post(status: "completed", published: "2026-09-22T09:00:00Z")
        let oldCompletion = post("old-completion", scheduled: nil, status: "completed",
                                 published: "2026-09-21T20:00:00Z")
        let rows = [record(datedOriginal), record(oldCompletion)]
        let encoded = try JSONEncoder().encode(rows)
        let restored = try JSONDecoder().decode([ResetRecord].self, from: encoded)
        XCTAssertFalse(ResetTopPresentation.make(pending: [], records: restored,
            now: date("2026-09-22T21:00:00Z")).didResetToday)
        let freshCompletionPost = post("completion-post", scheduled: nil, status: "completed",
                                       published: "2026-09-22T20:00:00Z")
        XCTAssertTrue(state(records: [freshCompletionPost], at: "2026-09-22T21:00:00Z").didResetToday)
    }

    func testDayBoundariesRespectSpringAndFallDaylightSavingChanges() {
        let fixtures: [(String, String, String, String)] = [
            ("2026-03-09T06:59:00Z", "2026-03-08T08:30:00Z", "2026-03-09T06:59:59Z", "2026-03-09T07:00:00Z"),
            ("2026-11-02T07:59:00Z", "2026-11-01T07:30:00Z", "2026-11-02T07:59:59Z", "2026-11-02T08:00:00Z")
        ]
        for (scheduled, deliveredAt, lastSecond, nextMidnight) in fixtures {
            let pending = post(scheduled: scheduled, title: "周日重置预告")
            let completed = post(scheduled: scheduled, status: "completed", delivery: deliveredAt,
                                 title: "周日重置预告")
            XCTAssertEqual(state(pending: [pending], at: lastSecond).announcements, [pending])
            XCTAssertTrue(state(pending: [pending], at: nextMidnight).announcements.isEmpty)
            XCTAssertTrue(state(records: [completed], at: lastSecond).didResetToday)
            XCTAssertFalse(state(records: [completed], at: nextMidnight).didResetToday)
        }
    }
}
