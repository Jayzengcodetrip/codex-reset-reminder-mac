import Foundation

/// Quote relative wording in its original publication context, never as a new deadline.
enum ResetUndatedSummary {
    static func title(count: Int, language: AppLanguage) -> String {
        language.localized(chinese: "有 \(count) 条待定预告 · 具体时间未公布",
                           english: "\(count) undated previews · Time not announced")
    }

    static func excerpt(_ announcement: ResetAnnouncement, language: AppLanguage) -> String {
        let summary = announcement.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let original = originalExcerpt(summary)
        var text = original ?? (summary.isEmpty ? announcement.title : summary)
        text = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        let quote = text.count > 180 ? String(text.prefix(180)) + "…" : text
        if original != nil {
            return language.localized(chinese: "原帖称：“\(quote)”", english: "Original post: “\(quote)”")
        }
        return language.localized(chinese: "公告摘要：\(quote)", english: "Announcement summary: \(quote)")
    }

    static func publication(_ announcement: ResetAnnouncement, language: AppLanguage) -> String {
        guard let date = announcement.announcedAt else {
            return language.localized(chinese: "原帖发布时间未提供", english: "Original publication time unavailable")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = ResetScheduleTiming.beijing
        formatter.dateFormat = "MM-dd HH:mm"
        return language.localized(chinese: "原帖发布：\(formatter.string(from: date))（北京）",
                                  english: "Originally posted: \(formatter.string(from: date)) (Beijing)")
    }

    private static func originalExcerpt(_ summary: String) -> String? {
        guard let start = summary.range(of: "原帖摘录：“"),
              let end = summary.range(of: "”", range: start.upperBound..<summary.endIndex) else { return nil }
        return String(summary[start.upperBound..<end.lowerBound])
    }
}
