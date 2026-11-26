import Foundation

struct ClockSample: Equatable, Sendable {
    var t0: Int, t1: Int, t2: Int, t3: Int
}

// NTP-style: offset = ((t1 - t0) + (t2 - t3)) / 2; keep the fastest round trip.
// Rounds like JavaScript's Math.round (half up), as the PWA does.
func pickOffset(_ samples: [ClockSample]) -> (offsetMs: Int, rttMs: Int) {
    let measured = samples.map { s in
        (offsetMs: Int((Double(s.t1 - s.t0 + (s.t2 - s.t3)) / 2 + 0.5).rounded(.down)), rttMs: s.t3 - s.t0 - (s.t2 - s.t1))
    }
    return measured.dropFirst().reduce(measured[0]) { best, m in m.rttMs < best.rttMs ? m : best }
}

// 1 s, doubling, capped at 30 s.
func nextBackoff(_ previousMs: Int) -> Int { min(previousMs > 0 ? previousMs * 2 : 1000, 30_000) }
