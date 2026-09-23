import XCTest
@testable import CodexNotch

final class ResetNotificationTextTests: XCTestCase {
    private func post(_ id: String = "notice", title: String = "预告", summary: String = "公开测试",
                      scheduledFor: Date? = nil, status: String? = "scheduled", now: Date) -> ResetAnnouncement {
        ResetAnnouncement(id: id, title: title, summary: summary, sourceURL: nil,
            announcedAt: now.addingTimeInterval(-60), scheduledFor: scheduledFor,
            kind: "regular", scope: "unspecified", status: status)
    }

    func testUnknownScheduleNeverInventsCountdown() {
        let now = Date()
        let body = ResetNotificationText.body(announcement: post(title: "有新的公告", scheduledFor: nil,
            status: "watch", now: now), now: now, count: 1)
        XCTAssertFalse(body.contains("还剩"))
        XCTAssertTrue(body.contains("NextReset"))
        XCTAssertTrue(body.contains("时间待公布"))
    }

    func testFutureScheduleUsesLosAngelesAndRemainingTime() {
        let now = Date(timeIntervalSince1970: 1_789_200_000)
        let body = ResetNotificationText.body(announcement: post(scheduledFor: now.addingTimeInterval(5_400),
            now: now), now: now, count: 2)
        XCTAssertTrue(body.contains("预计：洛杉矶"))
        XCTAssertTrue(body.contains("还剩 1小时30分0秒"))
        XCTAssertTrue(body.contains("对应北京：周"))
        XCTAssertFalse(body.contains("北京时间"))
        XCTAssertTrue(body.contains("共 2 条"))
        XCTAssertTrue(body.contains("接口时间"))
    }

    func testDateOnlyNotificationDisclosesEstimateAndSeconds() {
        let parser = ISO8601DateFormatter()
        let scheduled = parser.date(from: "2026-09-23T06:59:00Z")!
        let now = parser.date(from: "2026-09-23T06:58:30Z")!
        let body = ResetNotificationText.body(announcement: post(title: "周二预告", summary: "周二重置",
            scheduledFor: scheduled, now: now), now: now, count: 1)
        XCTAssertTrue(body.contains("预计：洛杉矶周二 23:59（日期边界估算，非官方精确时刻）"))
        XCTAssertTrue(body.contains("对应北京：周三"))
        XCTAssertTrue(body.contains("预计还剩 0小时1分30秒"))
        XCTAssertFalse(body.contains("9月23日"))
        XCTAssertFalse(body.contains("15:00"))
    }

    func testMixedBatchPrioritizesAdvanceDeadline() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let advance = ResetAnnouncement(id: "advance", title: "预告", summary: "公开测试", sourceURL: nil,
            announcedAt: now.addingTimeInterval(-60), scheduledFor: now.addingTimeInterval(5_400),
            kind: "regular", scope: "unspecified", status: "scheduled")
        let newer = ResetAnnouncement(id: "newer", title: "其他更新", summary: "公开测试", sourceURL: nil,
            announcedAt: now, scheduledFor: nil, kind: "regular", scope: "unspecified", status: nil)
        let batch = [advance, newer].map {
            ResetRecord(id: $0.id, announcement: $0, isUnread: true, occurredWhileAway: false)
        }
        XCTAssertEqual(ResetNotificationText.announcement(from: batch, now: now)?.id, "advance")
        XCTAssertEqual(ResetNotificationText.announcement(from: Array(batch.suffix(1)), now: now)?.id, "newer")
    }

    func testPassingTimeDoesNotAssertResetOccurred() {
        let now = Date()
        let body = ResetNotificationText.body(announcement: post(scheduledFor: now.addingTimeInterval(-60),
            now: now), now: now, count: 1)
        XCTAssertTrue(body.contains("执行状态请查看公告"))
        XCTAssertFalse(body.contains("已完成"))
    }

    func testIndependentPendingResetDoesNotReplaceExistingCountdown() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func post(_ id: String, offset: TimeInterval) -> ResetAnnouncement {
            ResetAnnouncement(id: id, title: "重置预告", summary: "测试", sourceURL: nil,
                announcedAt: now.addingTimeInterval(offset), scheduledFor: now.addingTimeInterval(3600 + offset),
                kind: "regular", scope: "unspecified", status: "scheduled")
        }
        let first = post("first", offset: 0), second = post("second", offset: 60)
        var ledger = ResetLedger()
        _ = ledger.ingest(NextResetSnapshot(announcements: [first], sourceCheckedAt: now, sourceIsFresh: true), at: now, occurredWhileAway: false)
        let updates = ledger.ingest(NextResetSnapshot(announcements: [first, second], sourceCheckedAt: now, sourceIsFresh: true), at: now, occurredWhileAway: false)
        XCTAssertEqual(ledger.pendingAnnouncements.map(\.id), ["first", "second"])
        XCTAssertEqual(ResetNotificationText.announcement(from: updates, now: now, pending: ledger.pendingAnnouncements)?.id, "second")
    }

    func testCompletedNoticeDoesNotShowOldFutureCountdown() {
        let now = Date()
        let body = ResetNotificationText.body(announcement: post(title: "完成",
            scheduledFor: now.addingTimeInterval(3600), status: " COMPLETED \n", now: now), now: now, count: 1)
        XCTAssertTrue(body.contains("来源已确认重置完成"))
        XCTAssertFalse(body.contains("还剩"))
    }
}
