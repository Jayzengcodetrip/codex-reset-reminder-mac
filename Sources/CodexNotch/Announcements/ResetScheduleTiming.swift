import Foundation

/// An interface timestamp can be a date boundary rather than an announced reset minute.
/// Keep the original timestamp in the ledger and interpret it only for presentation.
enum ResetScheduleTiming {
    struct Target: Equatable {
        let countdownDeadline: Date
        let displayedTime: Date
        let isDateBoundaryEstimate: Bool
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
        if !hasClock && parts.hour == 23 && parts.minute == 59,
           mentionsWeekday(of: scheduled, in: text, calendar: calendar) {
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

    static func losAngelesNowText(_ now: Date, language: AppLanguage) -> String {
        let clock = formattedTime(now, zone: losAngeles, format: "HH:mm:ss")
        let weekday = weekdayText(now, zone: losAngeles, language: language)
        return language.localized(chinese: "洛杉矶现在：\(weekday) \(clock)",
                                  english: "Los Angeles now: \(weekday) \(clock)")
    }

    static func targetText(for announcement: ResetAnnouncement, language: AppLanguage) -> String {
        guard let target = target(for: announcement) else {
            return language.localized(chinese: "预计时间待公布", english: "Expected time not announced")
        }
        let weekday = weekdayText(target.displayedTime, zone: losAngeles, language: language)
        let clock = formattedTime(target.displayedTime, zone: losAngeles, format: "HH:mm")
        if target.isDateBoundaryEstimate {
            return language.localized(
                chinese: "预计：洛杉矶\(weekday) \(clock)（日期边界估算，非官方精确时刻）",
                english: "Estimate: Los Angeles \(weekday) \(clock) (day boundary, not an official minute)"
            )
        }
        return language.localized(chinese: "预计：洛杉矶\(weekday) \(clock)（接口时间）",
                                  english: "Expected: Los Angeles \(weekday) \(clock) (source time)")
    }

    static func beijingWeekdayText(for announcement: ResetAnnouncement, language: AppLanguage) -> String? {
        guard let target = target(for: announcement) else { return nil }
        let weekday = weekdayText(target.countdownDeadline, zone: beijing, language: language)
        return language.localized(chinese: "对应北京：\(weekday)",
                                  english: "Beijing weekday: \(weekday)")
    }

    static func dateBoundaryExplanation(language: AppLanguage) -> String {
        language.localized(
            chinese: "按洛杉矶预告日的最后一分钟估算；原帖未公布精确重置时刻。",
            english: "Estimated from the last minute of the Los Angeles announcement day; the post gave no exact reset time."
        )
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
