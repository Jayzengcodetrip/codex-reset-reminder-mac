import Foundation
import XCTest
@testable import CodexNotch

final class ResetLedgerTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFirstArchiveBecomesReadBaselineButPendingAnnouncementStaysVisible() {
        var ledger = ResetLedger()
        var pending = announcement("upcoming")
        pending.status = "scheduled"
        pending.scheduledFor = now.addingTimeInterval(600)
        let notifications = ledger.ingest(snapshot([announcement("old"), pending]), at: now, occurredWhileAway: true)
        XCTAssertTrue(notifications.isEmpty)
        XCTAssertFalse(ledger.records.first(where: { $0.id == "old" })!.isUnread)
        XCTAssertTrue(ledger.records.first(where: { $0.id == "upcoming" })!.isUnread)
        XCTAssertTrue(ledger.baselineCompleted)
    }

    func testNewPostsAndMaterialUpdatesAreUnreadOnlyOnce() {
        var ledger = ResetLedger()
        let initial = announcement("old")
        _ = ledger.ingest(snapshot([initial]), at: now, occurredWhileAway: true)
        let next = announcement("new")
        XCTAssertEqual(ledger.ingest(snapshot([initial, next]), at: now, occurredWhileAway: false).map(\.id), ["new"])
        XCTAssertTrue(ledger.ingest(snapshot([initial, next]), at: now, occurredWhileAway: false).isEmpty)
        ledger.markRead(id: "new")
        var updated = next
        updated.summary = "计划已推迟"
        XCTAssertEqual(ledger.ingest(snapshot([initial, updated]), at: now, occurredWhileAway: false).count, 1)
        XCTAssertTrue(ledger.records.first(where: { $0.id == "new" })!.isUnread)
        XCTAssertEqual(ledger.versions["new"]?.count, 2)
    }

    func testCatchUpRetainsEveryNewRecordAndUnreadAcrossRestartAndArchiveRemoval() throws {
        var ledger = ResetLedger()
        _ = ledger.ingest(snapshot([announcement("old")]), at: now, occurredWhileAway: true)
        let changes = ledger.ingest(snapshot([announcement("a"), announcement("b")]), at: now, occurredWhileAway: true)
        XCTAssertEqual(changes.count, 2)
        XCTAssertTrue(changes.allSatisfy { $0.isUnread && $0.occurredWhileAway })
        var restored = try JSONDecoder().decode(ResetLedger.self, from: JSONEncoder().encode(ledger))
        XCTAssertTrue(restored.ingest(snapshot([]), at: now, occurredWhileAway: false).isEmpty)
        XCTAssertEqual(restored.records.filter(\.isUnread).count, 2)
        restored.markRead(id: "a")
        XCTAssertEqual(restored.records.filter { $0.isUnread && $0.occurredWhileAway }.map(\.id), ["b"])
        XCTAssertEqual(restored.records.count, 3)
    }

    func testMetadataOnlyChangeDoesNotReopenReadAnnouncement() {
        var ledger = ResetLedger()
        var post = announcement("post")
        post.status = "completed"
        _ = ledger.ingest(snapshot([post]), at: now, occurredWhileAway: true)
        post.announcedAt = now.addingTimeInterval(-500)
        post.sourceURL = URL(string: "https://x.com/thsottiaux/status/post")
        post.status = nil // Older history rows need not repeat latest_confirmed_reset metadata.
        XCTAssertTrue(ledger.ingest(snapshot([post]), at: now, occurredWhileAway: false).isEmpty)
        XCTAssertEqual(ledger.records.first?.announcement.status, "completed")
        XCTAssertFalse(ledger.records.first!.isUnread)
    }

    func testPreviouslySeenCachedVersionDoesNotReplayOrReplaceNewerVersion() {
        var ledger = ResetLedger()
        let first = announcement("post")
        _ = ledger.ingest(snapshot([first]), at: now, occurredWhileAway: true)
        var revision = first
        revision.summary = "更正后的时间"
        _ = ledger.ingest(snapshot([revision]), at: now, occurredWhileAway: false)
        ledger.markRead(id: "post")
        XCTAssertTrue(ledger.ingest(snapshot([first]), at: now, occurredWhileAway: false).isEmpty)
        XCTAssertEqual(ledger.records.first?.announcement.summary, "更正后的时间")
        XCTAssertFalse(ledger.records.first!.isUnread)
    }

    func testStaleSourceIsRecordedAsStaleWithoutLosingAnnouncements() {
        var ledger = ResetLedger()
        _ = ledger.ingest(snapshot([announcement("post")], fresh: false), at: now, occurredWhileAway: true)
        XCTAssertEqual(ledger.lastSuccessfulCheck, now)
        XCTAssertFalse(ledger.sourceIsFresh)
        XCTAssertEqual(ledger.records.count, 1)
    }

    func testStoreRoundTripPreservesReadAndVersionState() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ResetLedgerStore(url: folder.appendingPathComponent("ledger.json"))
        XCTAssertNil(try store.load())
        var ledger = ResetLedger()
        _ = ledger.ingest(snapshot([announcement("post")]), at: now, occurredWhileAway: true)
        try store.save(ledger)
        XCTAssertEqual(try store.load(), ledger)
    }

    private func announcement(_ id: String) -> ResetAnnouncement {
        ResetAnnouncement(id: id, title: "额度更新", summary: "以原公告适用范围为准", sourceURL: nil,
                          announcedAt: now.addingTimeInterval(-1000), scheduledFor: nil, kind: "regular", scope: "unspecified", status: nil)
    }
    private func snapshot(_ posts: [ResetAnnouncement], fresh: Bool = true) -> NextResetSnapshot {
        NextResetSnapshot(announcements: posts, sourceCheckedAt: now, sourceIsFresh: fresh)
    }
}
