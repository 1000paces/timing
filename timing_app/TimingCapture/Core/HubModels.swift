import Foundation

// The hub's /sync/v1 payloads; property names are the wire keys.

struct Roster: Codable, Equatable, Sendable {
    struct Event: Codable, Equatable, Sendable {
        var name: String
        var races: [Race]
    }

    struct Race: Codable, Equatable, Sendable {
        var id: String
        var name: String
    }

    struct Racer: Codable, Equatable, Sendable {
        var bib: String
        var name: String
        var race_id: String
    }

    struct Checkpoint: Codable, Equatable, Sendable {
        var id: String
        var name: String
    }

    // Where the hub has this phone (course events), and when an official set it.
    struct Device: Codable, Equatable, Sendable {
        var checkpoint_id: String?
        var checkpoint_set_at_ms: Int?
    }

    var event: Event
    var racers: [Racer]
    var checkpoints: [Checkpoint]
    var device: Device
    var version: String
}

struct Status: Codable, Equatable, Sendable {
    struct Capture: Codable, Equatable, Sendable {
        var id: String
        var bib: String?
        var entered_bib: String?
        var bib_source: String // "ruling" | "device" | "entered"
        var lap: Int?
        var lap_ms: Int?
        var typical_lap_ms: Int?
        var lap_flag: String? // "missed" | "long" | "short"
        var voided: Bool
    }

    var captures: [Capture]
}

struct Paired: Codable, Equatable, Sendable {
    var device_id: String
    var credential: String
    var event_id: String
}
