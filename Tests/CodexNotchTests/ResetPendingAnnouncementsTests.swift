import Foundation
import XCTest
@testable import CodexNotch

final class ResetPendingAnnouncementsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testPendingAnnouncementOutcomeChecks() throws {
        XCTAssertGreaterThanOrEqual(try ResetPendingAnnouncements.runSelfChecks(), 30)
    }

    func testSecondPendingAnnouncementDoesNotReplaceFirstCountdown() {
        var ledger = ResetLedger()
        let first = post("first", age: 100)
        let second = post("second")
        _ = ledger.ingest(snapshot([first]), at: now, occurredWhileAway: false)
        ledger.markRead(id: first.id)
        _ = ledger.ingest(snapshot([second]), at: now, occurredWhileAway: false)
        XCTAssertEqual(ledger.pendingAnnouncements.map(\.id), [first.id, second.id])
    }

    func testCompletingSecondLeavesFirstPending() {
        var ledger = ResetLedger()
        let first = post("first", age: 100)
        var second = post("second")
        _ = ledger.ingest(snapshot([first, second]), at: now, occurredWhileAway: false)
        second.status = "completed"
        _ = ledger.ingest(snapshot([second]), at: now, occurredWhileAway: false)
        XCTAssertEqual(ledger.pendingAnnouncements.map(\.id), [first.id])
    }

    func testKnownPendingSurvivesUnrecognizedSparseRevision() {
        var ledger = ResetLedger()
        var first = post("first")
        _ = ledger.ingest(snapshot([first]), at: now, occurredWhileAway: false)
        first.status = "unknown-source-status"
        first.scheduledFor = nil
        _ = ledger.ingest(snapshot([first]), at: now, occurredWhileAway: false)
        XCTAssertEqual(ledger.pendingAnnouncements.map(\.id), [first.id])
        XCTAssertNil(ledger.pendingAnnouncements.first?.scheduledFor)
    }

    func testPreviouslyNumberedLedgerLoadsWithoutDataLoss() throws {
        var ledger = ResetLedger()
        let first = post("first")
        _ = ledger.ingest(snapshot([first]), at: now, occurredWhileAway: false)
        ledger.markRead(id: first.id)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger)) as! [String: Any]
        json["preannouncementSequence"] = ["round": 1, "lastNumber": 1]
        let restored = try JSONDecoder().decode(ResetLedger.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored, ledger)
        XCTAssertEqual(restored.pendingAnnouncements, [first])
        XCTAssertFalse(restored.records[0].isUnread)
    }

    func testTwoDateOnlyNoticesRemainIndependentAfterOneDeadlinePassesAndLedgerReloads() throws {
        let parser = ISO8601DateFormatter()
        let before = parser.date(from: "2026-09-23T06:58:30Z")!
        let after = parser.date(from: "2026-09-23T07:00:00Z")!
        let first = ResetAnnouncement(id: "tuesday", title: "周二重置预告", summary: "周二",
            sourceURL: nil, announcedAt: before.addingTimeInterval(-3_600),
            scheduledFor: parser.date(from: "2026-09-23T06:59:00Z")!,
            kind: "regular", scope: "all", status: "scheduled")
        let second = ResetAnnouncement(id: "wednesday", title: "周三重置预告", summary: "周三",
            sourceURL: nil, announcedAt: before,
            scheduledFor: parser.date(from: "2026-09-24T06:59:00Z")!,
            kind: "regular", scope: "all", status: "scheduled")
        var ledger = ResetLedger()
        _ = ledger.ingest(NextResetSnapshot(announcements: [first, second], sourceCheckedAt: before,
            sourceIsFresh: true), at: before, occurredWhileAway: false)
        XCTAssertEqual(ledger.pendingAnnouncements.map(\.id), ["tuesday", "wednesday"])
        XCTAssertEqual(ResetAnnouncementSummary.countdownText(for: first, now: before, language: .chinese),
                       "预计还剩 0小时1分30秒")

        // Neither time passing nor a later source snapshot omitting both posts confirms either reset.
        _ = ledger.ingest(NextResetSnapshot(announcements: [], sourceCheckedAt: after,
            sourceIsFresh: true), at: after, occurredWhileAway: false)
        let restored = try JSONDecoder().decode(ResetLedger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(restored.pendingAnnouncements.map(\.id), ["tuesday", "wednesday"])
        XCTAssertEqual(ResetAnnouncementSummary.countdownText(for: restored.pendingAnnouncements[0],
            now: after, language: .chinese), "预计时间已过 · 等待确认")
        XCTAssertTrue(ResetAnnouncementSummary.countdownText(for: restored.pendingAnnouncements[1],
            now: after, language: .chinese).hasPrefix("预计还剩 "))

        var completed = first
        completed.status = "completed"
        var revised = restored
        _ = revised.ingest(NextResetSnapshot(announcements: [completed], sourceCheckedAt: after,
            sourceIsFresh: true), at: after, occurredWhileAway: false)
        XCTAssertEqual(revised.pendingAnnouncements.map(\.id), ["wednesday"])
    }

    private func post(_ id: String, age: TimeInterval = 0) -> ResetAnnouncement {
        ResetAnnouncement(id: id, title: "预告", summary: "公开测试内容", sourceURL: nil,
            announcedAt: now.addingTimeInterval(-age), scheduledFor: now.addingTimeInterval(600),
            kind: "regular", scope: "all", status: "scheduled")
    }

    private func snapshot(_ posts: [ResetAnnouncement]) -> NextResetSnapshot {
        NextResetSnapshot(announcements: posts, sourceCheckedAt: now, sourceIsFresh: true)
    }
}
