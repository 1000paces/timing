import Foundation
import Testing
@testable import TimingCapture

// Answers requests from a canned handler, recording what was sent.
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data)?)?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var request = self.request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            stream.close()
            request.httpBody = data
        }
        Self.requests.append(request)
        guard let (status, body) = Self.handler?(request) else { return } // never answers
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized) struct HubAPITests {
    let base = URL(string: "https://hub.local:3443")!

    func api(timeout: TimeInterval = 10, auth: DeviceAuth? = DeviceAuth(deviceId: "dev-1", credential: "secret", offsetMs: -25),
             _ handler: @escaping (URLRequest) -> (Int, Data)?) -> HTTPHubAPI {
        StubProtocol.requests = []
        StubProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return HTTPHubAPI(base: base, auth: { auth }, timeout: timeout, session: URLSession(configuration: config))
    }

    func json(_ s: String) -> Data { Data(s.utf8) }

    @Test func sendsDeviceAuthAndOffset() async throws {
        let hub = api { _ in (200, self.json(#"{"captures":[]}"#)) }
        _ = try await hub.status()
        let request = try #require(StubProtocol.requests.first)
        #expect(request.url?.absoluteString == "https://hub.local:3443/sync/v1/status")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Device dev-1:secret")
        #expect(request.value(forHTTPHeaderField: "X-Clock-Offset-Ms") == "-25")
    }

    @Test func noOffsetHeaderBeforeClockSync() async throws {
        let hub = api(auth: DeviceAuth(deviceId: "dev-1", credential: "secret", offsetMs: nil)) { _ in (200, self.json(#"{"t1":5,"t2":6}"#)) }
        let times = try await hub.clock(t0: 1)
        #expect(times.t1 == 5 && times.t2 == 6)
        let request = try #require(StubProtocol.requests.first)
        #expect(request.value(forHTTPHeaderField: "X-Clock-Offset-Ms") == nil)
        #expect(request.httpMethod == "POST")
        #expect(String(data: request.httpBody ?? Data(), encoding: .utf8) == #"{"t0":1}"#)
    }

    @Test func unauthorizedIsRevoked() async throws {
        let hub = api { _ in (401, self.json(#"{"error":"unknown or revoked device"}"#)) }
        await #expect(throws: HubError.revoked) { _ = try await hub.status() }
    }

    @Test func pushConflictReturnsAck() async throws {
        let hub = api { _ in (409, self.json(#"{"error":"x","ack_seq":4}"#)) }
        #expect(try await hub.push([]) == PushResult(conflict: true, ackSeq: 4))
    }

    @Test func pushOmitsNilFields() async throws {
        let hub = api { _ in (200, self.json(#"{"ack_seq":1}"#)) }
        let entry = Entry(id: "e1", kind: .capture, device_seq: 1, prev_hash: "p", hash: "h", captured_at_ms: 1000)
        #expect(try await hub.push([entry]) == PushResult(conflict: false, ackSeq: 1))
        let body = try #require(StubProtocol.requests.first?.httpBody)
        let sent = try #require((try JSONSerialization.jsonObject(with: body) as? [String: [[String: Any]]])?["entries"]?.first)
        #expect(sent.keys.sorted() == ["captured_at_ms", "device_seq", "hash", "id", "kind", "prev_hash"])
    }

    @Test func rosterNotModifiedIsNil() async throws {
        let hub = api { _ in (304, Data()) }
        #expect(try await hub.roster(version: "v1") == nil)
        #expect(StubProtocol.requests.first?.value(forHTTPHeaderField: "If-None-Match") == "v1")
    }

    @Test func pairSendsTokenAndName() async throws {
        let hub = api(auth: nil) { _ in (201, self.json(#"{"device_id":"d","credential":"c","event_id":"e"}"#)) }
        #expect(try await hub.pair(token: "K7Q-4MX", name: "Finish") == Paired(device_id: "d", credential: "c", event_id: "e"))
        let request = try #require(StubProtocol.requests.first)
        #expect(request.url?.path == "/devices/pair")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String]
        #expect(body == ["token": "K7Q-4MX", "name": "Finish"])
    }

    @Test func pairErrorUsesBody() async throws {
        let hub = api { _ in (422, self.json(#"{"error":"Code expired"}"#)) }
        await #expect(throws: HubError.failed("Code expired")) { _ = try await hub.pair(token: "X", name: "P") }
    }

    @Test func otherFailuresNameTheEndpoint() async throws {
        let hub = api { _ in (500, Data()) }
        await #expect(throws: HubError.failed("status 500")) { _ = try await hub.status() }
    }

    @Test func timeoutIsFailure() async throws {
        let hub = api(timeout: 0.2) { _ in nil }
        await #expect(throws: HubError.self) { _ = try await hub.status() }
    }
}
