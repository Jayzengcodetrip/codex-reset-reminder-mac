import Foundation

/// A banked reset actually granted by the official account endpoint.
/// This local receipt is not evidence that a public/global rollout completed.
struct AccountResetReceipt: Codable, Equatable, Sendable {
    let grantedAt: Date
    var title: String? = nil
    var description: String? = nil
}

enum ResetDeliveryOrigin: Equatable, Sendable {
    case publicAnnouncement
    case accountReceipt
}
