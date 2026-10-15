import CryptoKit
import Foundation

enum AccountQuotaRecoveryCacheError: Error {
    case invalidSavedState
}

/// Cross-launch observation history. It never changes announcement records or
/// interprets a falling percentage/credit count as an official benefit.
final class AccountQuotaRecoveryCache {
    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexNotch", isDirectory: true)
            .appendingPathComponent("account-quota-recoveries.json")
    }

    private struct KnownCredit: Codable {
        let key: String
        let expiresAt: Date?
    }
    private struct Sample: Codable {
        let fetchedAt: Date
        let plan: String
        let windowID: String
        let windowSeconds: Int
        let used: Double
        let resetAt: Date?
        let creditHistoryKnown: Bool
        var credits: [KnownCredit]
    }
    private struct TrackedRecovery: Codable {
        var recovery: AccountQuotaRecovery
        let previousDeadline: Date?
        let nextDeadline: Date?
        let windowSeconds: Int
        let baselineCreditHistoryKnown: Bool
        let baselineCredits: [KnownCredit]
        var historyCheckedAt: Date?
        var missingCredits = false
        var pendingRedemptions: [String: Date] = [:]
        var completedRedemptions: [String: Date] = [:]
        var unknownRedemption = false
        var publicCandidates: [AccountQuotaPublicCompletion] = []
    }
    private struct Candidate: Codable {
        let previous: Sample
        let firstZero: Sample
        var evidence: TrackedRecovery
    }
    private struct Account: Codable {
        var baseline: Sample?
        var candidate: Candidate?
        var lastCredits: [KnownCredit] = []
        var lastCreditsAt: Date?
        var recoveries: [TrackedRecovery] = []
        var usedPublicCompletions: [String: Date] = [:]
    }
    private struct Document: Codable {
        var schemaVersion = 1
        var accounts: [String: Account] = [:]
    }

    private let url: URL
    private let lock = NSLock()
    private static let publicWindow: TimeInterval = 24 * 60 * 60
    private static let publicAnnouncementDelay: TimeInterval = 30 * 60
    /// A second sample can include a small amount of new use after a real zero.
    /// This threshold is never itself a detector; the first sample must be zero.
    private static let confirmationUseLimit: Double = 5

    init(url: URL = AccountQuotaRecoveryCache.defaultURL) { self.url = url }

    func state(for accountID: String?, now: Date = .now) -> AccountQuotaRecoveryState {
        guard let key = Self.accountKey(accountID) else { return .init() }
        lock.lock()
        defer { lock.unlock() }
        guard let account = try? readDocument().accounts[key] else { return .init() }
        return Self.presentation(account, now: now)
    }

    @discardableResult
    func update(accountID: String?, snapshot: UsageSnapshot,
                publicCompletions: [AccountQuotaPublicCompletion] = [],
                now: Date = .now) throws -> AccountQuotaRecoveryState {
        guard let key = Self.accountKey(accountID) else { return .init() }
        lock.lock()
        defer { lock.unlock() }
        var document = try readDocument()
        var account = document.accounts[key] ?? Account()
        // An invalid sample breaks the observation chain; prior recoveries survive.
        guard var sample = Self.sample(snapshot, now: now) else {
            account.baseline = nil
            account.candidate = nil
            Self.reconcile(&account, history: snapshot.creditHistory,
                           publicCompletions: publicCompletions, now: now)
            document.accounts[key] = account
            try writeDocument(document)
            return Self.presentation(account, now: now)
        }
        if let previous = account.baseline, sample.fetchedAt < previous.fetchedAt {
            // A time rollback establishes a new baseline and is never confirmation.
            account.candidate = nil
            Self.captureInventory(snapshot.creditHistory, account: &account, now: now)
            sample.credits = account.lastCredits
            account.baseline = sample
        } else if let previous = account.baseline, sample.fetchedAt == previous.fetchedAt {
            // Re-evaluating the same fetch can upgrade evidence, not count as a poll.
            if previous.plan != sample.plan || previous.windowID != sample.windowID
                || previous.windowSeconds != sample.windowSeconds || previous.used != sample.used
                || previous.resetAt != sample.resetAt {
                account.candidate = nil
                Self.captureInventory(snapshot.creditHistory, account: &account, now: now)
                sample.credits = account.lastCredits
                account.baseline = sample
            }
        } else {
            if let previous = account.baseline,
               previous.plan == sample.plan, previous.windowID == sample.windowID,
               previous.windowSeconds == sample.windowSeconds {
                if let candidate = account.candidate {
                    if candidate.firstZero.plan == sample.plan,
                       candidate.firstZero.windowID == sample.windowID,
                       candidate.firstZero.resetAt == sample.resetAt,
                       sample.used <= Self.confirmationUseLimit,
                       sample.used < candidate.previous.used {
                        let recovery = AccountQuotaRecovery(
                            observedFrom: candidate.previous.fetchedAt,
                            observedThrough: candidate.firstZero.fetchedAt,
                            detectedAt: candidate.firstZero.fetchedAt, confirmedAt: sample.fetchedAt,
                            kind: .unconfirmed, uncertainty: .insufficientEvidence)
                        var confirmed = candidate.evidence
                        confirmed.recovery = recovery
                        account.recoveries.append(confirmed)
                        account.recoveries = Array(account.recoveries.suffix(32))
                    }
                    account.candidate = nil
                } else if previous.used > 0, sample.used == 0 {
                    let provisional = AccountQuotaRecovery(observedFrom: previous.fetchedAt,
                        observedThrough: sample.fetchedAt, detectedAt: sample.fetchedAt, confirmedAt: sample.fetchedAt,
                        kind: .unconfirmed, uncertainty: .insufficientEvidence)
                    var evidence = TrackedRecovery(recovery: provisional, previousDeadline: previous.resetAt,
                        nextDeadline: sample.resetAt, windowSeconds: previous.windowSeconds,
                        baselineCreditHistoryKnown: previous.creditHistoryKnown, baselineCredits: previous.credits)
                    Self.applyHistory(snapshot.creditHistory, to: &evidence, now: now)
                    account.candidate = Candidate(previous: previous, firstZero: sample, evidence: evidence)
                }
            } else {
                account.candidate = nil
            }
            Self.captureInventory(snapshot.creditHistory, account: &account, now: now)
            sample.credits = account.lastCredits
            account.baseline = sample
        }
        Self.reconcile(&account, history: snapshot.creditHistory,
                       publicCompletions: publicCompletions, now: now)
        document.accounts[key] = account
        try writeDocument(document)
        return Self.presentation(account, now: now)
    }

    /// A newly fetched public completion can explain a saved recovery immediately,
    /// including while account polling fails. This never creates a usage sample.
    @discardableResult
    func reconcilePublicCompletions(accountID: String?, publicCompletions: [AccountQuotaPublicCompletion],
                                    now: Date = .now) throws -> AccountQuotaRecoveryState {
        guard let key = Self.accountKey(accountID) else { return .init() }
        lock.lock()
        defer { lock.unlock() }
        var document = try readDocument()
        guard var account = document.accounts[key] else { return .init() }
        Self.reconcile(&account, history: nil, publicCompletions: publicCompletions, now: now)
        document.accounts[key] = account
        try writeDocument(document)
        return Self.presentation(account, now: now)
    }

    private static func sample(_ snapshot: UsageSnapshot, now: Date) -> Sample? {
        let windows = snapshot.windows.filter { $0.kind == .weekly }
        guard windows.count == 1, let window = windows.first,
              window.hasValidUsedPercent, window.usedPercent.isFinite,
              (0...100).contains(window.usedPercent), !window.id.isEmpty,
              let seconds = window.windowSeconds, UsageWindowClassifier.kind(seconds: seconds) == .weekly,
              let plan = snapshot.planType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !plan.isEmpty, validPast(snapshot.fetchedAt, now: now),
              window.resetAt.map({ validDate($0) && $0 > snapshot.fetchedAt }) != false else { return nil }
        let historyKnown = snapshot.creditHistory.map {
            $0.historyEnabled && validPast($0.fetchedAt, now: now) && $0.fetchedAt >= snapshot.fetchedAt
        } ?? false
        return Sample(fetchedAt: snapshot.fetchedAt, plan: plan, windowID: window.id, windowSeconds: seconds,
                      used: window.usedPercent, resetAt: window.resetAt, creditHistoryKnown: historyKnown, credits: [])
    }

    private static func captureInventory(_ history: AccountCreditHistory?, account: inout Account, now: Date) {
        guard let history, history.historyEnabled, validPast(history.fetchedAt, now: now),
              history.fetchedAt >= (account.lastCreditsAt ?? .distantPast) else { return }
        account.lastCredits = history.credits.filter {
            [nil, "codex_rate_limits"].contains($0.resetType?.lowercased())
                && ["available", "redeeming", "pending", "in_progress"].contains($0.status.lowercased())
        }.map { KnownCredit(key: digest($0.id), expiresAt: $0.expiresAt) }
        account.lastCreditsAt = history.fetchedAt
    }

    private static func reconcile(_ account: inout Account, history: AccountCreditHistory?,
                                  publicCompletions: [AccountQuotaPublicCompletion], now: Date) {
        for index in account.recoveries.indices {
            var tracked = account.recoveries[index]
            let recovery = tracked.recovery
            applyHistory(history, to: &tracked, now: now)
            for completion in publicCompletions {
                guard !completion.id.isEmpty, completion.id.count <= 256,
                      ["regular", "automatic_global", "one_time"].contains(completion.kind.lowercased()),
                      validPast(completion.deliveredAt, now: now),
                      completion.deliveredAt <= recovery.detectedAt.addingTimeInterval(publicAnnouncementDelay),
                      recovery.detectedAt.timeIntervalSince(completion.deliveredAt) <= publicWindow,
                      account.usedPublicCompletions[completion.id].map({ $0 == recovery.detectedAt }) != false else { continue }
                if let existing = tracked.publicCandidates.firstIndex(where: { $0.id == completion.id }) {
                    tracked.publicCandidates[existing] = completion
                } else {
                    tracked.publicCandidates.append(completion)
                }
            }
            tracked.publicCandidates.removeAll {
                account.usedPublicCompletions[$0.id].map({ $0 != recovery.detectedAt }) == true
            }
            classify(&tracked)
            if tracked.recovery.kind == .officialTemporary, let id = tracked.recovery.publicCompletionID {
                account.usedPublicCompletions[id] = tracked.recovery.detectedAt
            }
            account.recoveries[index] = tracked
        }
    }

    private static func applyHistory(_ history: AccountCreditHistory?, to tracked: inout TrackedRecovery, now: Date) {
        let recovery = tracked.recovery
        if let history, history.historyEnabled, validPast(history.fetchedAt, now: now),
           history.fetchedAt >= recovery.observedThrough,
           history.fetchedAt >= (tracked.historyCheckedAt ?? .distantPast) {
            let ids = Set(history.credits.map { digest($0.id) })
            tracked.unknownRedemption = false
            for credit in history.credits {
                let key = digest(credit.id)
                let type = credit.resetType?.lowercased()
                let status = credit.status.lowercased()
                let possiblyRelevant = credit.expiresAt.map { $0 >= recovery.observedFrom } ?? true
                if possiblyRelevant && type != "codex_rate_limits" { tracked.unknownRedemption = true }
                if possiblyRelevant && !["available", "redeemed", "expired", "failed", "cancelled", "canceled",
                                         "redeeming", "pending", "in_progress"].contains(status) {
                    tracked.unknownRedemption = true
                }
                let redeemed = credit.redeemedAt.flatMap { validPast($0, now: now) ? $0 : nil }
                let started = credit.redeemStartedAt.flatMap { validPast($0, now: now) ? $0 : nil }
                if possiblyRelevant && ((status == "redeemed" && redeemed == nil)
                    || (["redeeming", "pending", "in_progress"].contains(status) && started == nil)) {
                    tracked.unknownRedemption = true
                }
                if let redeemed, inObservation(redeemed, recovery) {
                    if type == "codex_rate_limits", status == "redeemed" {
                        tracked.completedRedemptions[key] = redeemed
                        tracked.pendingRedemptions.removeValue(forKey: key)
                    } else {
                        tracked.unknownRedemption = true
                    }
                } else if let started, started <= recovery.observedThrough,
                          redeemed == nil, !["failed", "cancelled", "canceled", "expired"].contains(status) {
                    tracked.pendingRedemptions[key] = started
                } else if redeemed != nil || ["failed", "cancelled", "canceled", "expired"].contains(status) {
                    tracked.pendingRedemptions.removeValue(forKey: key)
                    // An explicit corrected timestamp can refute earlier attribution.
                    if redeemed != nil { tracked.completedRedemptions.removeValue(forKey: key) }
                }
            }
            // A once-confirmed redemption remains known when a later response
            // omits that consumed credit. Other missing unexpired credits do not.
            let explainedIDs = ids.union(tracked.completedRedemptions.keys)
            tracked.missingCredits = tracked.baselineCredits.contains {
                ($0.expiresAt == nil || $0.expiresAt! > recovery.observedThrough) && !explainedIDs.contains($0.key)
            }
            tracked.historyCheckedAt = history.fetchedAt
        }
    }

    private static func classify(_ tracked: inout TrackedRecovery) {
        let recovery = tracked.recovery
        let gap = recovery.observedThrough.timeIntervalSince(recovery.observedFrom)
        let crossesWeekly = tracked.previousDeadline.map {
            $0 >= recovery.observedFrom && $0 <= recovery.observedThrough
        } ?? false
        let normalWeekly = crossesWeekly && tracked.previousDeadline.flatMap { old in
            tracked.nextDeadline.map { abs($0.timeIntervalSince(old) - TimeInterval(tracked.windowSeconds)) <= 60 }
        } == true
        func undecided(_ reason: AccountQuotaRecoveryUncertainty) {
            tracked.recovery.kind = .unconfirmed
            tracked.recovery.uncertainty = reason
            tracked.recovery.redeemedAt = nil
            tracked.recovery.publicCompletionID = nil
        }
        if gap >= TimeInterval(tracked.windowSeconds) { undecided(.longObservationGap); return }
        let redeemed = Array(tracked.completedRedemptions.values)
        if !redeemed.isEmpty {
            let simultaneousPublicDelivery = tracked.publicCandidates.contains { $0.deliveredAt > recovery.observedFrom }
            guard redeemed.count == 1, !crossesWeekly, !simultaneousPublicDelivery,
                  tracked.pendingRedemptions.isEmpty, !tracked.unknownRedemption, !tracked.missingCredits else {
                undecided(.overlappingCauses); return
            }
            tracked.recovery.kind = .manualCredit
            tracked.recovery.redeemedAt = redeemed[0]
            tracked.recovery.publicCompletionID = nil
            tracked.recovery.uncertainty = nil
            return
        }
        if !tracked.pendingRedemptions.isEmpty { undecided(.redemptionInProgress); return }
        if tracked.unknownRedemption { undecided(.overlappingCauses); return }
        guard tracked.baselineCreditHistoryKnown, tracked.historyCheckedAt != nil else {
            undecided(.creditHistoryUnavailable); return
        }
        if tracked.missingCredits { undecided(.missingCreditHistory); return }
        if tracked.publicCandidates.count > 1 || (crossesWeekly && !tracked.publicCandidates.isEmpty) {
            undecided(.overlappingCauses); return
        }
        if normalWeekly {
            tracked.recovery.kind = .weekly
            tracked.recovery.uncertainty = nil
            tracked.recovery.publicCompletionID = nil
            tracked.recovery.redeemedAt = nil
        } else if !crossesWeekly, tracked.previousDeadline != nil, let completion = tracked.publicCandidates.first {
            tracked.recovery.kind = .officialTemporary
            tracked.recovery.publicCompletionID = completion.id
            tracked.recovery.uncertainty = nil
            tracked.recovery.redeemedAt = nil
        } else {
            undecided(.insufficientEvidence)
        }
    }

    private static func inObservation(_ date: Date, _ recovery: AccountQuotaRecovery) -> Bool {
        date > recovery.observedFrom && date <= recovery.observedThrough
    }
    private static func presentation(_ account: Account, now: Date) -> AccountQuotaRecoveryState {
        let records = account.recoveries.map(\.recovery).filter { validPast($0.confirmedAt, now: now) }
        return AccountQuotaRecoveryState(
            latestConfirmed: records.filter { $0.kind != .unconfirmed }.max { $0.detectedAt < $1.detectedAt },
            latestUnconfirmed: records.filter { $0.kind == .unconfirmed }.max { $0.detectedAt < $1.detectedAt })
    }
    private static func validDate(_ date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite && date.timeIntervalSince1970 > 0
    }
    private static func validPast(_ date: Date, now: Date) -> Bool { validDate(date) && date <= now }
    private static func accountKey(_ id: String?) -> String? {
        guard let id = id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else { return nil }
        return digest(id)
    }
    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private static func validHash(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { "0123456789abcdef".contains($0) }
    }
    private static func validSample(_ sample: Sample) -> Bool {
        validDate(sample.fetchedAt) && !sample.plan.isEmpty && !sample.windowID.isEmpty
            && UsageWindowClassifier.kind(seconds: sample.windowSeconds) == .weekly
            && sample.used.isFinite && (0...100).contains(sample.used)
            && sample.resetAt.map({ validDate($0) && $0 > sample.fetchedAt }) != false
            && sample.credits.allSatisfy { validHash($0.key) && $0.expiresAt.map(validDate) != false }
    }

    private func readDocument() throws -> Document {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return Document() }
        guard data.count <= 2_000_000, let document = try? JSONDecoder().decode(Document.self, from: data),
              document.schemaVersion == 1,
              document.accounts.allSatisfy({ key, account in
                  Self.validHash(key)
                      && account.baseline.map(Self.validSample) != false
                      && account.candidate.map { candidate in
                          Self.validSample(candidate.previous) && Self.validSample(candidate.firstZero)
                              && candidate.firstZero.used == 0 && candidate.previous.used > 0
                              && candidate.firstZero.fetchedAt > candidate.previous.fetchedAt
                              && candidate.firstZero.plan == candidate.previous.plan
                              && candidate.firstZero.windowID == candidate.previous.windowID
                              && candidate.firstZero.windowSeconds == candidate.previous.windowSeconds
                      } != false
                      && account.recoveries.allSatisfy { value in
                          Self.validDate(value.recovery.observedFrom)
                              && Self.validDate(value.recovery.observedThrough)
                              && Self.validDate(value.recovery.confirmedAt)
                              && value.recovery.observedThrough > value.recovery.observedFrom
                              && value.recovery.detectedAt == value.recovery.observedThrough
                              && value.recovery.confirmedAt > value.recovery.detectedAt
                      }
              }) else { throw AccountQuotaRecoveryCacheError.invalidSavedState }
        return document
    }
    private func writeDocument(_ document: Document) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= 2_000_000 else { throw AccountQuotaRecoveryCacheError.invalidSavedState }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
