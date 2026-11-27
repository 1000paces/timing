import Foundation
import Testing
@testable import TimingCapture

func makeRoster(races: [Roster.Race] = [], racers: [Roster.Racer] = [], checkpoints: [Roster.Checkpoint] = [],
                device: Roster.Device = .init(checkpoint_id: nil, checkpoint_set_at_ms: nil), version: String = "v") -> Roster {
    Roster(event: .init(name: "E", races: races), racers: racers, checkpoints: checkpoints, device: device, version: version)
}

@Suite struct LocationTests {
    let hubA1 = Roster.Device(checkpoint_id: "a1", checkpoint_set_at_ms: 2_000)

    @Test func adoptsNewerHubMove() {
        #expect(shouldAdopt(Location(checkpointId: nil, changedAtMs: 1_000), hubA1))
    }

    @Test func keepsNewerOrAgreeingLocal() {
        #expect(!shouldAdopt(Location(checkpointId: nil, changedAtMs: 3_000), hubA1))
        #expect(!shouldAdopt(Location(checkpointId: "a1", changedAtMs: 1_000), hubA1))
    }

    @Test func neverChoseTakesHubIgnoresUnset() {
        #expect(shouldAdopt(nil, hubA1))
        #expect(!shouldAdopt(nil, Roster.Device(checkpoint_id: nil, checkpoint_set_at_ms: nil)))
    }

    @Test func namesFinishAndCheckpoints() {
        let roster = makeRoster(checkpoints: [.init(id: "a1", name: "Aid 1")])
        #expect(locationName(nil, roster) == "Finish")
        #expect(locationName("a1", roster) == "Aid 1")
        #expect(locationName("zz", roster) == "Unknown checkpoint")
        #expect(locationName("a1", nil) == "Unknown checkpoint")
    }
}
