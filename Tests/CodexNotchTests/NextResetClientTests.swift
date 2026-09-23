import Foundation
import XCTest
@testable import CodexNotch

final class NextResetClientTests: XCTestCase {
    func testPublicArchiveAndScheduledStatusAreMergedWithoutInventingResetTime() throws {
        let result = try NextResetClient.decode(status: data(status()), archive: data(archive()))
        XCTAssertEqual(result.announcements.count, 2)
        let completed = try XCTUnwrap(result.announcements.first(where: { $0.id == "old" }))
        XCTAssertEqual(completed.title, "重置已完成")
        XCTAssertEqual(completed.status, "completed")
        XCTAssertNil(completed.scheduledFor)
        let planned = try XCTUnwrap(result.announcements.first(where: { $0.id == "planned" }))
        XCTAssertEqual(planned.status, "scheduled")
        XCTAssertEqual(planned.scheduledFor, ISO8601DateFormatter().date(from: "2026-09-13T07:00:00Z"))
        XCTAssertEqual(result.sourceCheckedAt, ISO8601DateFormatter().date(from: "2026-09-12T13:07:27Z"))
        XCTAssertTrue(result.sourceIsFresh)
    }

    func testUnknownScheduledDeadlineRemainsNilAndEnglishFallbackWorks() throws {
        var object = status()
        var planned = announcement("planned", title: ["en": "A reset is planned"])
        planned["summary"] = ["en": "Time has not been announced"]
        object["scheduled"] = planned
        let result = try NextResetClient.decode(status: data(object), archive: data(archive()))
        let post = try XCTUnwrap(result.announcements.first(where: { $0.id == "planned" }))
        XCTAssertNil(post.scheduledFor)
        XCTAssertEqual(post.title, "A reset is planned")
        XCTAssertEqual(post.status, "scheduled")
    }

    func testNestedScheduledEventMergesArchiveAndStatusWithoutLosingOuterDeadline() throws {
        var event = announcement("planned", title: ["zh": "明日重置预告"])
        event["announcedAt"] = "2026-09-22T08:00:00.000Z"
        var scheduledEvent = event
        scheduledEvent["scheduledFor"] = "2026-09-23T06:00:00.000Z"
        var object = status()
        object["latest_update"] = event
        object["latest_confirmed_reset"] = event
        object["scheduled"] = [
            "event": scheduledEvent,
            "scheduledFor": "2026-09-23T07:00:00.000Z"
        ]

        let result = try NextResetClient.decode(
            status: data(object), archive: data(["data": [event], "meta": meta()])
        )
        XCTAssertEqual(result.announcements.count, 1)
        let post = try XCTUnwrap(result.announcements.first)
        XCTAssertEqual(post.id, "planned")
        XCTAssertEqual(post.title, "明日重置预告")
        XCTAssertEqual(post.status, "scheduled")
        XCTAssertEqual(post.announcedAt, ISO8601DateFormatter().date(from: "2026-09-22T08:00:00Z"))
        XCTAssertEqual(post.scheduledFor, ISO8601DateFormatter().date(from: "2026-09-23T07:00:00Z"))
        XCTAssertNotEqual(post.announcedAt, post.scheduledFor)
    }

    func testNestedScheduledEventWithUnknownDeadlineRemainsValidWithoutInventingTime() throws {
        for deadline in [nil, NSNull()] as [Any?] {
            var scheduled: [String: Any] = [
                "event": announcement("planned", title: ["en": "A reset is planned"])
            ]
            scheduled["scheduledFor"] = deadline
            var object = status()
            object["scheduled"] = scheduled

            let result = try NextResetClient.decode(status: data(object), archive: data(archive()))
            let post = try XCTUnwrap(result.announcements.first(where: { $0.id == "planned" }))
            XCTAssertEqual(post.title, "A reset is planned")
            XCTAssertEqual(post.status, "scheduled")
            XCTAssertNotNil(post.announcedAt)
            XCTAssertNil(post.scheduledFor)
        }
    }

    func testNestedScheduledExplicitNullDeadlineOverridesEarlierEventDeadline() throws {
        var event = announcement("planned")
        event["scheduledFor"] = "2026-09-23T06:00:00.000Z"
        var object = status()
        object["scheduled"] = ["event": event, "scheduledFor": NSNull()]

        let result = try NextResetClient.decode(status: data(object), archive: data(archive()))
        let post = try XCTUnwrap(result.announcements.first(where: { $0.id == "planned" }))
        XCTAssertEqual(post.status, "scheduled")
        XCTAssertNil(post.scheduledFor)
    }

    func testMalformedNestedEventFailsWholeSnapshotInsteadOfReturningValidArchiveOnly() {
        let invalidEvents: [Any] = [NSNull(), "not an event", [announcement("planned")], ["id": "missing-title"]]
        for event in invalidEvents {
            var object = status()
            object["scheduled"] = ["event": event, "scheduledFor": "2026-09-23T07:00:00.000Z"]
            XCTAssertThrowsError(try NextResetClient.decode(status: data(object), archive: data(archive())))
        }
    }

    func testNestedWatchEventRemainsVisibleWithoutClaimingScheduledReset() throws {
        var event = announcement("watch", title: ["zh": "正在关注重置消息"])
        event["status"] = "watch"
        var object = status()
        object["scheduled"] = NSNull()
        object["watch"] = ["event": event, "scheduledFor": NSNull()]

        let result = try NextResetClient.decode(status: data(object), archive: data(archive()))
        let post = try XCTUnwrap(result.announcements.first(where: { $0.id == "watch" }))
        XCTAssertEqual(result.announcements.count, 2)
        XCTAssertEqual(post.title, "正在关注重置消息")
        XCTAssertEqual(post.status, "watch")
        XCTAssertNil(post.scheduledFor)
    }

    func testNestedScheduledEventDoesNotHideStaleOriginalSource() throws {
        var object = status()
        object["scheduled"] = [
            "event": announcement("planned"), "scheduledFor": "2026-09-23T07:00:00.000Z"
        ]
        var source = meta()
        source["x_source"] = ["checked_at": "2026-09-12T13:07:27Z", "fresh": false, "coverage": ["caughtUp": false]]
        object["meta"] = source

        let result = try NextResetClient.decode(status: data(object), archive: data(archive()))
        XCTAssertEqual(result.announcements.count, 2)
        XCTAssertEqual(result.announcements.first(where: { $0.id == "planned" })?.status, "scheduled")
        XCTAssertFalse(result.sourceIsFresh)
        XCTAssertEqual(result.sourceCheckedAt, ISO8601DateFormatter().date(from: "2026-09-12T13:07:27Z"))
    }

    func testMalformedOrPartialArchiveFailsInsteadOfLookingLikeNoNews() {
        XCTAssertThrowsError(try NextResetClient.decode(status: data(status()), archive: data(["meta": meta()])))
        XCTAssertThrowsError(try NextResetClient.decode(status: data(status()), archive: data(["data": [["id": "missing-title"]], "meta": meta()])))
        XCTAssertThrowsError(try NextResetClient.decode(status: data([:]), archive: data(archive())))
    }

    func testSourceAgeAndCoverageRemainVisibleEvenWhenArchiveFetchSucceeds() throws {
        var object = status()
        var source = meta()
        source["x_source"] = ["checked_at": "2026-09-12T13:07:27Z", "fresh": false, "coverage": ["caughtUp": false]]
        object["meta"] = source
        let result = try NextResetClient.decode(status: data(object), archive: data(archive()))
        XCTAssertFalse(result.sourceIsFresh)
        XCTAssertEqual(result.announcements.count, 2)
    }

    func testClientReadsBothPublicEndpointsWithoutCredentials() async throws {
        let statusBody = data(status()), archiveBody = data(archive())
        NextResetMockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            let body: Data
            switch request.url!.path {
            case "/api/status": body = statusBody
            case "/api/resets": body = archiveBody
            default: throw URLError(.badURL)
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        defer { NextResetMockURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NextResetMockURLProtocol.self]
        let snapshot = try await NextResetClient(session: URLSession(configuration: config)).fetch()
        XCTAssertEqual(snapshot.announcements.count, 2)
    }

    private func status() -> [String: Any] {
        var planned = announcement("planned", title: ["zh": "未来重置"])
        planned["scheduledFor"] = "2026-09-13T07:00:00Z"
        return ["latest_update": announcement("old"), "latest_confirmed_reset": announcement("old"),
                "scheduled": planned, "watch": NSNull(), "meta": meta()]
    }
    private func archive() -> [String: Any] { ["data": [announcement("old")], "meta": meta()] }
    private func announcement(_ id: String, title: [String: String] = ["zh": "重置已完成", "en": "Reset complete"]) -> [String: Any] {
        ["id": id, "title": title, "summary": ["zh": "公告原文有适用条件"], "sourceUrl": "https://x.com/thsottiaux/status/\(id)",
         "announcedAt": "2026-09-12T08:09:17.000Z", "kind": "regular", "scope": "unspecified"]
    }
    private func meta() -> [String: Any] {
        ["fresh": true, "checked_at": "2026-09-12T13:16:03.116Z",
         "x_source": ["fresh": true, "checked_at": "2026-09-12T13:07:27Z", "coverage": ["caughtUp": true]]]
    }
    private func data(_ object: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: object) }
}

private final class NextResetMockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (response, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
