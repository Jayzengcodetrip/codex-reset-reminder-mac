import Foundation
import XCTest
@testable import CodexNotch

@MainActor
final class ResetManualDismissalTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testDismissalHidesOnlySelectedPreviewAndLeavesElapsedResetClockUntouched() {
        let undated = post("undated", postID: "92001", scheduled: false)
        let dated = post("dated", postID: "92002", scheduled: true)
        let delivery = ResetAnnouncement(
            id: "delivery", title: "官方已重置", summary: "We have reset usage limits.",
            sourceURL: URL(string: "https://x.com/thsottiaux/status/92000"),
            announcedAt: now.addingTimeInterval(-3_600), scheduledFor: nil,
            kind: "regular", scope: "broad", status: "completed",
            deliveryAt: now.addingTimeInterval(-3_600), deliveryKind: "regular"
        )
        var ledger = ResetLedger()
        ledger.records = [
            ResetRecord(id: undated.id, announcement: undated, isUnread: false, occurredWhileAway: false),
            ResetRecord(id: dated.id, announcement: dated, isUnread: false, occurredWhileAway: false),
            ResetRecord(id: delivery.id, announcement: delivery, isUnread: false, occurredWhileAway: false)
        ]
        ledger.versions = Dictionary(uniqueKeysWithValues: ledger.records.map { ($0.id, [$0.announcement]) })

        XCTAssertTrue(ledger.dismissPreviewManually(id: undated.id, at: now))
        XCTAssertEqual(ledger.pendingAnnouncements.map(\.id), [dated.id])
        XCTAssertEqual(ledger.records.first { $0.id == undated.id }?.manualDismissedAt, now)
        XCTAssertNil(ledger.records.first { $0.id == undated.id }?.manualCompletedAt)
        XCTAssertEqual(ledger.records.first { $0.id == undated.id }?.announcement.status, "scheduled")

        let afterOneDismissal = ResetTopPresentation.make(
            pending: ledger.pendingAnnouncements, records: ledger.records, now: now
        )
        XCTAssertTrue(afterOneDismissal.hasActivePreview)
        XCTAssertTrue(afterOneDismissal.undatedAnnouncements.isEmpty)
        XCTAssertEqual(afterOneDismissal.announcements.map(\.id), [dated.id])
        XCTAssertEqual(afterOneDismissal.secondsSinceLastDelivery, 3_600)
        XCTAssertEqual(afterOneDismissal.latestDeliveryOrigin, .publicAnnouncement)

        XCTAssertTrue(ledger.dismissPreviewManually(id: dated.id, at: now))
        let afterAllDismissed = ResetTopPresentation.make(
            pending: ledger.pendingAnnouncements, records: ledger.records, now: now
        )
        XCTAssertFalse(afterAllDismissed.hasActivePreview)
        XCTAssertEqual(afterAllDismissed.secondsSinceLastDelivery, 3_600)
        XCTAssertEqual(afterAllDismissed.latestDeliveryOrigin, .publicAnnouncement)

        XCTAssertTrue(ledger.undoManualPreviewDismissal(id: undated.id))
        let restored = ResetTopPresentation.make(
            pending: ledger.pendingAnnouncements, records: ledger.records, now: now
        )
        XCTAssertTrue(restored.hasActivePreview)
        XCTAssertEqual(restored.undatedAnnouncements.map(\.id), [undated.id])
        XCTAssertEqual(restored.secondsSinceLastDelivery, 3_600)
    }

    func testDismissalPersistsAcrossReloadRefreshAndAliases() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexNotch-Dismiss-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ResetLedgerStore(url: directory.appendingPathComponent("ledger.json"))
        let original = post("orig", postID: "93001", scheduled: false)
        var ledger = ResetLedger()
        _ = ledger.ingest(NextResetSnapshot(announcements: [original], sourceCheckedAt: now, sourceIsFresh: true),
                          at: now, occurredWhileAway: true)
        XCTAssertTrue(ledger.dismissPreviewManually(id: original.id, at: now))
        try store.save(ledger)

        var restored = try XCTUnwrap(store.load())
        XCTAssertEqual(restored, ledger)
        let alias = post("alias", postID: "93001", scheduled: false)
        XCTAssertTrue(restored.ingest(NextResetSnapshot(announcements: [alias], sourceCheckedAt: now, sourceIsFresh: true),
                                      at: now.addingTimeInterval(60), occurredWhileAway: false).isEmpty)
        XCTAssertTrue(restored.pendingAnnouncements.isEmpty)
        XCTAssertEqual(restored.records.first { $0.id == "alias" }?.manualDismissedAt, now)
    }

    func testSchemaOneWithoutDismissalFieldStillDecodes() throws {
        var ledger = ResetLedger()
        let preview = post("orig", postID: "94001", scheduled: false)
        ledger.records = [ResetRecord(id: preview.id, announcement: preview, isUnread: false, occurredWhileAway: false)]
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger)) as? [String: Any])
        var rows = try XCTUnwrap(document["records"] as? [[String: Any]])
        for index in rows.indices { rows[index].removeValue(forKey: "manualDismissedAt") }
        document["records"] = rows
        let decoded = try JSONDecoder().decode(ResetLedger.self, from: JSONSerialization.data(withJSONObject: document))
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertNil(decoded.records[0].manualDismissedAt)
        XCTAssertTrue(decoded.canDismissPreviewManually(id: preview.id))
    }

    func testDismissalSaveFailureKeepsStateIntactAndRetrySucceeds() async {
        let preview = post("orig", postID: "95001", scheduled: false)
        var ledger = ResetLedger()
        _ = ledger.ingest(NextResetSnapshot(announcements: [preview], sourceCheckedAt: now, sourceIsFresh: true),
                          at: now, occurredWhileAway: true)
        let store = DismissalMemoryStore(ledger: ledger)
        let monitor = ResetMonitor(store: store, fetchSnapshot: {
            NextResetSnapshot(announcements: [preview], sourceCheckedAt: self.now, sourceIsFresh: true)
        }, now: { self.now }, idleSeconds: { 0 }, minimumRefreshInterval: 0)
        defer { monitor.stop() }

        store.failSave = true
        XCTAssertFalse(monitor.dismissPreviewManually(id: preview.id))
        XCTAssertNotNil(monitor.manualConfirmationErrorMessage)
        XCTAssertEqual(monitor.pendingAnnouncements.map(\.id), [preview.id])

        store.failSave = false
        XCTAssertTrue(monitor.dismissPreviewManually(id: preview.id))
        XCTAssertNil(monitor.manualConfirmationErrorMessage)
        XCTAssertTrue(monitor.pendingAnnouncements.isEmpty)
    }

    private func post(_ id: String, postID: String, scheduled: Bool) -> ResetAnnouncement {
        ResetAnnouncement(
            id: id, title: "Synthetic preview", summary: "原帖摘录：“Soon”",
            sourceURL: URL(string: "https://x.com/thsottiaux/status/\(postID)"),
            announcedAt: now.addingTimeInterval(-300),
            scheduledFor: scheduled ? now.addingTimeInterval(3_600) : nil,
            kind: "regular", scope: "broad", status: "scheduled"
        )
    }
}

private final class DismissalMemoryStore: ResetLedgerStoring {
    var ledger: ResetLedger?
    var failSave = false
    init(ledger: ResetLedger?) { self.ledger = ledger }
    func load() throws -> ResetLedger? { ledger }
    func save(_ value: ResetLedger) throws {
        if failSave { throw CocoaError(.fileWriteNoPermission) }
        ledger = value
    }
}
