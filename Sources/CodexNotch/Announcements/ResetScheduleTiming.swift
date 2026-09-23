import Foundation

/// An interface timestamp can be a date boundary rather than an announced reset minute.
/// Keep the original timestamp in the ledger and interpret it only for presentation.
enum ResetScheduleTiming {
    struct Target: Equatable {
        let countdownDeadline: Date
        let displayedTime: Date
        let isDateBoundaryEstimate: Bool
    }

    enum Phase: Equatable {
        case beforeDate(Date)
        case duringDate(Date)
        case afterDate
        case beforeExact(Date)
        case afterExact

        var countdownDeadline: Date? {
            switch self {
            case .beforeDate(let deadline), .duringDate(let deadline), .beforeExact(let deadline):
                return deadline
            case .afterDate, .afterExact:
                return nil
            }
        }
    }

    static let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    static let beijing = TimeZone(identifier: "Asia/Shanghai")!

    static func target(for announcement: ResetAnnouncement) -> Target? {
        guard let scheduled = announcement.scheduledFor else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = losAngeles
        let parts = calendar.dateComponents([.hour, .minute], from: scheduled)
        let text = announcement.title + " " + announcement.summary
        let hasClock = text.range(
            of: #"(?i)\b\d{1,2}:[0-5]\d\b|\b\d{1,2}\s*(?:a\.?m\.?|p\.?m\.?)\b|\bmidnight\b|\bnoon\b|\d{1,2}\s*(?:点|时)"#,
            options: .regularExpression
        ) != nil

        // NextReset has used 23:59 and, in an earlier snapshot, next-day 00:00
        // to represent a post that only promised a weekday. Neither is a
        // minute-level promise. Treat the whole final minute as still pending.
        // A weekday in the post is direct evidence. If a later source revision
        // removes that excerpt, a preserved original X post link still lets us
        // treat NextReset's 23:59 marker as a date estimate.
        let hasOriginalPost = announcement.sourceURL.flatMap { url -> Bool? in
            guard let host = url.host?.lowercased(),
                  ["x.com", "www.x.com", "twitter.com", "www.twitter.com"].contains(host) else { return nil }
            let parts = url.path.split(separator: "/")
            return parts.count >= 3 && parts[parts.count - 2] == "status" && parts.last?.allSatisfy(\.isNumber) == true
        } == true
        if !hasClock && parts.hour == 23 && parts.minute == 59
            && (mentionsWeekday(of: scheduled, in: text, calendar: calendar) || hasOriginalPost) {
            let day = calendar.startOfDay(for: scheduled)
            if let nextDay = calendar.date(byAdding: .day, value: 1, to: day),
               let finalMinute = calendar.date(byAdding: .minute, value: -1, to: nextDay) {
                return Target(countdownDeadline: nextDay, displayedTime: finalMinute,
                              isDateBoundaryEstimate: true)
            }
        }
        if !hasClock && parts.hour == 0 && parts.minute == 0,
           mentionsWeekday(of: scheduled.addingTimeInterval(-60), in: text, calendar: calendar),
           let finalMinute = calendar.date(byAdding: .minute, value: -1, to: scheduled) {
            return Target(countdownDeadline: scheduled, displayedTime: finalMinute,
                          isDateBoundaryEstimate: true)
        }
        return Target(countdownDeadline: scheduled, displayedTime: scheduled,
                      isDateBoundaryEstimate: false)
    }

    static func phase(for announcement: ResetAnnouncement, now: Date) -> Phase? {
        guard let target = target(for: announcement) else { return nil }
        if target.isDateBoundaryEstimate {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = losAngeles
            let dayStart = calendar.startOfDay(for: target.displayedTime)
            if now < dayStart { return .beforeDate(dayStart) }
            if now < target.countdownDeadline { return .duringDate(target.countdownDeadline) }
            return .afterDate
        }
        return now < target.countdownDeadline
            ? .beforeExact(target.countdownDeadline) : .afterExact
    }

    static func losAngelesNowText(_ now: Date, language: AppLanguage) -> String {
        let clock = formattedTime(now, zone: losAngeles, format: "HH:mm:ss")
        let weekday = weekdayText(now, zone: losAngeles, language: language)
        return language.localized(chinese: "洛杉矶现在：\(weekday) \(clock)",
                                  english: "Los Angeles now: \(weekday) \(clock)")
    }

    static func losAngelesNotificationTimeText(_ now: Date, language: AppLanguage) -> String {
        let clock = formattedTime(now, zone: losAngeles, format: "HH:mm:ss")
        let weekday = weekdayText(now, zone: losAngeles, language: language)
        return language.localized(chinese: "通知时洛杉矶：\(weekday) \(clock)",
                                  english: "Los Angeles at notification: \(weekday) \(clock)")
    }

    static func targetText(for announcement: ResetAnnouncement, now: Date, language: AppLanguage) -> String {
        guard let target = target(for: announcement) else {
            return language.localized(chinese: "预计时间待公布", english: "Expected time not announced")
        }
        if target.isDateBoundaryEstimate {
            switch phase(for: announcement, now: now) {
            case .beforeDate(let dayStart):
                let weekday = weekdayText(dayStart, zone: losAngeles, language: language)
                return language.localized(
                    chinese: "最早可能窗口：洛杉矶\(weekday) 00:00（日期估算，非官方时刻）",
                    english: "Earliest possible window: Los Angeles \(weekday) 00:00 (calendar estimate)"
                )
            case .duringDate:
                let weekday = weekdayText(target.displayedTime, zone: losAngeles, language: language)
                return language.localized(
                    chinese: "预告日截止参考：洛杉矶\(weekday) 23:59（日期估算，非官方时刻）",
                    english: "Announced-day end: Los Angeles \(weekday) 23:59 (calendar estimate)"
                )
            case .afterDate:
                return language.localized(chinese: "预告日已过 · 等待确认", english: "Announced day passed · Awaiting confirmation")
            default:
                break
            }
        }
        let weekday = weekdayText(target.displayedTime, zone: losAngeles, language: language)
        let clock = formattedTime(target.displayedTime, zone: losAngeles, format: "HH:mm")
        return language.localized(chinese: "预计：洛杉矶\(weekday) \(clock)（接口时间）",
                                  english: "Expected: Los Angeles \(weekday) \(clock) (source time)")
    }

    static func quotaRiskText(for announcement: ResetAnnouncement, now: Date, language: AppLanguage) -> String? {
        guard let target = target(for: announcement), target.isDateBoundaryEstimate,
              let phase = phase(for: announcement, now: now),
              phase != .afterDate else { return nil }
        return language.localized(
            chinese: "不建议仅凭预告清空额度；实际重置可能延后。",
            english: "Do not exhaust quota based only on the post; reset may be delayed."
        )
    }

    static func beijingWeekdayText(for announcement: ResetAnnouncement, now: Date, language: AppLanguage) -> String? {
        guard let target = target(for: announcement) else { return nil }
        let cutoff: Date
        switch phase(for: announcement, now: now) {
        case .beforeDate(let dayStart): cutoff = dayStart
        case .duringDate(let dayEnd): cutoff = dayEnd
        case .afterDate: return nil
        default: cutoff = target.countdownDeadline
        }
        let weekday = weekdayText(cutoff, zone: beijing, language: language)
        return language.localized(chinese: "对应北京：\(weekday)",
                                  english: "Beijing weekday: \(weekday)")
    }

    static func dateBoundaryExplanation(for announcement: ResetAnnouncement, now: Date, language: AppLanguage) -> String {
        switch phase(for: announcement, now: now) {
        case .beforeDate:
            return language.localized(
                chinese: "洛杉矶预告日 00:00 只是最早可能窗口，不是官方承诺的重置时刻；若提前用尽额度，重置延后时就无法继续使用。",
                english: "The announced Los Angeles day at 00:00 is only the earliest possible window, not a promised reset minute. Exhausting quota early may leave you unable to use it if the reset is delayed."
            )
        default:
            return language.localized(
                chinese: "按洛杉矶预告日的最后一分钟估算；原帖未公布精确重置时刻，不建议仅凭预告清空额度。",
                english: "Estimated from the final minute of the announced Los Angeles day; the post gave no exact reset time, so do not exhaust quota based on it alone."
            )
        }
    }

    private static func weekdayText(_ date: Date, zone: TimeZone, language: AppLanguage) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let index = calendar.component(.weekday, from: date) - 1
        let names = language == .chinese
            ? ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return names[index]
    }

    private static func mentionsWeekday(of date: Date, in text: String, calendar: Calendar) -> Bool {
        let index = calendar.component(.weekday, from: date) - 1
        let english = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][index]
        let chinese = ["日", "一", "二", "三", "四", "五", "六"][index]
        return text.range(of: "\\b\(english)\\b", options: [.regularExpression, .caseInsensitive]) != nil
            || text.contains("周\(chinese)") || text.contains("星期\(chinese)")
    }

    private static func formattedTime(_ date: Date, zone: TimeZone, format: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
