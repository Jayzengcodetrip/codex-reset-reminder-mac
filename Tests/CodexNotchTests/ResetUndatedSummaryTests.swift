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
        XCTAssertEqual(ResetUndatedSummary.title(count: 2, language: .chinese), "有 2 条待定预告 · 具体时间未公布")
    }
}
