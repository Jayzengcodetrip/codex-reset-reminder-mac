import Foundation
import XCTest
@testable import CodexNotch

final class AccountCreditHistoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func tearDown() {
        CreditHistoryMockURLProtocol.handler = nil
        super.tearDown()
    }

    func testAllStatusesAndExactRedemptionTimesArePreservedSeparatelyFromAvailableUI() throws {
        var redeemed = entry("used", status: "redeemed")
        redeemed["redeem_started_at"] = "2026-07-01T12:34:50.123456Z"
        redeemed["redeemed_at"] = "2026-07-01T12:34:56.123456Z"
        let response = try decode(["available_count": 1, "history_enabled": true,
            "credits": [entry("available"), redeemed, entry("expired", status: "expired")]])
        XCTAssertEqual(response.availableCredits.map(\.id), ["available"])
        let history = try XCTUnwrap(response.accountHistory(fetchedAt: now))
        XCTAssertEqual(history.fetchedAt, now)
        XCTAssertTrue(history.historyEnabled)
        XCTAssertEqual(history.credits.map(\.status), ["available", "redeemed", "expired"])
        let used = try XCTUnwrap(history.credits.first(where: { $0.id == "used" }))
        XCTAssertEqual(try XCTUnwrap(used.redeemedAt).timeIntervalSince(try XCTUnwrap(used.redeemStartedAt)), 6,
                       accuracy: 0.000_001)
        XCTAssertEqual(used.resetType, "codex_rate_limits")
        XCTAssertNil(history.credits.first?.redeemedAt)
    }

    func testHistoryRequiresSuccessMetadataAndDoesNotTreatMissingAsEmpty() throws {
        for payload: [String: Any] in [[:], ["credits": []], ["history_enabled": true],
                                      ["history_enabled": NSNull(), "credits": []],
                                      ["history_enabled": "true", "credits": []]] {
            XCTAssertNil(try decode(payload).accountHistory(fetchedAt: now))
        }
        let empty = try XCTUnwrap(decode(["history_enabled": true, "credits": []]).accountHistory(fetchedAt: now))
        XCTAssertTrue(empty.historyEnabled)
        XCTAssertTrue(empty.credits.isEmpty)
        let disabled = try XCTUnwrap(decode(["history_enabled": false, "credits": [entry("a")]])
            .accountHistory(fetchedAt: now))
        XCTAssertFalse(disabled.historyEnabled)
    }

    func testMissingIdentityStatusOrRedemptionFieldsInvalidateEvidenceWithoutInventingIDs() throws {
        for missingKey in ["id", "status", "redeem_started_at", "redeemed_at"] {
            var incomplete = entry("incomplete")
            incomplete.removeValue(forKey: missingKey)
            let dto = try decode(["history_enabled": true, "credits": [entry("valid"), incomplete]])
            XCTAssertNil(dto.accountHistory(fetchedAt: now), missingKey)
        }
        for invalidID in ["", " \n "] {
            XCTAssertNil(try decode(["history_enabled": true, "credits": [entry(invalidID)]])
                .accountHistory(fetchedAt: now))
        }
        XCTAssertNil(try decode(["history_enabled": true, "credits": [entry("same"), entry("same")]])
            .accountHistory(fetchedAt: now))
    }

    func testMalformedDatesCannotBecomeNullRedemptionEvidence() throws {
        for key in ["redeem_started_at", "redeemed_at", "expires_at", "granted_at"] {
            for invalid: Any in ["not a date", true, ["unknown": "timestamp"]] {
                var row = entry("malformed")
                row[key] = invalid
                let dto = try decode(["history_enabled": true, "credits": [row]])
                XCTAssertNil(dto.accountHistory(fetchedAt: now), key)
            }
        }
    }

    func testNumericRedemptionDatesAndOptionalMetadataRemainReadable() throws {
        var row = entry("numeric", status: "redeemed")
        row["redeem_started_at"] = 1_780_000_000
        row["redeemed_at"] = 1_780_000_006_000 as Int64
        row.removeValue(forKey: "expires_at")
        row.removeValue(forKey: "granted_at")
        row.removeValue(forKey: "reset_type")
        let history = try XCTUnwrap(decode(["history_enabled": true, "credits": [row]])
            .accountHistory(fetchedAt: now))
        XCTAssertEqual(history.credits.first?.redeemedAt, Date(timeIntervalSince1970: 1_780_000_006))
        XCTAssertNil(history.credits.first?.resetType)
    }

    func testPlanAndEvidenceValidityArePreservedWithoutTrustingClampedPercentages() throws {
        for value in [0.0, 30, 100] {
            XCTAssertTrue(UsageWindow(id: "weekly", kind: .weekly, usedPercent: value).hasValidUsedPercent)
        }
        for value in [-1.0, 101, .infinity, -.infinity, .nan] {
            XCTAssertFalse(UsageWindow(id: "weekly", kind: .weekly, usedPercent: value).hasValidUsedPercent)
        }
        let invalid = UsageWindow(id: "weekly", kind: .weekly, usedPercent: -1)
        XCTAssertEqual(invalid.remainingPercent, 100) // Existing UI clamping remains compatible.
        XCTAssertFalse(invalid.hasValidUsedPercent)
        let snapshot = try JSONDecoder().decode(UsageResponseDTO.self, from: data(usage()))
            .snapshot(fetchedAt: now)
        XCTAssertEqual(snapshot.planType, "synthetic-plan")
        XCTAssertTrue(snapshot.weeklyWindow?.hasValidUsedPercent == true)
        let history = AccountCreditHistory(fetchedAt: now, historyEnabled: true, credits: [])
        let merged = snapshot.replacingResetCredits(availableCount: 0, credits: [], creditHistory: history)
        XCTAssertEqual(merged.planType, snapshot.planType)
        XCTAssertEqual(merged.fetchedAt, now)
        XCTAssertEqual(merged.creditHistory, history)
    }

    func testNestedUsageCreditDetailsNeverClaimIndependentHistoryCheck() throws {
        var payload = usage()
        payload["rate_limit_reset_credits"] = ["history_enabled": true, "credits": [entry("nested")]]
        let snapshot = try JSONDecoder().decode(UsageResponseDTO.self, from: data(payload)).snapshot(fetchedAt: now)
        XCTAssertNil(snapshot.creditHistory)
        XCTAssertEqual(snapshot.resetCredits.map(\.id), ["nested"])
    }

    func testRawWindowDurationSurvivesBroadWeeklyClassificationAndCreditMerge() throws {
        for seconds in [6 * 86_400, 7 * 86_400, 8 * 86_400] {
            let payload: [String: Any] = ["rate_limit": ["secondary_window":
                ["used_percent": 30, "limit_window_seconds": seconds]]]
            let snapshot = try JSONDecoder().decode(UsageResponseDTO.self, from: data(payload)).snapshot(fetchedAt: now)
            XCTAssertEqual(snapshot.weeklyWindow?.kind, .weekly)
            XCTAssertEqual(snapshot.weeklyWindow?.windowSeconds, seconds)
            XCTAssertEqual(snapshot.replacingResetCredits(availableCount: 0, credits: [])
                .weeklyWindow?.windowSeconds, seconds)
        }
        XCTAssertNil(UsageWindow(id: "legacy", kind: .weekly, usedPercent: 30).windowSeconds)
    }

    func testSuccessfulDedicatedRequestPublishesHistoryAndKeepsOnlyAvailableCards() async throws {
        let before = Date()
        let usageBody = data(usage())
        var redeemed = entry("used", status: "redeemed")
        redeemed["redeem_started_at"] = "2026-07-01T12:34:50Z"
        redeemed["redeemed_at"] = "2026-07-01T12:34:56Z"
        let creditsBody = data(["available_count": 1, "history_enabled": true,
                                "credits": [entry("available"), redeemed]])
        CreditHistoryMockURLProtocol.handler = { request in
            (200, request.url!.path.hasSuffix("/usage") ? usageBody : creditsBody)
        }
        let snapshot = try await client().fetch()
        let history = try XCTUnwrap(snapshot.creditHistory)
        XCTAssertGreaterThanOrEqual(history.fetchedAt, before)
        XCTAssertLessThanOrEqual(history.fetchedAt, Date())
        XCTAssertEqual(history.credits.count, 2)
        XCTAssertEqual(snapshot.resetCredits.map(\.id), ["available"])
        XCTAssertEqual(snapshot.planType, "synthetic-plan")
    }

    func testFailedOrMalformedAuxiliaryRequestCannotPretendNoRedemptionOccurred() async throws {
        let usageBody = data(usage())
        let unavailable = data(["history_enabled": true, "credits": [["id": "partial"]]])
        for response in [(503, Data()), (200, Data("not JSON".utf8)), (200, unavailable)] {
            CreditHistoryMockURLProtocol.handler = { request in
                request.url!.path.hasSuffix("/usage") ? (200, usageBody) : response
            }
            let snapshot = try await client().fetch()
            XCTAssertEqual(snapshot.weeklyWindow?.remainingPercent, 70)
            XCTAssertNil(snapshot.creditHistory)
            XCTAssertEqual(snapshot.planType, "synthetic-plan")
        }
    }

    private func client() -> CodexUsageClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CreditHistoryMockURLProtocol.self]
        return CodexUsageClient(credentials: CodexCredentials(accessToken: "synthetic-token", accountID: "synthetic-account"),
            session: URLSession(configuration: configuration),
            endpoint: URL(string: "https://example.test/backend-api/wham/usage")!)
    }

    private func entry(_ id: String, status: String = "available") -> [String: Any] {
        ["id": id, "status": status, "reset_type": "codex_rate_limits",
         "granted_at": "2026-07-01T01:00:00Z", "expires_at": "2026-07-31T01:00:00Z",
         "redeem_started_at": NSNull(), "redeemed_at": NSNull()]
    }
    private func usage() -> [String: Any] {
        ["plan_type": "synthetic-plan", "rate_limit": ["secondary_window":
            ["used_percent": 30, "limit_window_seconds": 604800, "reset_at": 1_800_604_800]]]
    }
    private func decode(_ object: [String: Any]) throws -> ResetCreditsDTO {
        try JSONDecoder().decode(ResetCreditsDTO.self, from: data(object))
    }
    private func data(_ object: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: object) }
}

private final class CreditHistoryMockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badURL) }
            let (status, body) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
