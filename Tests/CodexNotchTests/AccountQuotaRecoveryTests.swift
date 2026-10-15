import Foundation
import XCTest
@testable import CodexNotch

final class AccountQuotaRecoveryTests: XCTestCase {
    private let base = ISO8601DateFormatter().date(from: "2026-07-07T12:00:00Z")!
    private let week: TimeInterval = 604800
    private let accountID = "synthetic-private-account"

    func testFirstZeroSnapshotAndPercentageDropsCannotManufactureRecovery() throws {
        try withCache { cache, _ in
            for (time, used) in [(0.0, 0.0), (60, 0), (120, 50), (180, 5), (240, 3)] {
                let state = try update(cache, sample(time, used))
                XCTAssertNil(state.latestConfirmed)
                XCTAssertNil(state.latestUnconfirmed)
            }
        }
    }

    func testZeroNeedsSeparateValidConfirmationAndDoesNotKeepResettingClock() throws {
        try withCache { cache, _ in
            _ = try update(cache, sample(0, 50))
            XCTAssertNil(try update(cache, sample(60, 0)).latestUnconfirmed)
            XCTAssertNil(try update(cache, sample(60, 0)).latestUnconfirmed)
            let confirmed = try XCTUnwrap(update(cache, sample(120, 2)).latestUnconfirmed)
            XCTAssertEqual(confirmed.detectedAt, date(60))
            XCTAssertEqual(confirmed.observedFrom, date(0))
            XCTAssertEqual(confirmed.confirmedAt, date(120))
            _ = try update(cache, sample(180, 0))
            _ = try update(cache, sample(240, 0))
            let repeated = cache.state(for: accountID, now: date(300))
            XCTAssertEqual(repeated.latestUnconfirmed?.detectedAt, date(180))
            _ = try update(cache, sample(300, 0))
            XCTAssertEqual(cache.state(for: accountID, now: date(301)).latestUnconfirmed?.detectedAt, date(180))
        }
    }

    func testReboundToOldUsageAndLargeReboundDoNotConfirm() throws {
        for (before, after) in [(1.0, 1.0), (4, 5), (50, 6)] {
            try withCache { cache, _ in
                _ = try update(cache, sample(0, before))
                _ = try update(cache, sample(60, 0))
                let state = try update(cache, sample(120, after))
                XCTAssertNil(state.latestConfirmed)
                XCTAssertNil(state.latestUnconfirmed)
            }
        }
    }

    func testManualRedemptionUsesExactEvidenceNotCreditCount() throws {
        try withCache { cache, url in
            let old = credit("synthetic-credit-secret", status: "available")
            let used = credit("synthetic-credit-secret", status: "redeemed", redeemed: 40)
            _ = try update(cache, sample(0, 50, credits: [old]))
            _ = try update(cache, sample(60, 0, credits: [used]))
            let result = try XCTUnwrap(update(cache, sample(120, 0, credits: [used])).latestConfirmed)
            XCTAssertEqual(result.kind, .manualCredit)
            XCTAssertEqual(result.redeemedAt, date(40))
            XCTAssertEqual(result.referenceTime, date(40))
            let saved = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(saved.contains(accountID))
            XCTAssertFalse(saved.contains("synthetic-credit-secret"))
        }
    }

    func testFirstZeroEvidenceSurvivesSecondHistoryFailure() throws {
        try withCache { cache, _ in
            _ = try update(cache, sample(0, 50))
            _ = try update(cache, sample(60, 0, credits: [credit("credit", status: "redeemed", redeemed: 40)]))
            let state = try update(cache, sample(120, 0, historyAvailable: false))
            XCTAssertEqual(state.latestConfirmed?.kind, .manualCredit)
        }
    }

    func testMissingOrDisabledCreditHistoryCannotExcludeManualReset() throws {
        for disabled in [false, true] {
            try withCache { cache, _ in
                _ = try update(cache, sample(0, 50))
                let publicReset = completion("public", -3600)
                _ = try update(cache, sample(60, 0, historyAvailable: disabled, historyEnabled: false), public: [publicReset])
                let state = try update(cache, sample(120, 0, historyAvailable: disabled, historyEnabled: false), public: [publicReset])
                XCTAssertEqual(state.latestUnconfirmed?.uncertainty, .creditHistoryUnavailable)
                XCTAssertNil(state.latestConfirmed)
            }
        }
    }

    func testPendingRedemptionWaitsThenUpgradesWithoutChangingDetection() throws {
        try withCache { cache, _ in
            _ = try update(cache, sample(0, 50))
            let pending = credit("credit", status: "redeeming", started: 30)
            _ = try update(cache, sample(60, 0, credits: [pending]))
            let unresolved = try update(cache, sample(120, 0, credits: [pending]))
            XCTAssertEqual(unresolved.latestUnconfirmed?.uncertainty, .redemptionInProgress)
            let used = credit("credit", status: "redeemed", started: 30, redeemed: 40)
            let later = try update(cache, sample(180, 0, credits: [used]))
            XCTAssertEqual(later.latestConfirmed?.kind, .manualCredit)
            XCTAssertEqual(later.latestConfirmed?.detectedAt, date(60))
            XCTAssertNil(later.latestUnconfirmed)
        }
    }

    func testMissingRedemptionTimesUnknownStatusesAndTypesStayUnconfirmed() throws {
        let uncertain = [credit("a", status: "redeemed"), credit("a", status: "redeeming"),
                         credit("a", status: "new_status"), credit("a", status: "available", type: nil)]
        for credit in uncertain {
            try withCache { cache, _ in
                _ = try update(cache, sample(0, 50))
                _ = try update(cache, sample(60, 0, credits: [credit]), public: [completion("p", -60)])
                let state = try update(cache, sample(120, 0, credits: [credit]), public: [completion("p", -60)])
                XCTAssertNil(state.latestConfirmed)
                XCTAssertNotNil(state.latestUnconfirmed)
            }
        }
    }

    func testCreditIdentityDisappearanceCannotBeHiddenByNewGrantOrSameCount() throws {
        try withCache { cache, _ in
            _ = try update(cache, sample(0, 50, credits: [credit("old", status: "available")]))
            _ = try update(cache, sample(60, 0, credits: [credit("new", status: "available")]), public: [completion("p", -60)])
            let state = try update(cache, sample(120, 0, credits: [credit("new", status: "available")]), public: [completion("p", -60)])
            XCTAssertEqual(state.latestUnconfirmed?.uncertainty, .missingCreditHistory)
            XCTAssertNil(state.latestConfirmed)
            let restored = try update(cache, sample(180, 0, credits: [credit("old", status: "available"), credit("new", status: "available")]), public: [completion("p", -60)])
            XCTAssertEqual(restored.latestConfirmed?.kind, .officialTemporary)
            XCTAssertEqual(restored.latestConfirmed?.detectedAt, date(60))
        }
    }

    func testWeeklyRequiresCrossedOldDeadlineAndNormalAdvance() throws {
        try withCache { cache, _ in
            _ = try update(cache, sample(0, 50, deadline: 60))
            _ = try update(cache, sample(120, 0, deadline: week + 60))
            let result = try update(cache, sample(180, 0, deadline: week + 60))
            XCTAssertEqual(result.latestConfirmed?.kind, .weekly)
            XCTAssertEqual(result.latestConfirmed?.referenceTime, date(120))
        }
        try withCache { cache, _ in
            _ = try update(cache, sample(0, 50, deadline: 60))
            _ = try update(cache, sample(120, 0, deadline: week + 3600))
            XCTAssertNil(try update(cache, sample(180, 0, deadline: week + 3600)).latestConfirmed)
        }
    }

    func testExpiredOldCreditCanDisappearAtOrdinaryWeeklyReset() throws {
        try withCache { cache, _ in
            _ = try update(cache, sample(0, 50, deadline: 60, credits: [credit("old", status: "available", expires: 30)]))
            _ = try update(cache, sample(120, 0, deadline: week + 60))
            XCTAssertEqual(try update(cache, sample(180, 0, deadline: week + 60)).latestConfirmed?.kind, .weekly)
        }
    }

    func testWeeklyAndRedemptionOrPublicOverlapAndLongAbsenceStayUnconfirmed() throws {
        for manual in [true, false] {
            try withCache { cache, _ in
                _ = try update(cache, sample(0, 50, deadline: 60))
                let credits = manual ? [credit("used", status: "redeemed", redeemed: 40)] : []
                let publicEvents = manual ? [] : [completion("p", 40)]
                _ = try update(cache, sample(120, 0, deadline: week + 60, credits: credits), public: publicEvents)
                let state = try update(cache, sample(180, 0, deadline: week + 60, credits: credits), public: publicEvents)
                XCTAssertEqual(state.latestUnconfirmed?.uncertainty, .overlappingCauses)
            }
        }
        try withCache { cache, _ in
            _ = try update(cache, sample(0, 50, deadline: week))
            _ = try update(cache, sample(week * 2 + 60, 0, deadline: week * 3))
            let state = try update(cache, sample(week * 2 + 120, 0, deadline: week * 3))
            XCTAssertEqual(state.latestUnconfirmed?.uncertainty, .longObservationGap)
            XCTAssertNil(state.latestConfirmed)
        }
    }

    func testUniqueEarlierPublicResetAllowsDelayedAccountObservation() throws {
        try withCache { cache, _ in
            let event = completion("public", -4 * 3600)
            _ = try update(cache, sample(0, 50))
            _ = try update(cache, sample(60, 0), public: [event])
            let result = try update(cache, sample(120, 0), public: [event])
            XCTAssertEqual(result.latestConfirmed?.kind, .officialTemporary)
            XCTAssertEqual(result.latestConfirmed?.publicCompletionID, "public")
            XCTAssertEqual(result.latestConfirmed?.referenceTime, date(60))
        }
    }

    func testMultipleOldFutureOrBankedPublicEventsCannotExplainRecovery() throws {
        let sets = [[completion("one", -60), completion("two", -120)], [completion("old", -90000)],
                    [completion("future", 1900)], [AccountQuotaPublicCompletion(id: "banked", deliveredAt: date(-60), kind: "banked")]]
        for events in sets {
            try withCache { cache, _ in
                _ = try update(cache, sample(0, 50))
                _ = try update(cache, sample(60, 0), public: events)
                let state = try update(cache, sample(120, 0), public: events)
                XCTAssertNil(state.latestConfirmed)
                XCTAssertNotNil(state.latestUnconfirmed)
            }
        }
    }

    func testLaterPublicEvidenceUpgradesWithoutAnotherUsageSample() throws {
        try withCache { cache, _ in
            _ = try update(cache, sample(0, 50))
            _ = try update(cache, sample(60, 0))
            _ = try update(cache, sample(120, 0))
            let state = try cache.reconcilePublicCompletions(accountID: accountID,
                publicCompletions: [completion("public", -60)], now: date(150))
            XCTAssertEqual(state.latestConfirmed?.kind, .officialTemporary)
            XCTAssertEqual(state.latestConfirmed?.detectedAt, date(60))
            XCTAssertNil(state.latestUnconfirmed)
        }
    }

    func testLaterRedemptionCorrectsBackgroundAssociationButSameIntervalIsAmbiguous() throws {
        for publicTime in [-3600.0, 30.0] {
            try withCache { cache, _ in
                _ = try update(cache, sample(0, 50))
                _ = try update(cache, sample(60, 0), public: [completion("public", publicTime)])
                XCTAssertEqual(try update(cache, sample(120, 0), public: [completion("public", publicTime)]).latestConfirmed?.kind, .officialTemporary)
                let corrected = try update(cache, sample(180, 0, credits: [credit("late", status: "redeemed", redeemed: 40)]))
                if publicTime < 0 {
                    XCTAssertEqual(corrected.latestConfirmed?.kind, .manualCredit)
                    XCTAssertEqual(corrected.latestConfirmed?.detectedAt, date(60))
                } else {
                    XCTAssertNil(corrected.latestConfirmed)
                    XCTAssertEqual(corrected.latestUnconfirmed?.uncertainty, .overlappingCauses)
                    XCTAssertEqual(corrected.latestUnconfirmed?.detectedAt, date(60))
                }
            }
        }
    }

    func testPublicEventCannotBeReusedAndEarlierConfirmedRecordSurvives() throws {
        try withCache { cache, _ in
            let event = completion("single", -60)
            _ = try update(cache, sample(0, 50))
            _ = try update(cache, sample(60, 0), public: [event])
            _ = try update(cache, sample(120, 0), public: [event])
            _ = try update(cache, sample(180, 20), public: [event])
            _ = try update(cache, sample(240, 0), public: [event])
            let state = try update(cache, sample(300, 0), public: [event])
            XCTAssertEqual(state.latestConfirmed?.detectedAt, date(60))
            XCTAssertEqual(state.latestUnconfirmed?.detectedAt, date(240))
            XCTAssertNil(state.latestUnconfirmed?.publicCompletionID)
        }
    }

    func testBaselineCandidateAndEvidenceSurviveRestartAndLaterFailures() throws {
        try withCache { cache, url in
            _ = try update(cache, sample(0, 50))
            let restarted = AccountQuotaRecoveryCache(url: url)
            _ = try update(restarted, sample(60, 0), public: [completion("p", -60)])
            let restartedAgain = AccountQuotaRecoveryCache(url: url)
            let confirmed = try update(restartedAgain, sample(120, 0), public: [completion("p", -60)])
            XCTAssertEqual(confirmed.latestConfirmed?.kind, .officialTemporary)
            let failedHistory = try update(restartedAgain, sample(180, 0, historyAvailable: false))
            XCTAssertEqual(failedHistory.latestConfirmed, confirmed.latestConfirmed)
            XCTAssertEqual(AccountQuotaRecoveryCache(url: url).state(for: accountID, now: date(181)), failedHistory)
        }
    }

    func testAccountsPlansWindowsInvalidValuesAndTimeRollbackBreakChain() throws {
        let transitions: [(UsageSnapshot, UsageSnapshot)] = [
            (sample(60, 0, plan: "plus"), sample(120, 0, plan: "plus")),
            (sample(60, 0, windowID: "other"), sample(120, 0, windowID: "other")),
            (sample(60, -1), sample(120, 0)),
            (sample(60, .nan), sample(120, 0)),
            (sample(60, 0, plan: nil), sample(120, 0)),
            (sample(-60, 0), sample(120, 0))
        ]
        for (first, second) in transitions {
            try withCache { cache, _ in
                _ = try update(cache, sample(0, 50))
                _ = try update(cache, first)
                let state = try update(cache, second)
                XCTAssertNil(state.latestConfirmed)
                XCTAssertNil(state.latestUnconfirmed)
            }
        }
        try withCache { cache, _ in
            _ = try update(cache, sample(0, 50))
            _ = try cache.update(accountID: "other-account", snapshot: sample(60, 0), now: date(61))
            XCTAssertNil(try cache.update(accountID: "other-account", snapshot: sample(120, 0), now: date(121)).latestUnconfirmed)
            XCTAssertEqual(cache.state(for: nil, now: date(180)), AccountQuotaRecoveryState())
        }
    }

    func testCorruptStateIsNotOverwrittenAndPrivatePermissionsAreSet() throws {
        try withCache { cache, url in
            _ = try update(cache, sample(0, 50))
            let mode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)
            XCTAssertEqual(mode.intValue & 0o777, 0o600)
            let bad = Data("broken".utf8)
            try bad.write(to: url)
            XCTAssertThrowsError(try update(cache, sample(60, 0)))
            XCTAssertEqual(try Data(contentsOf: url), bad)
            XCTAssertEqual(cache.state(for: accountID, now: date(120)), AccountQuotaRecoveryState())
        }
    }

    func testAnnouncementAfterAccountObservationHasBoundedDelayAndMustAlreadyExist() throws {
        try withCache { cache, _ in
            _ = try update(cache, sample(0, 50))
            _ = try update(cache, sample(60, 0))
            _ = try update(cache, sample(120, 0))
            let event = completion("delayed", 900)
            let tooEarly = try cache.reconcilePublicCompletions(accountID: accountID, publicCompletions: [event], now: date(500))
            XCTAssertNil(tooEarly.latestConfirmed)
            let inWindow = try cache.reconcilePublicCompletions(accountID: accountID, publicCompletions: [event], now: date(1000))
            XCTAssertEqual(inWindow.latestConfirmed?.kind, .officialTemporary)
            XCTAssertEqual(inWindow.latestConfirmed?.referenceTime, date(60))
        }
        try withCache { cache, _ in
            _ = try update(cache, sample(0, 50))
            _ = try update(cache, sample(60, 0))
            _ = try update(cache, sample(120, 0))
            let late = try cache.reconcilePublicCompletions(accountID: accountID, publicCompletions: [completion("late", 1861)], now: date(1900))
            XCTAssertNil(late.latestConfirmed)
        }
    }

    func testUnavailableBaselineHistoryPreventsExcludingManualReset() throws {
        try withCache { cache, _ in
            _ = try update(cache, sample(0, 50, historyAvailable: false))
            _ = try update(cache, sample(60, 0), public: [completion("p", -60)])
            let state = try update(cache, sample(120, 0), public: [completion("p", -60)])
            XCTAssertEqual(state.latestUnconfirmed?.uncertainty, .creditHistoryUnavailable)
            XCTAssertNil(state.latestConfirmed)
            let manual = try update(cache, sample(180, 0, credits: [credit("used", status: "redeemed", redeemed: 40)]))
            XCTAssertEqual(manual.latestConfirmed?.kind, .manualCredit)
        }
    }

    func testRawWindowDurationMissingOrChangedBreaksObservation() throws {
        for seconds in [nil, 518400] as [Int?] {
            try withCache { cache, _ in
                _ = try update(cache, sample(0, 50))
                _ = try update(cache, sample(60, 0, windowSeconds: seconds))
                let state = try update(cache, sample(120, 0, windowSeconds: seconds))
                XCTAssertNil(state.latestConfirmed)
                XCTAssertNil(state.latestUnconfirmed)
            }
        }
    }

    func testExplicitExpiredCreditEndsPendingRedemptionState() throws {
        try withCache { cache, _ in
            _ = try update(cache, sample(0, 50))
            _ = try update(cache, sample(60, 0, credits: [credit("credit", status: "redeeming", started: 30)]))
            _ = try update(cache, sample(120, 0, credits: [credit("credit", status: "redeeming", started: 30)]))
            let state = try update(cache, sample(180, 0, credits: [credit("credit", status: "expired", started: 30)]), public: [completion("p", -60)])
            XCTAssertEqual(state.latestConfirmed?.kind, .officialTemporary)
            XCTAssertNil(state.latestUnconfirmed)
        }
    }

    func testKnownRedemptionSurvivesOmissionButAnotherMissingCreditStaysAmbiguous() throws {
        try withCache { cache, _ in
            _ = try update(cache, sample(0, 50, credits: [credit("old", status: "available")]))
            _ = try update(cache, sample(60, 0, credits: [credit("old", status: "redeemed", redeemed: 40)]))
            let confirmed = try update(cache, sample(120, 0, credits: [credit("old", status: "redeemed", redeemed: 40)]))
            XCTAssertEqual(confirmed.latestConfirmed?.kind, .manualCredit)
            XCTAssertEqual(try update(cache, sample(180, 0)).latestConfirmed, confirmed.latestConfirmed)
        }
        try withCache { cache, _ in
            _ = try update(cache, sample(0, 50, credits: [credit("missing", status: "available")]))
            _ = try update(cache, sample(60, 0, credits: [credit("different", status: "redeemed", redeemed: 40)]))
            let ambiguous = try update(cache, sample(120, 0, credits: [credit("different", status: "redeemed", redeemed: 40)]))
            XCTAssertNil(ambiguous.latestConfirmed)
            XCTAssertEqual(ambiguous.latestUnconfirmed?.uncertainty, .overlappingCauses)
        }
    }

    func testInvalidPersistedBaselineAndUnknownSchemaArePreserved() throws {
        for invalidSchema in [false, true] {
            try withCache { cache, url in
                _ = try update(cache, sample(0, 50))
                var document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
                if invalidSchema {
                    document["schemaVersion"] = 999
                } else {
                    var accounts = document["accounts"] as! [String: [String: Any]]
                    let key = accounts.keys.first!
                    var account = accounts[key]!
                    var baseline = account["baseline"] as! [String: Any]
                    baseline["used"] = -10
                    account["baseline"] = baseline
                    accounts[key] = account
                    document["accounts"] = accounts
                }
                let invalid = try JSONSerialization.data(withJSONObject: document)
                try invalid.write(to: url)
                XCTAssertThrowsError(try update(cache, sample(60, 0)))
                XCTAssertEqual(try Data(contentsOf: url), invalid)
            }
        }
    }

    private func withCache(_ body: (AccountQuotaRecoveryCache, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("quota-recovery-test-" + UUID().uuidString)
        let url = directory.appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(AccountQuotaRecoveryCache(url: url), url)
    }
    private func date(_ seconds: TimeInterval) -> Date { base.addingTimeInterval(seconds) }
    private func completion(_ id: String, _ time: TimeInterval) -> AccountQuotaPublicCompletion {
        AccountQuotaPublicCompletion(id: id, deliveredAt: date(time))
    }
    private func credit(_ id: String, status: String, started: TimeInterval? = nil,
                        redeemed: TimeInterval? = nil, expires: TimeInterval? = 1000000,
                        type: String? = "codex_rate_limits") -> AccountCreditHistoryEntry {
        AccountCreditHistoryEntry(id: id, status: status, redeemStartedAt: started.map(date), redeemedAt: redeemed.map(date),
            expiresAt: expires.map(date), grantedAt: date(-3600), resetType: type)
    }
    private func sample(_ time: TimeInterval, _ used: Double, deadline: TimeInterval? = 604800,
                        credits: [AccountCreditHistoryEntry] = [], historyAvailable: Bool = true,
                        historyEnabled: Bool = true, plan: String? = "pro", windowID: String = "weekly",
                        windowSeconds: Int? = 604800) -> UsageSnapshot {
        UsageSnapshot(windows: [UsageWindow(id: windowID, kind: .weekly, usedPercent: used, resetAt: deadline.map(date), windowSeconds: windowSeconds)],
            fetchedAt: date(time), planType: plan,
            creditHistory: historyAvailable ? AccountCreditHistory(fetchedAt: date(time), historyEnabled: historyEnabled, credits: credits) : nil)
    }
    private func update(_ cache: AccountQuotaRecoveryCache, _ snapshot: UsageSnapshot,
                        public completions: [AccountQuotaPublicCompletion] = []) throws -> AccountQuotaRecoveryState {
        try cache.update(accountID: accountID, snapshot: snapshot, publicCompletions: completions,
                         now: max(snapshot.fetchedAt, base).addingTimeInterval(1))
    }
}
