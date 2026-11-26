import Foundation

struct DeviceAuth: Sendable {
    var deviceId: String
    var credential: String
    var offsetMs: Int?
}

enum HubError: Error, Equatable, LocalizedError {
    // The hub refused this phone's credential: it was revoked (or the hub forgot it).
    case revoked
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .revoked: return "This phone was revoked on the hub"
        case .failed(let message): return message
        }
    }
}

struct PushResult: Equatable, Sendable {
    var conflict: Bool
    var ackSeq: Int
}

protocol HubAPI: Sendable {
    func pair(token: String, name: String) async throws -> Paired
    func clock(t0: Int) async throws -> (t1: Int, t2: Int)
    func push(_ entries: [Entry]) async throws -> PushResult
    func roster(version: String?) async throws -> Roster? // nil = unchanged (304)
    func status() async throws -> Status
}

// The hub's /sync/v1 API, as the paired device. Every request gives up after
// `timeout`, so a half-open connection on venue Wi-Fi can't stall sync.
struct HTTPHubAPI: HubAPI {
    let base: URL
    let auth: @Sendable () -> DeviceAuth?
    var timeout: TimeInterval = 10
    var session: URLSession = .shared

    private struct ErrorBody: Decodable {
        var error: String?
        var ack_seq: Int?
    }

    func pair(token: String, name: String) async throws -> Paired {
        let (status, data) = try await send("POST", "/devices/pair", body: ["token": token, "name": name], authorized: false)
        guard (200..<300).contains(status) else { throw HubError.failed(errorBody(data)?.error ?? "Pairing failed") }
        return try decode(Paired.self, data)
    }

    func clock(t0: Int) async throws -> (t1: Int, t2: Int) {
        struct Times: Decodable { var t1: Int; var t2: Int }
        let (status, data) = try await send("POST", "/sync/v1/clock", body: ["t0": t0])
        guard status == 200 else { throw HubError.failed("clock \(status)") }
        let times = try decode(Times.self, data)
        return (times.t1, times.t2)
    }

    func push(_ entries: [Entry]) async throws -> PushResult {
        let (status, data) = try await send("POST", "/sync/v1/push", body: ["entries": entries])
        let body = errorBody(data)
        if status == 409 { return PushResult(conflict: true, ackSeq: body?.ack_seq ?? 0) }
        guard (200..<300).contains(status), let ack = body?.ack_seq else { throw HubError.failed(body?.error ?? "push \(status)") }
        return PushResult(conflict: false, ackSeq: ack)
    }

    func roster(version: String?) async throws -> Roster? {
        let (status, data) = try await send("GET", "/sync/v1/roster", headers: version.map { ["If-None-Match": $0] } ?? [:])
        if status == 304 { return nil }
        guard status == 200 else { throw HubError.failed("roster \(status)") }
        return try decode(Roster.self, data)
    }

    func status() async throws -> Status {
        let (status, data) = try await send("GET", "/sync/v1/status")
        guard status == 200 else { throw HubError.failed("status \(status)") }
        return try decode(Status.self, data)
    }

    // MARK: private

    private func send(_ method: String, _ path: String, body: (any Encodable)? = nil, headers: [String: String] = [:],
                      authorized: Bool = true) async throws -> (Int, Data) {
        var request = URLRequest(url: base.appendingPathComponent(String(path.dropFirst())), timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authorized, let device = auth() {
            request.setValue("Device \(device.deviceId):\(device.credential)", forHTTPHeaderField: "Authorization")
            if let offset = device.offsetMs { request.setValue(String(offset), forHTTPHeaderField: "X-Clock-Offset-Ms") }
        }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let body { request.httpBody = try JSONEncoder().encode(body) }
        let (data, response) = try await withTimeout { try await session.data(for: request) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 && authorized { throw HubError.revoked }
        return (status, data)
    }

    // The request, or HubError.failed when it doesn't answer within `timeout`
    // (whichever comes first; the loser is cancelled).
    private func withTimeout<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let seconds = timeout
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                do { return try await operation() } catch let error as URLError { throw HubError.failed(error.localizedDescription) }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw HubError.failed("The hub didn't answer")
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    private func errorBody(_ data: Data) -> ErrorBody? { try? JSONDecoder().decode(ErrorBody.self, from: data) }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) } catch { throw HubError.failed("Unexpected answer from the hub") }
    }
}
