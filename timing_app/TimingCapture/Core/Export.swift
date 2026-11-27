import Foundation

// The phone's whole log as JSON (a last-resort backup for an official), in the
// PWA's export shape. Never includes the device credential.
func exportJSON(pairing: Pairing?, entries: [Entry], archives: [ArchivedLog]) throws -> Data {
    struct PairingInfo: Encodable {
        var deviceId: String
        var eventId: String
        var name: String
        var hubURL: URL
    }
    struct Archived: Encodable {
        var pairing: PairingInfo?
        var entries: [Entry]
        var archivedAtMs: Int
    }
    struct Body: Encodable {
        var pairing: PairingInfo?
        var entries: [Entry]
        var archive: [Archived]
    }
    let info = { (p: Pairing?) in p.map { PairingInfo(deviceId: $0.deviceId, eventId: $0.eventId, name: $0.name, hubURL: $0.hubURL) } }
    let body = Body(pairing: info(pairing), entries: entries,
                    archive: archives.map { Archived(pairing: info($0.pairing), entries: $0.entries, archivedAtMs: $0.archivedAtMs) })
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(body)
}

// capture-log-<phone name>-<UTC time>.json, as the PWA names it.
func exportFileName(phoneName: String?, at date: Date) -> String {
    let name = (phoneName ?? "phone").replacingOccurrences(of: "\\W+", with: "-", options: .regularExpression)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    let stamp = formatter.string(from: date).replacingOccurrences(of: "Z", with: "")
    return "capture-log-\(name)-\(stamp).json"
}
