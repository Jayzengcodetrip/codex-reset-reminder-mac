import XCTest
@testable import CodexNotch

final class ResetCreditGrantTests: XCTestCase {
    func testAccountGrantTimeSurvivesCreditDecodingAndUsageMerge() throws {
        let data = Data(#"{"available_count":1,"credits":[{"id":"synthetic-credit","title":"Full reset","status":"available","reset_type":"codex_rate_limits","is_supported_by_plan":true,"description":"Synthetic free reset","granted_at":"2026-07-01T12:34:56.123456Z","expires_at":"2026-07-31T12:34:56.123456Z"}]}"#.utf8)
        let dto = try JSONDecoder().decode(ResetCreditsDTO.self, from: data)
        let snapshot = UsageSnapshot(windows: []).replacingResetCredits(
            availableCount: dto.availableCount, credits: dto.availableCredits)
        let credit = try XCTUnwrap(snapshot.resetCredits.first)
        XCTAssertEqual(credit.resetType, "codex_rate_limits")
        XCTAssertEqual(credit.isSupportedByPlan, true)
        XCTAssertEqual(credit.creditDescription, "Synthetic free reset")
        XCTAssertEqual(try XCTUnwrap(credit.expiresAt).timeIntervalSince(try XCTUnwrap(credit.grantedAt)),
                       30 * 86_400, accuracy: 0.001)
        XCTAssertEqual(snapshot.resetCreditsAvailable, 1)
    }

    func testMissingOrMalformedGrantNeverUsesExpiryAsGrant() throws {
        for timestamp in [nil, "unknown"] as [String?] {
            var credit: [String: Any] = ["id": "synthetic-credit", "status": "available",
                                         "expires_at": "2026-07-31T12:34:56Z"]
            if let timestamp { credit["granted_at"] = timestamp }
            let data = try JSONSerialization.data(withJSONObject: ["available_count": 1, "credits": [credit]])
            let dto = try JSONDecoder().decode(ResetCreditsDTO.self, from: data)
            XCTAssertEqual(dto.availableCount, 1)
            XCTAssertNotNil(dto.availableCredits.first?.expiresAt)
            XCTAssertNil(dto.availableCredits.first?.grantedAt)
        }
    }

    func testGrantAlsoDecodesFromNestedUsageResponse() throws {
        let data = Data(#"{"rate_limit_reset_credits":{"available_count":1,"credits":[{"id":"synthetic-credit","status":"available","reset_type":"codex_rate_limits","granted_at":1790707586}]}}"#.utf8)
        let dto = try JSONDecoder().decode(UsageResponseDTO.self, from: data)
        XCTAssertEqual(dto.snapshot().resetCredits.first?.grantedAt, Date(timeIntervalSince1970: 1790707586))
    }
}
