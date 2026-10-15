import Foundation
import XCTest
@testable import CodexNotch

final class BoundedResetLinkResolverTests: XCTestCase {
    private let link = URL(string: "https://t.co/SyntheticLink")!
    private let post = URL(string: "https://x.com/thsottiaux/status/1001")!

    override func tearDown() {
        ResetLinkMockURLProtocol.handler = nil
        super.tearDown()
    }

    private func resolver(timeout: TimeInterval = 5) -> BoundedResetLinkResolver {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResetLinkMockURLProtocol.self]
        // The resolver must clear inherited headers even with an injected configuration.
        configuration.httpAdditionalHeaders = ["Authorization": "synthetic-secret", "Cookie": "synthetic-cookie"]
        return BoundedResetLinkResolver(configuration: configuration, timeout: timeout)
    }

    func testAcceptedRedirectsUseAnonymousHeadAndNeverRequestDestination() async {
        for status in [301, 302, 303, 307, 308] {
            var requested: [URL] = []
            ResetLinkMockURLProtocol.handler = { request in
                requested.append(request.url!)
                XCTAssertEqual(request.url, self.link)
                XCTAssertEqual(request.httpMethod, "HEAD")
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
                XCTAssertFalse(request.httpShouldHandleCookies)
                XCTAssertLessThanOrEqual(request.timeoutInterval, 5)
                return HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                    headerFields: ["Location": "https://www.twitter.com/thsottiaux/status/1001?s=20#context"])!
            }
            let result = await resolver(timeout: 60).resolve([link])
            XCTAssertEqual(result, [link: post])
            XCTAssertEqual(requested, [link])
        }
    }

    func testRedirectDelegateRejectsEvenAnAllowedDestinationRequest() {
        let response = HTTPURLResponse(url: link, statusCode: 302, httpVersion: nil,
                                       headerFields: ["Location": post.absoluteString])!
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var called = false
        RejectResetLinkRedirects().urlSession(session, task: session.dataTask(with: link),
            willPerformHTTPRedirection: response, newRequest: URLRequest(url: post)) { request in
                called = true
                XCTAssertNil(request)
            }
        XCTAssertTrue(called)
    }

    func testNonRedirectMissingAndUntrustedLocationsAreIgnored() async {
        let cases: [(Int, String?)] = [
            (200, post.absoluteString), (300, post.absoluteString), (304, post.absoluteString),
            (404, post.absoluteString), (302, nil), (302, "https://example.com/thsottiaux/status/1001"),
            (302, "https://t.co/AnotherLink"), (302, "/thsottiaux/status/1001")
        ]
        for (status, location) in cases {
            ResetLinkMockURLProtocol.handler = { request in
                HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                headerFields: location.map { ["Location": $0] })!
            }
            let result = await resolver().resolve([link])
            XCTAssertTrue(result.isEmpty)
        }
    }

    func testOnlyExactHTTPSOfficialPostDestinationsAreAccepted() {
        for host in ["x.com", "www.x.com", "twitter.com", "www.twitter.com"] {
            XCTAssertEqual(BoundedResetLinkResolver.officialPostDestination(
                "https://\(host)/Thsottiaux/status/1001/"), post)
        }
        for location in ["http://x.com/thsottiaux/status/1001", "https://x.com.evil.test/thsottiaux/status/1001",
                         "https://user@x.com/thsottiaux/status/1001", "https://x.com:443/thsottiaux/status/1001",
                         "https://x.com/other/status/1001", "https://x.com/thsottiaux/status/not-a-number",
                         "https://x.com/thsottiaux/status/1001/photo/1", "https://x.com/thsottiaux/status/%31",
                         "https://x.com/thsottiaux/status/", "https://x.com/thsottiaux/status/1001/../2",
                         "https://127.0.0.1/thsottiaux/status/1001", "file:///thsottiaux/status/1001"] {
            XCTAssertNil(BoundedResetLinkResolver.officialPostDestination(location), location)
        }
    }

    func testShortLinkValidationExcludesCredentialsPortsQueriesAndNestedPaths() {
        XCTAssertTrue(BoundedResetLinkResolver.isAllowedShortLink(link))
        for text in ["http://t.co/abc", "https://www.t.co/abc", "https://t.co.evil.test/abc",
                     "https://user@t.co/abc", "https://t.co:443/abc", "https://t.co/abc?x=1",
                     "https://t.co/abc#fragment", "https://t.co/a/b", "https://t.co/abc/",
                     "https://t.co/%61bc", "https://t.co/", "https://t.co/a-b", "https://localhost/abc"] {
            XCTAssertFalse(BoundedResetLinkResolver.isAllowedShortLink(URL(string: text)!), text)
        }
    }

    func testOnlyFourUniqueAllowedLinksAreRequested() async {
        let lock = NSLock()
        var requests: [URL] = []
        ResetLinkMockURLProtocol.handler = { request in
            lock.lock()
            requests.append(request.url!)
            lock.unlock()
            return HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil,
                                   headerFields: ["Location": self.post.absoluteString])!
        }
        let links = (1...8).map { URL(string: "https://t.co/Link\($0)")! }
        let result = await resolver().resolve([URL(string: "https://example.com/no")!, links[0]] + links)
        XCTAssertEqual(Set(requests), Set(links.prefix(4)))
        XCTAssertEqual(result.count, 4)
    }

    func testTimeoutAndTransportErrorsOnlyDropOptionalContext() async {
        for code in [URLError.Code.timedOut, .cancelled, .cannotFindHost, .notConnectedToInternet] {
            ResetLinkMockURLProtocol.handler = { request in
                XCTAssertEqual(request.timeoutInterval, 0.2)
                throw URLError(code)
            }
            let result = await resolver(timeout: 0.2).resolve([link])
            XCTAssertTrue(result.isEmpty)
        }
    }

    func testResponseFromAnotherURLCannotSupplyContext() async {
        ResetLinkMockURLProtocol.handler = { _ in
            HTTPURLResponse(url: self.post, statusCode: 302, httpVersion: nil,
                            headerFields: ["Location": self.post.absoluteString])!
        }
        let result = await resolver().resolve([link])
        XCTAssertTrue(result.isEmpty)
    }

    func testEmptyOrInvalidCandidateListMakesNoNetworkRequest() async {
        ResetLinkMockURLProtocol.handler = { _ in
            XCTFail("No optional request should be made")
            throw URLError(.badURL)
        }
        let result = await resolver().resolve([URL(string: "https://x.com/thsottiaux/status/1001")!])
        XCTAssertTrue(result.isEmpty)
    }
}

private final class ResetLinkMockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> HTTPURLResponse)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badURL) }
            let response = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
