import Foundation

/// Optional public evidence. A missing/malformed auxiliary feed cannot invalidate the main feed.
enum ResetDeliveryEvidence {
    static func announcements(eventsData: Data?, historyData: Data?) -> [ResetAnnouncement] {
        let textPosts = historyData.map(parseHistory) ?? []
        let linkedPosts = eventsData.map(parseEvents) ?? []
        return merge(base: textPosts, supplements: linkedPosts)
    }

    /// General benefit delivery can drive the top-level "reset today" label.
    /// Targeted compensation remains in history without claiming all users received it.
    static func isGeneralDelivery(_ announcement: ResetAnnouncement) -> Bool {
        ["completed", "confirmed", "propagated", "rolling_out"].contains(normalized(announcement.status))
            && !targetedScopes.contains(normalized(announcement.scope))
            && !isSeparateBenefit(announcement.title + " " + announcement.summary)
    }

    static func hasOriginalDeliveryText(_ announcement: ResetAnnouncement) -> Bool {
        deliveryKind(in: announcement.summary) != nil
    }

    /// An unlinked delivery can close only a unique compatible announcement on its LA target day.
    /// This is an explicit local inference, never a relationship claimed by the source.
    static func associate(_ announcements: [ResetAnnouncement], pending: [ResetAnnouncement]) -> [ResetAnnouncement] {
        announcements.map { original in
            guard let delivered = original.deliveryAt,
                  original.relatedAnnouncementIDs?.isEmpty != false,
                  let source = officialPost(original.sourceURL),
                  isGeneralDelivery(original) else { return original }
            let candidates = pending.filter { candidate in
                guard !terminalStatuses.contains(normalized(candidate.status)),
                      !targetedScopes.contains(normalized(candidate.scope)),
                      !isSeparateBenefit(candidate.title + " " + candidate.summary),
                      let post = officialPost(candidate.sourceURL), post.author == source.author,
                      post.id != source.id,
                      let announced = candidate.announcedAt, announced <= delivered,
                      let target = ResetScheduleTiming.target(for: candidate) else { return false }
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = ResetScheduleTiming.losAngeles
                let start = calendar.startOfDay(for: target.displayedTime)
                guard let end = calendar.date(byAdding: .day, value: 1, to: start),
                      delivered >= start, delivered < end else { return false }
                let restriction = promisedKind(candidate.title + " " + candidate.summary)
                return restriction == nil || original.deliveryKind == "both"
                    || restriction == original.deliveryKind
            }
            // Multiple aliases of the same source post do not introduce false ambiguity.
            let groups = Dictionary(grouping: candidates) { officialPost($0.sourceURL)!.id }
            guard groups.count == 1, let group = groups.first else { return original }
            var result = original
            result.relatedAnnouncementIDs = Array(Set(group.value.map(\.id) + [group.key])).sorted()
            result.completionEvidence = "同一洛杉矶目标日，仅有一条发放方式相符的官方预告；根据后续官方发放原文匹配。"
            return result
        }
    }

    /// Supplements enrich an existing source post without discarding its title/deadline.
    /// An empty optional response must not erase previously known delivery evidence.
    static func merge(base: [ResetAnnouncement], supplements: [ResetAnnouncement]) -> [ResetAnnouncement] {
        var result = base
        for incoming in supplements {
            guard let index = result.firstIndex(where: {
                $0.id == incoming.id || ResetPendingAnnouncements.sameIdentity($0, incoming)
            }) else { result.append(incoming); continue }
            var current = result[index]
            if let delivered = incoming.deliveryAt {
                current.deliveryAt = delivered
                current.deliveryKind = incoming.deliveryKind ?? current.deliveryKind
                current.status = incoming.status
                if targetedScopes.contains(normalized(incoming.scope)) { current.scope = incoming.scope }
                if let evidence = incoming.completionEvidence,
                   incoming.relatedAnnouncementIDs?.isEmpty == false || current.completionEvidence == nil {
                    current.completionEvidence = evidence
                }
            }
            if let relations = incoming.relatedAnnouncementIDs, !relations.isEmpty {
                current.relatedAnnouncementIDs = Array(Set((current.relatedAnnouncementIDs ?? []) + relations)).sorted()
            }
            // The history feed supplies the original text; event summaries are short editorial labels.
            if deliveryKind(in: incoming.summary) != nil || current.summary.isEmpty {
                current.summary = incoming.summary
            }
            current.sourceURL = current.sourceURL ?? incoming.sourceURL
            current.announcedAt = current.announcedAt ?? incoming.announcedAt
            result[index] = current
        }
        return result.sorted {
            let l = $0.announcedAt ?? .distantPast, r = $1.announcedAt ?? .distantPast
            return l == r ? $0.id < $1.id : l > r
        }
    }

    private static let originalTextEvidence = "官方原帖明确宣布已开始发放或已发放。"
    private static let terminalStatuses: Set<String> = ["completed", "confirmed", "propagated", "rolling_out", "cancelled", "canceled"]
    private static let targetedScopes: Set<String> = ["limited", "affected", "targeted", "partial", "selected", "individual", "subset"]

    private static func parseHistory(_ data: Data) -> [ResetAnnouncement] {
        guard let document = json(data) else { return [] }
        let rows: [[String: Any]]
        if let history = document["data"] as? [[String: Any]] { rows = history }
        else if let status = document["data"] as? [String: Any], let latest = status["latest_reset"] as? [String: Any] { rows = [latest] }
        else { return [] }
        return rows.compactMap { row in
            guard let source = row["source"] as? [String: Any],
                  normalized(source["type"] as? String) == "x_post",
                  normalized(source["author"] as? String) == "thsottiaux",
                  let urlString = source["url"] as? String, let url = URL(string: urlString),
                  let post = officialPost(url),
                  let date = date(row["announced_at"]),
                  let text = row["text"] as? String, text.count <= 100_000,
                  let kind = deliveryKind(in: text) else { return nil }
            // The canonical post identity is safer than a third-party generated row identifier.
            return ResetAnnouncement(
                id: post.id, title: kind == "banked" ? "官方已开始发放重置券" : "官方已开始重置额度",
                summary: text, sourceURL: url, announcedAt: date, scheduledFor: nil,
                kind: kind == "banked" ? "banked" : "regular",
                scope: isSeparateBenefit(text) ? "limited" : "unspecified", status: "rolling_out",
                deliveryAt: date, relatedAnnouncementIDs: nil, deliveryKind: kind,
                completionEvidence: originalTextEvidence
            )
        }
    }

    private static func parseEvents(_ data: Data) -> [ResetAnnouncement] {
        guard let document = json(data), let rows = document["events"] as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            let lifecycle = normalized(row["lifecycle"] as? String)
            guard ["confirmed", "rolling_out"].contains(lifecycle),
                  normalized(row["verificationStatus"] as? String) == "primary_verified",
                  let evidence = row["evidence"] as? [[String: Any]],
                  let rawKind = row["resetType"] as? String else { return nil }
            let kind: String
            switch rawKind {
            case "automatic_global", "regular", "one_time": kind = "regular"
            case "banked": kind = "banked"
            default: return nil
            }
            let primary = evidence.filter {
                normalized($0["tier"] as? String) == "primary"
                    && normalized($0["verificationStatus"] as? String) == "primary_verified"
            }
            let confirmations = primary.filter {
                ["confirmation", "rollout"].contains(normalized($0["role"] as? String))
                    && officialPost(url($0["sourceUrl"])) != nil
            }.sorted { (date($0["publishedAt"]) ?? .distantPast) > (date($1["publishedAt"]) ?? .distantPast) }
            guard let confirmation = confirmations.first,
                  let sourceURL = url(confirmation["sourceUrl"]), let post = officialPost(sourceURL),
                  let delivered = date(row["confirmedAt"]) ?? date(confirmation["publishedAt"]) else { return nil }
            let related = primary.filter {
                ["announcement", "timing_update"].contains(normalized($0["role"] as? String))
            }.compactMap { officialPost(url($0["sourceUrl"]))?.id }.filter { $0 != post.id }
            // Without an announcement relation, do not manufacture one from an event's display date.
            let status = lifecycle == "rolling_out" || normalized(confirmation["role"] as? String) == "rollout"
                ? "rolling_out" : "completed"
            let summary = localized(row["summary"]) ?? "官方发放消息与原预告在公开事件记录中明确关联。"
            return ResetAnnouncement(
                id: post.id, title: kind == "banked" ? "官方已发放重置券" : "官方已重置额度",
                summary: summary, sourceURL: sourceURL, announcedAt: date(confirmation["publishedAt"]) ?? delivered,
                scheduledFor: nil, kind: kind, scope: isSeparateBenefit(summary) ? "limited" : "unspecified", status: status,
                deliveryAt: delivered, relatedAnnouncementIDs: related.isEmpty ? nil : Array(Set(related)).sorted(),
                deliveryKind: kind, completionEvidence: "公开事件中的官方发放证据与原预告明确关联。"
            )
        }
    }

    /// Match an explicit action clause, not a category or an isolated mention of reset/banked.
    private static func deliveryKind(in text: String) -> String? {
        let sentences = text.replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "**", with: "")
            .components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
        var kinds = Set<String>()
        let banked = [
            #"\b(?:we|i)\s+(?:are|am)\s+(?:now\s+)?(?:loading|adding|crediting|granting|issuing|distributing)\s+(?:a|one|an|another|the|\d+)\s+(?:full\s+)?banked\s+reset\b"#,
            #"\b(?:we|i)(?:\s+have|'ve)\s+(?:now\s+)?(?:added|credited|granted|issued|distributed|loaded)\s+(?:a|one|an|another|the|\d+)\s+(?:full\s+)?banked\s+reset\b"#,
            #"^\s*(?:added|credited|granted|issued|distributed|loaded)\s+(?:a|one|an|another|the|\d+)\s+(?:full\s+)?banked\s+reset\s+(?:to|into|for)\b"#,
            #"\bbanked\s+resets?\s+(?:have|has)\s+(?:now\s+)?been\s+(?:added|credited|granted|issued|distributed|loaded)\b"#,
            #"\bbanked\s+resets?\s+(?:have|has)\s+(?:now\s+)?(?:landed|arrived|rolled\s+out)\b"#
        ]
        let direct = [
            #"\b(?:we|i)(?:\s+have|'ve)\s+(?:now\s+)?reset\s+(?:(?:everyone's|all|the|codex)\s+)*(?:usage|rate|limits)\b"#,
            #"\b(?:we|i)\s+(?:are|am)\s+(?:once\s+again\s+|now\s+)?resetting\s+(?:the\s+)?(?:usage|rate|limits)\b"#,
            #"\b(?:we|i)\s+(?:are|am)\s+(?:now\s+)?reseting\s+(?:the\s+)?(?:usage|rate|limits)\b"#,
            #"\b(?:usage|rate)\s+limits\s+(?:have|has)\s+(?:now\s+)?been\s+reset\b"#,
            #"^\s*(?:reset\s+(?:has\s+been\s+)?(?:all\s+)?propagated|all\s+reset\s+for\s+everyone|reset\s+button\s+pressed)\b"#
        ]
        for sentence in sentences {
            for (kind, patterns) in [("banked", banked), ("regular", direct)] {
                for pattern in patterns {
                    guard let match = sentence.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { continue }
                    let prefix = String(sentence[..<match.lowerBound])
                    // Indirect claims, hypothetical clauses and negations are not official action evidence.
                    guard prefix.range(of: #"\b(?:if|unless|wish|hope|said|says|claim|claims|heard|told|reported|reportedly|not|never)\b|[“\"]"#,
                                       options: [.regularExpression, .caseInsensitive]) == nil else { continue }
                    guard sentence.range(of: #"\b(?:not|never|haven't|hasn't|isn't|aren't|didn't)\b"#,
                                         options: [.regularExpression, .caseInsensitive]) == nil else { continue }
                    kinds.insert(kind)
                }
            }
        }
        return kinds.count > 1 ? "both" : kinds.first
    }

    private static func promisedKind(_ text: String) -> String? {
        let banked = text.range(of: #"\bbanked\s+reset\b|重置券|可兑换重置"#, options: [.regularExpression, .caseInsensitive]) != nil
        let direct = text.range(of: #"\bone[- ]time\s+reset\b|\b(?:hard|automatic|global)\s+reset\b|直接重置"#, options: [.regularExpression, .caseInsensitive]) != nil
        return banked == direct ? nil : banked ? "banked" : "regular"
    }

    private static func isSeparateBenefit(_ text: String) -> Bool {
        text.range(of: #"\b(?:compensat\w*|refund\w*|(?:affected|some|selected)\s+(?:users|accounts)|\d+\s*%\s+of\s+users|\d+[km]\s+users)\b|补偿|赔偿|部分用户"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func officialPost(_ url: URL?) -> (id: String, author: String)? {
        guard let url, url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              let host = url.host?.lowercased(),
              ["x.com", "www.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com"].contains(host) else { return nil }
        let path = url.path.split(separator: "/")
        guard path.count == 3, path[0].lowercased() == "thsottiaux", path[1] == "status",
              !path[2].isEmpty, path[2].allSatisfy(\.isNumber) else { return nil }
        return (String(path[2]), String(path[0]).lowercased())
    }

    private static func normalized(_ value: String?) -> String { value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "" }
    private static func json(_ data: Data) -> [String: Any]? { (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] }
    private static func url(_ value: Any?) -> URL? { (value as? String).flatMap(URL.init(string:)) }
    private static func date(_ value: Any?) -> Date? {
        guard let raw = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
    private static func localized(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        guard let map = value as? [String: String] else { return nil }
        return map["zh"] ?? map["en"]
    }
}
