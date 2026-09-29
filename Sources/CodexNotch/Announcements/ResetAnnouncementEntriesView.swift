import SwiftUI

/// Undated posts share one compact summary; only usable dates get a countdown card.
struct ResetAnnouncementEntriesView: View {
    let unreadCount: Int
    let awayUnreadCount: Int
    let statusText: String
    let announcements: [ResetAnnouncement]
    var undatedAnnouncements: [ResetAnnouncement] = []
    let now: Date
    let language: AppLanguage
    var didResetToday: Bool = false
    var secondsSinceLastDelivery: Int? = nil
    let action: () -> Void
    var undatedAction: () -> Void = {}

    static let summaryHeight: CGFloat = 120
    static let deliveryHeight: CGFloat = 34
    static let maximumHeight: CGFloat = 284

    // Retained for existing callers that only have timed countdowns.
    static func height(for count: Int) -> CGFloat {
        let visibleCount = min(2, max(1, count))
        let entryHeight = count == 0 ? ResetAnnouncementEntryView.emptyHeight : ResetAnnouncementEntryView.announcementHeight
        return CGFloat(visibleCount) * entryHeight + CGFloat(visibleCount - 1) * 8
    }

    static func height(for presentation: ResetTopPresentation) -> CGFloat {
        height(timedCount: presentation.announcements.count,
               hasUndated: !presentation.undatedAnnouncements.isEmpty,
               hasDelivery: presentation.secondsSinceLastDelivery != nil)
    }

    static func height(timedCount: Int, hasUndated: Bool, hasDelivery: Bool) -> CGFloat {
        guard timedCount > 0 || hasUndated else { return ResetAnnouncementEntryView.emptyHeight }
        let count = timedCount + (hasUndated ? 1 : 0)
        let cards = CGFloat(timedCount) * ResetAnnouncementEntryView.announcementHeight
            + (hasUndated ? summaryHeight : 0) + CGFloat(max(0, count - 1)) * 8
        return min(maximumHeight, cards + (hasDelivery ? deliveryHeight + 8 : 0))
    }

    private var hasActive: Bool { !announcements.isEmpty || !undatedAnnouncements.isEmpty }
    private var height: CGFloat {
        Self.height(timedCount: announcements.count, hasUndated: !undatedAnnouncements.isEmpty,
                    hasDelivery: secondsSinceLastDelivery != nil)
    }
    private var footerHeight: CGFloat { hasActive && secondsSinceLastDelivery != nil ? Self.deliveryHeight + 8 : 0 }
    private var contentHeight: CGFloat {
        guard hasActive else { return ResetAnnouncementEntryView.emptyHeight }
        let count = announcements.count + (undatedAnnouncements.isEmpty ? 0 : 1)
        return CGFloat(announcements.count) * ResetAnnouncementEntryView.announcementHeight
            + (undatedAnnouncements.isEmpty ? 0 : Self.summaryHeight) + CGFloat(max(0, count - 1)) * 8
    }

    var body: some View {
        VStack(spacing: footerHeight > 0 ? 8 : 0) {
            Group {
                if contentHeight > height - footerHeight {
                    ScrollView(.vertical) { cards }
                        .scrollIndicators(.visible)
                } else {
                    cards
                }
            }
            .frame(height: height - footerHeight)
            if hasActive, let seconds = secondsSinceLastDelivery {
                VStack(alignment: .leading, spacing: 2) {
                    Text(language.localized(chinese: "距上次重置已过 ", english: "Since last reset: ")
                         + ResetTopPresentation.elapsedText(seconds: seconds, language: language))
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.mint)
                    Text(language.localized(chinese: "按官方发放消息计时，不代表账户到账", english: "From the official rollout post; account receipt may vary"))
                        .font(.system(size: 9))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .frame(height: Self.deliveryHeight)
            }
        }
        .frame(height: height)
    }

    private var cards: some View {
        VStack(spacing: 8) {
            if !hasActive {
                ResetAnnouncementEntryView(unreadCount: unreadCount, awayUnreadCount: awayUnreadCount,
                    statusText: statusText, announcement: nil,
                    now: now, language: language, didResetToday: didResetToday,
                    secondsSinceLastDelivery: secondsSinceLastDelivery, action: action)
            } else {
                ForEach(Array(announcements.reversed()), id: \.id) { announcement in
                    ResetAnnouncementEntryView(
                        unreadCount: announcement.id == announcements.last?.id ? unreadCount : 0,
                        awayUnreadCount: announcement.id == announcements.last?.id ? awayUnreadCount : 0,
                        statusText: statusText, announcement: announcement,
                        now: now, language: language, didResetToday: didResetToday,
                        secondsSinceLastDelivery: secondsSinceLastDelivery, action: action)
                }
                if let latest = undatedAnnouncements.last {
                    undatedSummary(latest)
                }
            }
        }
    }

    private func undatedSummary(_ latest: ResetAnnouncement) -> some View {
        Button(action: undatedAction) {
            HStack(spacing: 10) {
                Image(systemName: awayUnreadCount > 0 || unreadCount > 0 ? "bell.badge" : "text.bubble")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.orange)
                    .frame(width: 25)
                VStack(alignment: .leading, spacing: 4) {
                    Text(ResetUndatedSummary.title(count: undatedAnnouncements.count, language: language))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(ResetUndatedSummary.excerpt(latest, language: language))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(ResetUndatedSummary.publication(latest, language: language))
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .lineLimit(1)
                    Text(ResetScheduleTiming.losAngelesNowText(now, language: language))
                        .font(.system(size: 10.5, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.85))
                    if unreadCount > 0 {
                        Text(awayUnreadCount > 0
                             ? language.localized(chinese: "离开期间有 \(awayUnreadCount) 条动态更新", english: "\(awayUnreadCount) updates while away")
                             : language.localized(chinese: "有 \(unreadCount) 条未读动态", english: "\(unreadCount) unread updates"))
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Color.orange)
                    }
                    Text(statusText)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            .padding(.horizontal, 12)
            .frame(height: Self.summaryHeight)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 11))
            .overlay { RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.12), lineWidth: 0.5) }
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .help(language.localized(chinese: "查看待定预告列表；打开不会清除未读", english: "View undated previews without clearing unread updates"))
    }
}

/// A stable-height entry keeps announcement updates from moving the quota card.
struct ResetAnnouncementEntryView: View {
    static let emptyHeight: CGFloat = 96
    static let announcementHeight: CGFloat = 138

    let unreadCount: Int
    let awayUnreadCount: Int
    let statusText: String
    let announcement: ResetAnnouncement?
    let now: Date
    let language: AppLanguage
    var didResetToday: Bool = false
    var secondsSinceLastDelivery: Int? = nil
    let action: () -> Void

    private var title: String {
        if announcement != nil {
            let heading = language.localized(chinese: "临时重置预告", english: "Temporary reset ahead")
            if awayUnreadCount > 0 {
                return heading + language.localized(chinese: " · 离开期间有更新", english: " · Updates while away")
            }
            return heading + (unreadCount > 0 ? language.localized(chinese: " · 有未读更新", english: " · Unread updates") : "")
        }
        return ResetTopPresentation(announcements: [], didResetToday: didResetToday, secondsSinceLastDelivery: secondsSinceLastDelivery).emptyText(language: language)
    }

    private var highlighted: Bool { announcement != nil }

    private var accessibilityText: String {
        guard let announcement else { return title + "，" + statusText }
        var lines = [title, ResetAnnouncementSummary.headline(for: announcement, now: now, language: language)]
        if ResetScheduleTiming.phase(for: announcement, now: now) != .afterDate {
            lines.append(ResetAnnouncementSummary.scheduleText(for: announcement, now: now, language: language))
            if let beijing = ResetScheduleTiming.beijingWeekdayText(for: announcement, now: now, language: language) {
                lines.append(beijing)
            }
            if let risk = ResetScheduleTiming.quotaRiskText(for: announcement, now: now, language: language) {
                lines.append(risk)
            }
        }
        lines.append(ResetScheduleTiming.losAngelesNowText(now, language: language))
        lines.append(statusText)
        return lines.joined(separator: "，")
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: announcement != nil ? "clock.fill" : (unreadCount > 0 ? "bell.badge.fill" : "bell"))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(highlighted ? Color.orange : Color.secondary)
                    .frame(width: 25)

                VStack(alignment: .leading, spacing: 3) {
                    if let announcement {
                        Text(title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.orange)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(ResetAnnouncementSummary.countdownText(for: announcement, now: now, language: language))
                            .font(.system(size: ResetScheduleTiming.phase(for: announcement, now: now) == .afterDate ? 13 : 18,
                                          weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.orange)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        if ResetScheduleTiming.phase(for: announcement, now: now) != .afterDate {
                            Text(ResetAnnouncementSummary.scheduleText(for: announcement, now: now, language: language))
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.9))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            if let beijingWeekday = ResetScheduleTiming.beijingWeekdayText(for: announcement, now: now, language: language) {
                                Text(beijingWeekday)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.8))
                                    .lineLimit(1)
                            }
                            if let risk = ResetScheduleTiming.quotaRiskText(for: announcement, now: now, language: language) {
                                Text(risk)
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(Color.orange.opacity(0.9))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                        Text(ResetScheduleTiming.losAngelesNowText(now, language: language))
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.white.opacity(0.9))
                            .lineLimit(1)
                    } else {
                        Text(title.replacingOccurrences(of: "（", with: "\n（"))
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(didResetToday ? Color.green : Color.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }
                    if announcement == nil && unreadCount > 0 {
                        Text(awayUnreadCount > 0
                            ? language.localized(chinese: "离开期间有 \(awayUnreadCount) 条更新 · 点击查看", english: "\(awayUnreadCount) updates while away · View history")
                            : language.localized(chinese: "\(unreadCount) 条未读动态 · 点击查看", english: "\(unreadCount) unread updates · View history"))
                            .font(.system(size: 9.5))
                            .foregroundStyle(Color.orange)
                            .lineLimit(1)
                    }
                    Text(statusText)
                        .font(.system(size: announcement == nil ? 10.5 : 9.5))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .lineLimit(announcement == nil ? 2 : 1)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity,
                   minHeight: announcement == nil ? Self.emptyHeight : Self.announcementHeight,
                   maxHeight: announcement == nil ? Self.emptyHeight : Self.announcementHeight)
            .background(highlighted ? Color.orange.opacity(0.12) : Color.white.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(highlighted ? Color.orange.opacity(0.35) : Color.white.opacity(0.1), lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .help(language.localized(chinese: "查看公告详情；查看额度不会清除未读", english: "View announcements; checking quota does not clear unread updates"))
        .accessibilityLabel(accessibilityText)
    }
}

