import CryptoKit
import Foundation

// SHA-256 of the entry's canonical JSON, without its own hash. The first
// entry chains from SHA-256(device id).
enum DeviceHash {
    static func digest(_ fields: [String: JSONValue]) -> String {
        var body = fields
        body.removeValue(forKey: "hash")
        return sha256Hex(canonicalJSON(body))
    }

    static func genesis(_ deviceId: String) -> String { sha256Hex(deviceId) }

    // UUIDv7: 48-bit ms timestamp, then random bits (sortable, like the hub's ids).
    static func uuidv7(nowMs: Int = Int(Date().timeIntervalSince1970 * 1000)) -> String {
        var bytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        for i in 0..<6 { bytes[i] = UInt8((nowMs >> (8 * (5 - i))) & 0xff) }
        bytes[6] = (bytes[6] & 0x0f) | 0x70
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let parts = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { r in
            String(hex[hex.index(hex.startIndex, offsetBy: r.lowerBound)..<hex.index(hex.startIndex, offsetBy: r.upperBound)])
        }
        return parts.joined(separator: "-")
    }

    private static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
