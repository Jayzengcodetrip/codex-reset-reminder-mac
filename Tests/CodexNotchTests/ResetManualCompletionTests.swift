import Foundation
import XCTest
@testable import CodexNotch

final class ResetManualCompletionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testManualConfirmationEndsOnlySelectedPreviewAndKeepsPublicEvidenceAndUnread() {
        var ledger = loaded([post("first"), post("second", source: "https://x.com/thsottiaux/status/90002")])
        let prior = ledger.records.first { $0.id == "first" }!
        XCTAssertTrue(ledger.confirmResetManually(id: "first", at: now))
        let result = ledger.records.first { $0.id == "first" }!
        XCTAssertEqual(result.manualCompletedAt, now)
        XCTAssertEqual(result.announcement, prior.announcement)
        XCTAssertEqual(result.isUnread, prior.isUnread)
        XCTAssertEqual(result.occurredWhileAway, prior.occurredWhileAway)
        XCTAssertEqual(ledger.pendingAnnouncements.map(\.id), ["second"])
        XCTAssertNil(result.announcement.deliveryAt)
        XCTAssertEqual(result.announcement.status, "scheduled")
    }

    func testRepeatedConfirmationDoesNotMoveTimeOrCreateVersions() {
        var ledger = loaded([post("first")])
        let priorVersions = ledger.versions
        XCTAssertTrue(ledger.confirmResetManually(id: "first", at: now))
        XCTAssertFalse(ledger.confirmResetManually(id: "first", at: now.addingTimeInterval(100)))
        XCTAssertFalse(ledger.canConfirmResetManually(id: "first"))
        XCTAssertEqual(ledger.records[0].manualCompletedAt, now)
        XCTAssertEqual(ledger.versions, priorVersions)
    }

    func testConfirmationPersistsAcrossStoreReloadAndAbsentSnapshots() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ResetLedgerStore(url: directory.appendingPathComponent("ledger.json"))
        var ledger = loaded([post("first")])
        XCTAssertTrue(ledger.confirmResetManually(id: "first", at: now))
        try store.save(ledger)
        var restored = try XCTUnwrap(store.load())
        XCTAssertEqual(restored, ledger)
        XCTAssertTrue(restored.ingest(snapshot([]), at: now.addingTimeInterval(120), occurredWhileAway: true).isEmpty)
        XCTAssertTrue(restored.pendingAnnouncements.isEmpty)
        XCTAssertEqual(restored.records[0].manualCompletedAt, now)
    }

    func testSchemaOneWithoutManualMetadataStillDecodes() throws {
        let ledger = loaded([post("first")])
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger)) as? [String: Any])
        var rows = try XCTUnwrap(document["records"] as? [[String: Any]])
        for index in rows.indices { rows[index].removeValue(forKey: "manualCompletedAt") }
        document["records"] = rows
        let restored = try JSONDecoder().decode(ResetLedger.self, from: JSONSerialization.data(withJSONObject: document))
        XCTAssertEqual(restored.schemaVersion, 1)
        XCTAssertEqual(restored, ledger)
        XCTAssertTrue(restored.canConfirmResetManually(id: "first"))
    }

    func testHistoricalURLLinksSparseAliasAndOnlyThatOriginalPost() {
        let original = post("first")
        var ledger = loaded([original, post("independent", source: "https://x.com/thsottiaux/status/90002")])
        var sparse = original
        sparse.sourceURL = nil
        sparse.summary = "Source now omits URL"
        _ = ledger.ingest(snapshot([sparse]), at: now, occurredWhileAway: false)
        let alias = post("alias", source: "https://twitter.com/thsottiaux/status/90001?s=20")
        _ = ledger.ingest(snapshot([alias]), at: now, occurredWhileAway: false)
        XCTAssertTrue(ledger.confirmResetManually(id: "first", at: now))
        XCTAssertEqual(ledger.records.filter { $0.manualCompletedAt == now }.map(\.id).sorted(), ["alias", "first"])
        XCTAssertEqual(ledger.pendingAnnouncements.map(\.id), ["independent"])
        XCTAssertTrue(ledger.undoManualResetConfirmation(id: "alias"))
        XCTAssertTrue(ledger.records.allSatisfy { $0.manualCompletedAt == nil })
        XCTAssertEqual(ledger.pendingAnnouncements.count, 2)
    }

    func testAliasArrivingAfterManualConfirmationInheritsTimeWithoutNotification() {
        var ledger = loaded([post("first")])
        XCTAssertTrue(ledger.confirmResetManually(id: "first", at: now))
        let alias = post("alias", source: "https://twitter.com/thsottiaux/status/90001")
        XCTAssertTrue(ledger.ingest(snapshot([alias]), at: now.addingTimeInterval(120), occurredWhileAway: false).isEmpty)
        XCTAssertTrue(ledger.pendingAnnouncements.isEmpty)
        XCTAssertEqual(ledger.records.first { $0.id == "alias" }?.manualCompletedAt, now)
        XCTAssertFalse(ledger.records.first { $0.id == "alias" }!.isUnread)
    }

    func testSourceCorrectionPreservesConfirmationAndCanBeUndone() {
        var ledger = loaded([post("first")])
        XCTAssertTrue(ledger.confirmResetManually(id: "first", at: now))
        var revision = post("first")
        revision.summary = "Official schedule correction"
        revision.scheduledFor = now.addingTimeInterval(3600)
        XCTAssertTrue(ledger.ingest(snapshot([revision]), at: now.addingTimeInterval(120), occurredWhileAway: false).isEmpty)
        XCTAssertTrue(ledger.pendingAnnouncements.isEmpty)
        XCTAssertEqual(ledger.records[0].announcement, revision)
        XCTAssertEqual(ledger.records[0].manualCompletedAt, now)
        XCTAssertTrue(ledger.undoManualResetConfirmation(id: "first"))
        XCTAssertEqual(ledger.pendingAnnouncements.map(\.scheduledFor), [revision.scheduledFor])
        XCTAssertFalse(ledger.undoManualResetConfirmation(id: "first"))
    }

    func testTerminalOrUnknownRecordCannotBeConfirmed() {
        for status in ["completed", "confirmed", "rolling_out", "cancelled", "canceled"] {
            var completed = post("terminal")
            completed.status = status
            var ledger = loaded([completed])
            XCTAssertFalse(ledger.canConfirmResetManually(id: completed.id), status)
            XCTAssertFalse(ledger.confirmResetManually(id: completed.id, at: now), status)
        }
        var ledger = loaded([post("first")])
        XCTAssertFalse(ledger.confirmResetManually(id: "missing", at: now))
        XCTAssertFalse(ledger.confirmResetManually(id: "first", at: Date(timeIntervalSince1970: .infinity)))
    }

    func testOfficialCompletionAfterManualConfirmationRemainsOfficialAfterUndo() {
        var ledger = loaded([post("first")])
        XCTAssertTrue(ledger.confirmResetManually(id: "first", at: now))
        var official = post("first")
        official.status = "completed"
        official.deliveryAt = now.addingTimeInterval(30)
        official.deliveryKind = "regular"
        XCTAssertTrue(ledger.ingest(snapshot([official]), at: now.addingTimeInterval(120), occurredWhileAway: false).isEmpty)
        XCTAssertEqual(ledger.records[0].manualCompletedAt, now)
        XCTAssertEqual(ledger.records[0].announcement.deliveryAt, official.deliveryAt)
        XCTAssertTrue(ledger.undoManualResetConfirmation(id: "first"))
        XCTAssertTrue(ledger.pendingAnnouncements.isEmpty)
        XCTAssertFalse(ledger.canConfirmResetManually(id: "first"))
    }

    func testSparseKnownPendingAndUndatedPreviewsAreEligibleButSharedProfileIsIndependent() {
        var original = post("first", source: "https://x.com/thsottiaux")
        original.scheduledFor = nil
        var ledger = loaded([original, post("second", source: "https://x.com/thsottiaux")])
        var sparse = original
        sparse.status = "unknown-format"
        _ = ledger.ingest(snapshot([sparse]), at: now, occurredWhileAway: false)
        XCTAssertTrue(ledger.canConfirmResetManually(id: "first"))
        XCTAssertTrue(ledger.confirmResetManually(id: "first", at: now))
        XCTAssertEqual(ledger.pendingAnnouncements.map(\.id), ["second"])
    }

    func testDuplicateVersionProjectionWithSameIDDoesNotCrashIdentityOrManualFiltering() {
        let original = post("same")
        var revision = original
        revision.summary = "Additional projection of the same original post"
        let originalRecord = ResetRecord(id: "same", announcement: original, isUnread: false, occurredWhileAway: false)
        let revisedRecord = ResetRecord(id: "same", announcement: revision, isUnread: false, occurredWhileAway: false)
        XCTAssertEqual(ResetPendingAnnouncements.pending(from: [originalRecord, revisedRecord]).count, 1)
        XCTAssertEqual(ResetPendingAnnouncements.matchingRecordIDs(for: "same", records: [originalRecord, revisedRecord]), ["same"])
        var completed = revisedRecord
        completed.manualCompletedAt = now
        XCTAssertTrue(ResetPendingAnnouncements.pending(from: [originalRecord, completed]).isEmpty)
        XCTAssertEqual(ResetPendingAnnouncements.manualCompletionDates(records: [originalRecord, completed]), ["same": now])
    }

    private func post(_ id: String, source: String = "https://x.com/thsottiaux/status/90001") -> ResetAnnouncement {
        ResetAnnouncement(id: id, title: "Synthetic reset preview", summary: "Synthetic original text",
                          sourceURL: URL(string: source), announcedAt: now.addingTimeInterval(-300),
                          scheduledFor: now.addingTimeInterval(600), kind: "regular", scope: "unspecified", status: "scheduled")
    }

    private func snapshot(_ posts: [ResetAnnouncement]) -> NextResetSnapshot {
        NextResetSnapshot(announcements: posts, sourceCheckedAt: now, sourceIsFresh: true)
    }

    private func loaded(_ posts: [ResetAnnouncement]) -> ResetLedger {
        var ledger = ResetLedger()
        _ = ledger.ingest(snapshot(posts), at: now, occurredWhileAway: true)
        return ledger
    }
}
