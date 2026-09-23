import Foundation

enum NextResetError: Error, LocalizedError {
    case invalidResponse, httpStatus(Int), invalidDocument, invalidAnnouncement, invalidSavedState

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "公告接口未返回有效响应。"
        case .httpStatus(let status): return "公告接口暂不可用（\(status)）。"
        case .invalidDocument: return "公告接口格式发生变化，暂时无法确认更新。"
        case .invalidAnnouncement: return "有公告无法完整读取，本次检查未保存。"
        case .invalidSavedState: return "本地公告记录版本不兼容，原有记录未覆盖。"
        }
    }
}

struct NextResetClient {
    let session: URLSession
    let baseURL: URL

    init(session: URLSession? = nil, baseURL: URL = URL(string: "https://nextreset.net")!) {
        if let session { self.session = session } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.urlCredentialStorage = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
        self.baseURL = baseURL
    }

    func fetch() async throws -> NextResetSnapshot {
        async let status = get("api/status")
        async let archive = get("api/resets")
        return try await Self.decode(status: status, archive: archive)
    }

    private func get(_ path: String) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CodexNotch-ResetWatch/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NextResetError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw NextResetError.httpStatus(http.statusCode) }
        return data
    }

    static func decode(status statusData: Data, archive archiveData: Data) throws -> NextResetSnapshot {
        guard let status = try JSONSerialization.jsonObject(with: statusData) as? [String: Any],
              let archive = try JSONSerialization.jsonObject(with: archiveData) as? [String: Any],
              let history = archive["data"] as? [[String: Any]],
              let statusMeta = status["meta"] as? [String: Any],
              let archiveMeta = archive["meta"] as? [String: Any],
              status.keys.contains("latest_update"), status.keys.contains("scheduled") else {
            throw NextResetError.invalidDocument
        }
        var announcements: [String: ResetAnnouncement] = [:]
        for object in history {
            let announcement = try parseAnnouncement(object)
            announcements[announcement.id] = announcement
        }
        // Status entries supplement the archive, which may not yet contain a current preannouncement.
        for key in ["latest_broad_reset", "latest_update", "latest_confirmed_reset", "watch", "scheduled"] {
            guard let value = status[key], !(value is NSNull) else { continue }
            let values: [[String: Any]]
            if let object = value as? [String: Any] { values = [object] }
            else if let objects = value as? [[String: Any]] { values = objects }
            else { throw NextResetError.invalidDocument }
            for object in values {
                let defaultStatus: String? = key == "scheduled" ? "scheduled" : key == "latest_confirmed_reset" ? "completed" : nil
                let announcement = try parseAnnouncement(statusPayload(object), defaultStatus: defaultStatus)
                announcements[announcement.id] = announcement
            }
        }
        let metadata = try [statusMeta, archiveMeta].map(parseMetadata)
        return NextResetSnapshot(
            announcements: announcements.values.sorted {
                ($0.announcedAt ?? .distantPast) > ($1.announcedAt ?? .distantPast)
            },
            sourceCheckedAt: metadata.compactMap(\.checkedAt).min(),
            sourceIsFresh: metadata.allSatisfy(\.fresh)
        )
    }

    /// Status can wrap the source post in `event`, keeping its reset deadline on the envelope.
    /// Preserve the post's identity/publication time and never derive a deadline from either.
    private static func statusPayload(_ object: [String: Any]) throws -> [String: Any] {
        guard let wrapped = object["event"] else { return object }
        guard var event = wrapped as? [String: Any] else { throw NextResetError.invalidAnnouncement }
        for key in scheduledDateKeys {
            if let value = object[key] { event[key] = value }
        }
        return event
    }

    private static let scheduledDateKeys = ["scheduledFor", "scheduled_for", "scheduledAt", "scheduled_at",
                                            "resetAt", "reset_at", "targetAt", "target_at"]

    private static func parseAnnouncement(_ object: [String: Any], defaultStatus: String? = nil) throws -> ResetAnnouncement {
        let sourceString = string(object, keys: ["sourceUrl", "sourceURL", "source_url", "url"])
        let sourceURL = sourceString.flatMap(URL.init(string:)).flatMap { url in
            let host = url.host?.lowercased() ?? ""
            let normalizedHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            return url.scheme?.lowercased() == "https" && url.user == nil && url.password == nil
                && ["x.com", "twitter.com", "nextreset.net"].contains(normalizedHost) ? url : nil
        }
        // Scheduled entries sometimes use their original source URL instead of a separate archive ID.
        guard let id = string(object, keys: ["id", "sourceId", "source_id"])
                ?? sourceURL?.lastPathComponent, !id.isEmpty,
              let title = localized(object["title"]), !title.isEmpty else { throw NextResetError.invalidAnnouncement }
        let summary = localized(object["summary"]) ?? localized(object["description"]) ?? ""
        return ResetAnnouncement(
            id: id, title: title, summary: summary, sourceURL: sourceURL,
            announcedAt: try date(object, keys: ["announcedAt", "announced_at", "publishedAt", "published_at"]),
            scheduledFor: try date(object, keys: scheduledDateKeys),
            kind: string(object, keys: ["kind"]) ?? "unspecified",
            scope: string(object, keys: ["scope"]) ?? "unspecified",
            status: string(object, keys: ["status"]) ?? defaultStatus
        )
    }

    private static func parseMetadata(_ object: [String: Any]) throws -> (checkedAt: Date?, fresh: Bool) {
        guard let fresh = object["fresh"] as? Bool else { throw NextResetError.invalidDocument }
        let x = object["x_source"] as? [String: Any]
        let coverage = x?["coverage"] as? [String: Any]
        let xDate = try x.map { try date($0, keys: ["checked_at"]) } ?? nil
        let checkedAt = try xDate ?? date(object, keys: ["checked_at"])
        return (checkedAt, fresh && (x?["fresh"] as? Bool != false)
                && (coverage?["caughtUp"] as? Bool != false))
    }

    private static func string(_ object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let string = object[key] as? String, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return string }
        }
        return nil
    }

    private static func localized(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        guard let map = value as? [String: Any] else { return nil }
        return string(map, keys: ["zh", "zh-CN", "en"])
    }

    private static func date(_ object: [String: Any], keys: [String]) throws -> Date? {
        for key in keys {
            guard let value = object[key], !(value is NSNull) else { continue }
            guard let raw = value as? String else { throw NextResetError.invalidAnnouncement }
            if raw.isEmpty { continue }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsed = fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) { return parsed }
            // An explicit but ambiguous time is not a trustworthy deadline.
            throw NextResetError.invalidAnnouncement
        }
        return nil
    }
}
