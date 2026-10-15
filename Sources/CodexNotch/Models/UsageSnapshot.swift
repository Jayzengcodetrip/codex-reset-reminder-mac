import Foundation

enum UsageWindowKind: Equatable, Sendable {
    case rolling(hours: Int)
    case daily
    case weekly
    case custom(seconds: Int)
}

struct UsageWindow: Equatable, Identifiable, Sendable {
    let id: String
    let kind: UsageWindowKind
    let usedPercent: Double
    let resetAt: Date?
    /// Preserve the API duration: different 6–8 day windows share the weekly UI label.
    let windowSeconds: Int?
    /// Evidence must inspect the original value, not the UI's clamped percentage.
    let hasValidUsedPercent: Bool

    init(id: String, kind: UsageWindowKind, usedPercent: Double, resetAt: Date? = nil,
         windowSeconds: Int? = nil) {
        self.id = id
        self.kind = kind
        self.usedPercent = UsageWindowClassifier.clampPercent(usedPercent)
        self.resetAt = resetAt
        self.windowSeconds = windowSeconds
        self.hasValidUsedPercent = usedPercent.isFinite && (0...100).contains(usedPercent)
    }

    var remainingPercent: Double {
        max(0, 100 - usedPercent)
    }
}

struct ResetCredit: Equatable, Identifiable, Sendable {
    let id: String
    let title: String?
    let expiresAt: Date?
    let grantedAt: Date?
    let resetType: String?
    let creditDescription: String?
    let isSupportedByPlan: Bool?

    init(id: String, title: String? = nil, expiresAt: Date? = nil,
         grantedAt: Date? = nil, resetType: String? = nil,
         creditDescription: String? = nil, isSupportedByPlan: Bool? = nil) {
        self.id = id
        self.title = title
        self.expiresAt = expiresAt
        self.grantedAt = grantedAt
        self.resetType = resetType
        self.creditDescription = creditDescription
        self.isSupportedByPlan = isSupportedByPlan
    }
}

/// Complete credit detail from one successful dedicated account request.
/// Missing or malformed history is represented by nil on UsageSnapshot, never an empty success.
struct AccountCreditHistory: Codable, Equatable, Sendable {
    let fetchedAt: Date
    let historyEnabled: Bool
    let credits: [AccountCreditHistoryEntry]
}

struct AccountCreditHistoryEntry: Codable, Equatable, Sendable {
    let id: String
    let status: String
    let redeemStartedAt: Date?
    let redeemedAt: Date?
    let expiresAt: Date?
    let grantedAt: Date?
    let resetType: String?
}

struct UsageSnapshot: Equatable, Sendable {
    let windows: [UsageWindow]
    let resetCreditsAvailable: Int?
    let resetCredits: [ResetCredit]
    let fetchedAt: Date
    let planType: String?
    let creditHistory: AccountCreditHistory?

    init(
        windows: [UsageWindow],
        resetCreditsAvailable: Int? = nil,
        resetCredits: [ResetCredit] = [],
        fetchedAt: Date = .now,
        planType: String? = nil,
        creditHistory: AccountCreditHistory? = nil
    ) {
        self.windows = windows
        self.resetCreditsAvailable = resetCreditsAvailable
        self.resetCredits = resetCredits.sorted { lhs, rhs in
            switch (lhs.expiresAt, rhs.expiresAt) {
            case let (lhsDate?, rhsDate?):
                return lhsDate < rhsDate
            case (.some, .none):
                return true
            default:
                return false
            }
        }
        self.fetchedAt = fetchedAt
        self.planType = planType
        self.creditHistory = creditHistory
    }

    var weeklyWindow: UsageWindow? {
        windows.first { window in
            if case .weekly = window.kind { return true }
            return false
        }
    }

    var fiveHourWindow: UsageWindow? {
        windows.first { window in
            if case .rolling(hours: 5) = window.kind { return true }
            return false
        }
    }

    func replacingResetCredits(
        availableCount: Int?,
        credits: [ResetCredit],
        creditHistory: AccountCreditHistory? = nil
    ) -> UsageSnapshot {
        UsageSnapshot(
            windows: windows,
            resetCreditsAvailable: availableCount
                ?? (credits.isEmpty ? resetCreditsAvailable : credits.count),
            resetCredits: credits.isEmpty ? resetCredits : credits,
            fetchedAt: fetchedAt,
            planType: planType,
            creditHistory: creditHistory
        )
    }
}

enum WeeklyQuotaLevel: Equatable, Sendable {
    case healthy
    case warning
    case critical
    case unavailable

    init(weeklyWindow: UsageWindow?) {
        guard let weeklyWindow else {
            self = .unavailable
            return
        }
        self.init(remainingPercent: weeklyWindow.remainingPercent)
    }

    init(remainingPercent: Double) {
        guard remainingPercent.isFinite else {
            self = .critical
            return
        }
        if remainingPercent <= 10 {
            self = .critical
        } else if remainingPercent <= 20 {
            self = .warning
        } else {
            self = .healthy
        }
    }
}
