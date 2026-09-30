import Foundation
import XCTest
@testable import CodexNotch

final class AccountResetReceiptCacheTests: XCTestCase {
    private var directory: URL!
    private var url: URL { directory.appendingPathComponent("account-reset-receipts.json") }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReceiptCacheTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func credit(_ id: String, grant: Date?, type: String? = "codex_rate_limits",
                        supported: Bool? = true, title: String? = "Full reset",
                        description: String? = nil) -> ResetCredit {
        ResetCredit(id: id, title: title, expiresAt: now.addingTimeInterval(86_400),
            grantedAt: grant, resetType: type, creditDescription: description, isSupportedByPlan: supported)
    }

    func testFirstSnapshotSelectsLatestGrantAndRestartKeepsItsOriginalTime() throws {
        let cache = AccountResetReceiptCache(url: url)
        let latest = now.addingTimeInterval(-3_600)
        let receipt = try cache.update(accountID: "synthetic-account-a", credits: [
            credit("new", grant: latest), credit("old", grant: now.addingTimeInterval(-86_400))
        ], now: now)
        XCTAssertEqual(receipt?.grantedAt, latest)
        XCTAssertEqual(AccountResetReceiptCache(url: url).receipt(for: "synthetic-account-a", now: now), receipt)
    }

    func testConsumptionEmptySnapshotsAndOlderSnapshotsCannotRollBackReceipt() throws {
        let cache = AccountResetReceiptCache(url: url)
        let receipt = try cache.update(accountID: "a", credits: [credit("first", grant: now.addingTimeInterval(-120))], now: now)
        XCTAssertEqual(try cache.update(accountID: "a", credits: [], now: now), receipt)
        XCTAssertEqual(try cache.update(accountID: "a", credits: [credit("older", grant: now.addingTimeInterval(-3600))], now: now), receipt)
        XCTAssertEqual(cache.receipt(for: "a", now: now.addingTimeInterval(500)), receipt)
        let newer = try cache.update(accountID: "a", credits: [credit("newer", grant: now.addingTimeInterval(-60))], now: now)
        XCTAssertEqual(newer?.grantedAt, now.addingTimeInterval(-60))
    }

    func testAccountSwitchMissingIdentityAndDiskContentAreIsolated() throws {
        let cache = AccountResetReceiptCache(url: url)
        let a = try cache.update(accountID: "synthetic-account-a", credits: [credit("secret-credit-id-a", grant: now.addingTimeInterval(-120))], now: now)
        XCTAssertNil(cache.receipt(for: "synthetic-account-b", now: now))
        XCTAssertNil(try cache.update(accountID: "synthetic-account-b", credits: [], now: now))
        let b = try cache.update(accountID: "synthetic-account-b", credits: [credit("secret-credit-id-b", grant: now.addingTimeInterval(-60))], now: now)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(cache.receipt(for: "synthetic-account-a", now: now), a)
        XCTAssertEqual(cache.receipt(for: "synthetic-account-b", now: now), b)
        for missing in [nil, "", " \n "] {
            XCTAssertNil(cache.receipt(for: missing, now: now))
            XCTAssertNil(try cache.update(accountID: missing, credits: [credit("ignored", grant: now)], now: now))
        }
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("synthetic-account"))
        XCTAssertFalse(text.contains("secret-credit-id"))
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let accounts = try XCTUnwrap(document["accounts"] as? [String: Any])
        XCTAssertEqual(accounts.count, 2)
        XCTAssertTrue(accounts.keys.allSatisfy { $0.count == 64 })
    }

    func testOnlyKnownSupportedFullCreditsWithPastExactGrantsEstablishEvidence() throws {
        let cache = AccountResetReceiptCache(url: url)
        let rejected = [credit("missing", grant: nil), credit("future", grant: now.addingTimeInterval(1)),
            credit("unknown", grant: now, type: "another_credit"), credit("no-type", grant: now, type: nil),
            credit("unsupported", grant: now, supported: false), credit("invalid", grant: Date(timeIntervalSince1970: .nan)),
            credit("ancient", grant: Date(timeIntervalSince1970: 0))]
        XCTAssertNil(try cache.update(accountID: "a", credits: rejected, now: now))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try cache.update(accountID: "a", credits: [credit("valid", grant: now, supported: nil)], now: now)?.grantedAt, now)
    }

    func testFutureRecordAfterClockMovesBackIsHiddenWithoutOverwritingIt() throws {
        let cache = AccountResetReceiptCache(url: url)
        _ = try cache.update(accountID: "a", credits: [credit("valid", grant: now)], now: now)
        let stored = try Data(contentsOf: url)
        let earlier = now.addingTimeInterval(-100)
        XCTAssertNil(cache.receipt(for: "a", now: earlier))
        XCTAssertNil(try cache.update(accountID: "a", credits: [credit("older", grant: earlier)], now: earlier))
        XCTAssertEqual(try Data(contentsOf: url), stored)
        XCTAssertEqual(cache.receipt(for: "a", now: now)?.grantedAt, now)
    }

    func testMetadataSurvivesSparseSnapshotsForTheSameGrant() throws {
        let cache = AccountResetReceiptCache(url: url)
        let receipt = try cache.update(accountID: "a", credits: [credit("known", grant: now,
            title: "Full reset", description: "Thanks for using Codex!")], now: now)
        let sparse = try cache.update(accountID: "a", credits: [credit("sparse", grant: now, title: " ", description: nil)], now: now)
        XCTAssertEqual(sparse, receipt)
        XCTAssertEqual(cache.receipt(for: "a", now: now)?.description, "Thanks for using Codex!")
    }

    func testTargetedOrCompensationGrantCannotReplaceKnownGeneralReceipt() throws {
        let cache = AccountResetReceiptCache(url: url)
        let receipt = try cache.update(accountID: "a", credits: [credit("general", grant: now.addingTimeInterval(-120))], now: now)
        let data = try Data(contentsOf: url)
        let targeted = [credit("compensation", grant: now, title: "Compensation reset"),
                        credit("selected", grant: now, description: "For affected accounts only")]
        XCTAssertEqual(try cache.update(accountID: "a", credits: targeted, now: now), receipt)
        XCTAssertEqual(try Data(contentsOf: url), data)
        XCTAssertNil(try cache.update(accountID: "b", credits: targeted, now: now))
    }

    func testCorruptUnsupportedAndInvalidIdentityFilesAreNeverOverwritten() throws {
        let invalid: [Data] = [Data("broken json".utf8),
            Data("{\"schemaVersion\":99,\"accounts\":{}}".utf8),
            Data("{\"schemaVersion\":1,\"accounts\":{\"raw-account\":{\"grantedAt\":800000000}}}".utf8)]
        let cache = AccountResetReceiptCache(url: url)
        for original in invalid {
            try original.write(to: url)
            XCTAssertNil(cache.receipt(for: "a", now: now))
            XCTAssertThrowsError(try cache.update(accountID: "a", credits: [credit("new", grant: now)], now: now))
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
    }

    func testUnreadablePathDoesNotClaimANewReceipt() throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        let cache = AccountResetReceiptCache(url: url)
        XCTAssertNil(cache.receipt(for: "a", now: now))
        XCTAssertThrowsError(try cache.update(accountID: "a", credits: [credit("new", grant: now)], now: now))
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }
}
