import Foundation

// Where this phone is on the course (nil: the finish line), and when that was
// last chosen, in hub time.
struct Location: Codable, Equatable, Sendable {
    var checkpointId: String?
    var changedAtMs: Int
}

// The hub wins when an official moved the phone after the phone's own last change.
func shouldAdopt(_ local: Location?, _ hub: Roster.Device) -> Bool {
    guard let setAt = hub.checkpoint_set_at_ms else { return false }
    if let local, hub.checkpoint_id == local.checkpointId { return false }
    guard let local else { return true }
    return setAt > local.changedAtMs
}

func locationName(_ checkpointId: String?, _ roster: Roster?) -> String {
    guard let checkpointId else { return "Finish" }
    return roster?.checkpoints.first { $0.id == checkpointId }?.name ?? "Unknown checkpoint"
}
