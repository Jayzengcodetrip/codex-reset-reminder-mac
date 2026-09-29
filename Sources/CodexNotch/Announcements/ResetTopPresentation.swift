import Foundation

/// A time-dependent projection for the small top card. Hiding an expired card
/// never changes the announcement ledger or claims that delivery happened.
struct ResetTopPresentation: Equatable {
    let announcements: [ResetAnnouncement]
    let didResetToday: Bool
    var secondsSinceLastDelivery: Int? = nil
    var undatedAnnouncements: [ResetAnnouncement] = []
    var archivedUndated: [String: ResetAnnouncement] = [:]

    static func make(pending: [ResetAnnouncement], records: [ResetRecord], now: Date) -> Self {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ResetScheduleTiming.losAngeles
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
        for announcement in active.filter({ ResetScheduleTiming.target(for: $0) == nil }).sorted(by: {
            let lhs = $0.announcedAt ?? .distantPast, rhs = $1.announcedAt ?? .distantPast
            return lhs == rhs ? $0.id < $1.id : lhs < rhs
        }) {
            if let delivery = deliveries.first(where: {
                ResetDeliveryEvidence.canArchiveUndated(announcement, after: $0, now: now)
            }) {
                archived[announcement.id] = delivery
            } else {
                undated.append(announcement)
            }
        }
        let latestDelivery = records.compactMap { record -> Date? in
            let announcement = record.announcement
            guard ResetDeliveryEvidence.isGeneralDelivery(announcement) else { return nil }
            // A completion post can use its publication time. A preannouncement
            // with a scheduled target cannot use its original post time as delivery.
            let delivery = announcement.deliveryAt
                ?? (announcement.scheduledFor == nil ? announcement.announcedAt : nil)
            guard let delivery, delivery <= now else { return nil }
            return delivery
        }.max()
        return Self(announcements: visible,
                    didResetToday: latestDelivery.map { calendar.isDate($0, inSameDayAs: now) } ?? false,
                    secondsSinceLastDelivery: latestDelivery.map { max(0, Int(now.timeIntervalSince($0))) },
                    undatedAnnouncements: undated, archivedUndated: archived)
    }

    func emptyText(language: AppLanguage) -> String {
        if didResetToday {
            return language.localized(chinese: "暂无最新重置预告（今天已重置）",
                                      english: "No new reset announcements (reset delivered today)")
        }
        if let elapsed = secondsSinceLastDelivery {
            let time = Self.elapsedText(seconds: elapsed, language: language)
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
