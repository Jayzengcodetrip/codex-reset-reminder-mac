import Foundation

/// Reads only the first redirect of a small number of official-post short links.
/// It never loads X, follows another redirect, or shares an authenticated session.
final class BoundedResetLinkResolver: @unchecked Sendable {
    static let maximumLinks = 4
    private let session: URLSession
    private let timeout: TimeInterval

    // Configuration injection supports URLProtocol tests; the private session and
    // redirect delegate cannot be replaced with one that forwards credentials.
    init(configuration: URLSessionConfiguration = .ephemeral, timeout: TimeInterval = 5) {
        let configuration = configuration.copy() as! URLSessionConfiguration
        self.timeout = min(5, max(0.1, timeout))
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.httpAdditionalHeaders = [:]
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = self.timeout
        configuration.timeoutIntervalForResource = self.timeout
        session = URLSession(configuration: configuration, delegate: RejectResetLinkRedirects(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    func resolve(_ candidates: [URL]) async -> [URL: URL] {
        var seen = Set<URL>()
        let links = Array(candidates.filter { Self.isAllowedShortLink($0) && seen.insert($0).inserted }
            .prefix(Self.maximumLinks))
        return await withTaskGroup(of: (URL, URL?).self) { group in
            for link in links {
                group.addTask { (link, await self.resolveOne(link)) }
            }
            var resolved: [URL: URL] = [:]
            for await (link, destination) in group {
                if let destination { resolved[link] = destination }
            }
            return resolved
        }
    }

    private func resolveOne(_ link: URL) async -> URL? {
        guard !Task.isCancelled else { return nil }
        var request = URLRequest(url: link, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: timeout)
        request.httpMethod = "HEAD"
        request.httpShouldHandleCookies = false
        request.setValue("CodexNotch-ResetWatch/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.url == link,
                  [301, 302, 303, 307, 308].contains(http.statusCode),
                  let location = http.value(forHTTPHeaderField: "Location") else { return nil }
            return Self.officialPostDestination(location)
        } catch {
            // Optional context must never turn a healthy public feed into a failure.
            return nil
        }
    }

    static func isAllowedShortLink(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https", components.host?.lowercased() == "t.co",
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil else { return false }
        return components.percentEncodedPath.range(of: "^/[A-Za-z0-9]{1,64}$",
                                                   options: .regularExpression) != nil
    }

    static func officialPostDestination(_ location: String) -> URL? {
        guard let components = URLComponents(string: location),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              ["x.com", "www.x.com", "twitter.com", "www.twitter.com"].contains(host),
              components.user == nil, components.password == nil, components.port == nil,
              components.percentEncodedPath.range(of: "^/thsottiaux/status/[0-9]{1,30}/?$",
                  options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        let id = components.path.split(separator: "/").last!
        // Query strings and fragments are unnecessary for identity and are discarded.
        return URL(string: "https://x.com/thsottiaux/status/\(id)")
    }
}

final class RejectResetLinkRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
