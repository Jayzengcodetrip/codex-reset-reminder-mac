import Foundation
import XCTest
@testable import CodexNotch

final class ResetUndatedSummaryTests: XCTestCase {
    func testRelativeWordingStaysQuotedWithOriginalPublicationTime() {
        let notice = ResetAnnouncement(id: "next-week", title: "重置预告",
            summary: "原帖摘录：“More resets coming next week” 完整条件请查看原帖。", sourceURL: nil,
            announcedAt: ISO8601DateFormatter().date(from: "2026-09-26T21:41:35Z"), scheduledFor: nil,
            kind: "regular", scope: "unspecified", status: "scheduled")
        XCTAssertEqual(ResetUndatedSummary.excerpt(notice, language: .chinese), "原帖称：“More resets coming next week”")
        XCTAssertEqual(ResetUndatedSummary.publication(notice, language: .chinese), "原帖发布：09-27 05:41（北京）")
        XCTAssertNil(notice.scheduledFor)
    }

    func testSummaryHandlesMissingTimestampAndBoundsSourceExcerpt() {
        var notice = ResetAnnouncement(id: "unknown", title: "尚未公布时间", summary: "", sourceURL: nil,
            announcedAt: nil, scheduledFor: nil, kind: "regular", scope: "unspecified", status: "scheduled")
        XCTAssertEqual(ResetUndatedSummary.publication(notice, language: .chinese), "原帖发布时间未提供")
        XCTAssertEqual(ResetUndatedSummary.excerpt(notice, language: .chinese), "公告摘要：尚未公布时间")
        notice.summary = String(repeating: "source ", count: 100)
        XCTAssertTrue(ResetUndatedSummary.excerpt(notice, language: .english).count < 205)
        XCTAssertTrue(ResetUndatedSummary.excerpt(notice, language: .english).hasPrefix("Announcement summary:"))
        XCTAssertEqual(ResetUndatedSummary.title(count: 2, language: .chinese), "有 2 条待定预告")
        XCTAssertEqual(ResetUndatedSummary.title(count: 1, language: .english), "1 pending preview")
    }

    func testElapsedTimerCountsFromPublicationTimeAndRejectsMissingOrFutureDates() {
        let published = Date(timeIntervalSince1970: 1_800_000_000)
        let notice = ResetAnnouncement(id: "undated", title: "待定", summary: "原帖摘录：“Soon”", sourceURL: nil,
            announcedAt: published, scheduledFor: nil, kind: "regular", scope: "broad", status: "scheduled")
        XCTAssertEqual(ResetUndatedSummary.elapsedText(for: notice, now: published.addingTimeInterval(3_665), language: .chinese),
                       "预告已发出 01:01:05")
        XCTAssertEqual(ResetUndatedSummary.elapsedText(for: notice, now: published.addingTimeInterval(90_005), language: .chinese),
                       "预告已发出 1天01:00:05")
        XCTAssertEqual(ResetUndatedSummary.elapsedText(for: notice, now: published.addingTimeInterval(3_665), language: .english),
                       "Posted 01:01:05 ago")
        XCTAssertNil(ResetUndatedSummary.elapsedText(for: notice, now: published.addingTimeInterval(-1), language: .chinese))
        var missing = notice
        missing.announcedAt = nil
        XCTAssertNil(ResetUndatedSummary.elapsedText(for: missing, now: published.addingTimeInterval(60), language: .chinese))
    }
}
