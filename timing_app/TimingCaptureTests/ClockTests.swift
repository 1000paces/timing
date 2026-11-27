import Foundation
import Testing
@testable import TimingCapture

@Suite struct ClockTests {
    @Test func fastestRoundTripWins() {
        // offset = ((t1 - t0) + (t2 - t3)) / 2 ; rtt = (t3 - t0) - (t2 - t1)
        let slow = ClockSample(t0: 0, t1: 600, t2: 600, t3: 400) // rtt 400, offset 400
        let fast = ClockSample(t0: 1000, t1: 1550, t2: 1550, t3: 1100) // rtt 100, offset 500
        let picked = pickOffset([slow, fast])
        #expect(picked.offsetMs == 500)
        #expect(picked.rttMs == 100)
    }

    @Test func offsetRoundsHalfUpLikeMathRound() {
        #expect(pickOffset([ClockSample(t0: 0, t1: 1, t2: 1, t3: 0)]).offsetMs == 1) // 0.5 → 1
        #expect(pickOffset([ClockSample(t0: 0, t1: -1, t2: -1, t3: 0)]).offsetMs == -1) // -1.0
        #expect(pickOffset([ClockSample(t0: 2, t1: 1, t2: 1, t3: 2)]).offsetMs == -1) // -1.0
        #expect(pickOffset([ClockSample(t0: 1, t1: 1, t2: 1, t3: 2)]).offsetMs == 0) // -0.5 → -0 → 0
    }

    @Test func backoffDoublesToCap() {
        var ms = 0
        var seq: [Int] = []
        for _ in 0..<7 { ms = nextBackoff(ms); seq.append(ms) }
        #expect(seq == [1000, 2000, 4000, 8000, 16000, 30000, 30000])
    }

    @Test func tapClockIsMonotonicAndAligned() {
        var wall = 1_000_000.0
        var mono = 10.0
        var clock = TapClock(wallMs: { wall }, monoS: { mono })
        #expect(clock.nowMs() == 1_000_000)
        mono = 10.25
        wall = 0 // the wall clock jumps; taps keep counting from the base
        #expect(clock.nowMs() == 1_000_250)
        wall = 5_000
        mono = 20
        clock.rebase()
        #expect(clock.nowMs() == 5_000)
    }

    @Test func decodesHubRoster() throws {
        let json = #"""
        {"event":{"name":"CX","races":[{"id":"r1","name":"Cat 3"}]},"racers":[{"bib":"101","name":"Ann Lee","race_id":"r1"}],
         "checkpoints":[],"device":{"checkpoint_id":null,"checkpoint_set_at_ms":null},"version":"abc"}
        """#
        let roster = try JSONDecoder().decode(Roster.self, from: Data(json.utf8))
        #expect(roster.event.name == "CX")
        #expect(roster.racers.first?.race_id == "r1")
        #expect(roster.device.checkpoint_set_at_ms == nil)
        let status = try JSONDecoder().decode(Status.self, from: Data(#"""
        {"captures":[{"id":"e1","bib":null,"entered_bib":null,"bib_source":"entered","lap":null,"lap_ms":null,"typical_lap_ms":null,"lap_flag":null,"voided":false}]}
        """#.utf8))
        #expect(status.captures.first?.bib_source == "entered")
    }
}
