import Foundation

/// A validated, broad direct-reset announcement supplied by the public monitor.
/// Banked-credit grants alone are not evidence that account quota recovered.
struct AccountQuotaPublicCompletion: Codable, Equatable, Sendable {
    let id: String
    let deliveredAt: Date
    var kind: String = "regular"
}

enum AccountQuotaRecoveryKind: String, Codable, Equatable, Sendable {
    case manualCredit
    case weekly
    case officialTemporary
    case unconfirmed
}

enum AccountQuotaRecoveryUncertainty: String, Codable, Equatable, Sendable {
    case insufficientEvidence
    case creditHistoryUnavailable
    case missingCreditHistory
    case redemptionInProgress
    case overlappingCauses
    case longObservationGap
}

/// This records an observed recovery, not an inferred exact server execution time.
/// `detectedAt` never changes when later evidence corrects the explanation.
struct AccountQuotaRecovery: Codable, Equatable, Sendable {
    let observedFrom: Date
    let observedThrough: Date
    let detectedAt: Date
    let confirmedAt: Date
    var kind: AccountQuotaRecoveryKind
    var uncertainty: AccountQuotaRecoveryUncertainty?
    var redeemedAt: Date?
    var publicCompletionID: String?

    /// Redemption provides an exact action timestamp. Other explanations only
    /// locate the recovery within the observation interval, so use first detection.
    var referenceTime: Date {
        kind == .manualCredit ? (redeemedAt ?? detectedAt) : detectedAt
    }
}

/// A newer unexplained recovery must not erase an earlier confirmed explanation.
struct AccountQuotaRecoveryState: Equatable, Sendable {
    var latestConfirmed: AccountQuotaRecovery? = nil
    var latestUnconfirmed: AccountQuotaRecovery? = nil
}
