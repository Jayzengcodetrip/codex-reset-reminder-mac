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

    private func post(_ id: String, age: TimeInterval = 0) -> ResetAnnouncement {
        ResetAnnouncement(id: id, title: "预告", summary: "公开测试内容", sourceURL: nil,
            announcedAt: now.addingTimeInterval(-age), scheduledFor: now.addingTimeInterval(600),
            kind: "regular", scope: "all", status: "scheduled")
    }

    private func snapshot(_ posts: [ResetAnnouncement]) -> NextResetSnapshot {
        NextResetSnapshot(announcements: posts, sourceCheckedAt: now, sourceIsFresh: true)
    }
}
