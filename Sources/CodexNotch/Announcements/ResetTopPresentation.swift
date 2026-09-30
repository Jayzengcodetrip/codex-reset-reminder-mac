import Foundation

/// A time-dependent projection for the small top card. Hiding an expired card
/// never changes the announcement ledger or claims that delivery happened.
struct ResetTopPresentation: Equatable {
    let announcements: [ResetAnnouncement]
    let didResetToday: Bool
    var secondsSinceLastDelivery: Int? = nil
    var undatedAnnouncements: [ResetAnnouncement] = []
    var archivedUndated: [String: ResetAnnouncement] = [:]
    var archivedForAccountReceipt: [String: AccountResetReceipt] = [:]
    var latestDeliveryOrigin: ResetDeliveryOrigin? = nil

    static func make(pending: [ResetAnnouncement], records: [ResetRecord], now: Date,
                     accountReceipt: AccountResetReceipt? = nil) -> Self {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ResetScheduleTiming.losAngeles
        let receipt = accountReceipt.flatMap {
            $0.grantedAt <= now && ResetDeliveryEvidence.isGeneralAccountReceipt($0) ? $0 : nil
        }
        let active = pending.filter { announcement in
            let status = normalizedStatus(announcement)
            return !deliveryStatuses.contains(status) && !["cancelled", "canceled"].contains(status)
        }
        let visible = active.filter { announcement in
            guard let target = ResetScheduleTiming.target(for: announcement) else { return false }
            if target.isDateBoundaryEstimate {
                return now < target.countdownDeadline
            }
            // A precise clock time can pass before delivery is confirmed. Keep
            // its waiting state until that Los Angeles calendar day has ended.
            guard let endOfDay = calendar.date(byAdding: .day, value: 1,
                                               to: calendar.startOfDay(for: target.displayedTime)) else {
                return false
            }
            return now < endOfDay
        }
        let deliveries = records.map(\.announcement).sorted {
            let lhs = ResetDeliveryEvidence.deliveryTimestamp($0) ?? .distantFuture
            let rhs = ResetDeliveryEvidence.deliveryTimestamp($1) ?? .distantFuture
            return lhs == rhs ? $0.id < $1.id : lhs < rhs
        }
        var undated: [ResetAnnouncement] = []
        var archived: [String: ResetAnnouncement] = [:]
        var archivedForAccount: [String: AccountResetReceipt] = [:]
        for announcement in active.filter({ ResetScheduleTiming.target(for: $0) == nil }).sorted(by: {
            let lhs = $0.announcedAt ?? .distantPast, rhs = $1.announcedAt ?? .distantPast
            return lhs == rhs ? $0.id < $1.id : lhs < rhs
        }) {
            if let delivery = deliveries.first(where: {
                ResetDeliveryEvidence.canArchiveUndated(announcement, after: $0, now: now)
            }) {
                archived[announcement.id] = delivery
            } else if let receipt,
                      ResetDeliveryEvidence.canArchiveUndated(announcement, for: receipt, now: now) {
                archivedForAccount[announcement.id] = receipt
            } else {
                undated.append(announcement)
            }
        }
        let latestPublicDelivery = records.compactMap { record -> Date? in
            let announcement = record.announcement
            guard ResetDeliveryEvidence.isGeneralDelivery(announcement) else { return nil }
            // A completion post can use its publication time. A preannouncement
            // with a scheduled target cannot use its original post time as delivery.
            let delivery = announcement.deliveryAt
                ?? (announcement.scheduledFor == nil ? announcement.announcedAt : nil)
            guard let delivery, delivery <= now else { return nil }
            return delivery
        }.max()
        // The same instant prefers the stronger personal receipt; a later
        // public delivery still moves the clock forward and identifies its origin.
        let useAccountReceipt = receipt.map { $0.grantedAt >= (latestPublicDelivery ?? .distantPast) } ?? false
        let latestDelivery = useAccountReceipt ? receipt?.grantedAt : latestPublicDelivery
        let origin: ResetDeliveryOrigin? = latestDelivery == nil ? nil
            : useAccountReceipt ? .accountReceipt : .publicAnnouncement
        return Self(announcements: visible,
                    didResetToday: latestDelivery.map { calendar.isDate($0, inSameDayAs: now) } ?? false,
                    secondsSinceLastDelivery: latestDelivery.map { max(0, Int(now.timeIntervalSince($0))) },
                    undatedAnnouncements: undated, archivedUndated: archived,
                    archivedForAccountReceipt: archivedForAccount, latestDeliveryOrigin: origin)
    }

    func emptyText(language: AppLanguage) -> String {
        if didResetToday {
            if latestDeliveryOrigin == .accountReceipt {
                return language.localized(chinese: "暂无最新重置预告（今天已收到重置券）",
                                          english: "No new reset announcements (reset credit received today)")
            }
            return language.localized(chinese: "暂无最新重置预告（今天已重置）",
                                      english: "No new reset announcements (reset delivered today)")
        }
        if let elapsed = secondsSinceLastDelivery {
            let time = Self.elapsedText(seconds: elapsed, language: language)
            if latestDeliveryOrigin == .accountReceipt {
                return language.localized(chinese: "暂无最新重置预告（距离上次收到重置券已过\(time)）",
                                          english: "No new reset announcements (last reset credit received \(time) ago)")
            }
            return language.localized(chinese: "暂无最新重置预告（距离上次重置已过\(time)）",
                                      english: "No new reset announcements (last reset \(time) ago)")
        }
        return language.localized(chinese: "暂无最新重置预告", english: "No new reset announcements")
    }

    static func elapsedText(seconds: Int, language: AppLanguage) -> String {
        let value = max(0, seconds)
        let days = value / 86_400
        let clock = String(format: "%02d:%02d:%02d", value % 86_400 / 3_600, value % 3_600 / 60, value % 60)
        guard days > 0 else { return clock }
        return language.localized(chinese: "\(days)天\(clock)", english: "\(days)d \(clock)")
    }

    private static let deliveryStatuses: Set<String> = ["completed", "confirmed", "propagated", "rolling_out"]

    private static func normalizedStatus(_ announcement: ResetAnnouncement) -> String {
        announcement.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }
}
