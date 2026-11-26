import Foundation
import QuartzCore

// The tap time: wall-clock ms, advanced by the monotonic clock so a wall-clock
// change mid-session can't make taps jump. Rebased when the app comes back to
// the foreground.
struct TapClock {
    private let wallMs: () -> Double
    private let monoS: () -> Double
    private var baseWall: Double
    private var baseMono: Double

    init(wallMs: @escaping () -> Double = { Date().timeIntervalSince1970 * 1000 }, monoS: @escaping () -> Double = CACurrentMediaTime) {
        self.wallMs = wallMs
        self.monoS = monoS
        baseWall = wallMs()
        baseMono = monoS()
    }

    mutating func rebase() {
        baseWall = wallMs()
        baseMono = monoS()
    }

    func nowMs() -> Double { baseWall + (monoS() - baseMono) * 1000 }
}
