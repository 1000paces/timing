import Foundation

// A device log value: entries only ever hold strings and integers (and nulls,
// which the checksum omits).
enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Device log values are strings or integers")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .int(let i): try c.encode(i)
        case .null: try c.encodeNil()
        }
    }
}

// The device log checksum's canonical form, shared with the hub
// (packs/timing/app/models/device_hash.rb) and the PWA (frontend/capture/src/hash.ts):
// keys sorted, no whitespace, null fields omitted. Strings are escaped as
// JSON.stringify does: quote, backslash and control characters only.
func canonicalJSON(_ fields: [String: JSONValue]) -> String {
    let parts = fields
        .filter { $0.value != .null }
        .sorted { Array($0.key.utf8).lexicographicallyPrecedes($1.key.utf8) }
        .map { "\(jsonString($0.key)):\(jsonLiteral($0.value))" }
    return "{\(parts.joined(separator: ","))}"
}

private func jsonLiteral(_ value: JSONValue) -> String {
    switch value {
    case .string(let s): return jsonString(s)
    case .int(let i): return String(i)
    case .null: return "null"
    }
}

private func jsonString(_ s: String) -> String {
    var out = "\""
    for scalar in s.unicodeScalars {
        switch scalar {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\u{08}": out += "\\b"
        case "\u{0C}": out += "\\f"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        case _ where scalar.value < 0x20: out += String(format: "\\u%04x", scalar.value)
        default: out.unicodeScalars.append(scalar)
        }
    }
    return out + "\""
}
