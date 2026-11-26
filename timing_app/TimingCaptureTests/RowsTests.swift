import Foundation
import Testing
@testable import TimingCapture

func e(_ seq: Int, _ kind: Entry.Kind, at: Int? = nil, bib: String? = nil, captureId: String? = nil) -> Entry {
    Entry(id: "e\(seq)", kind: kind, device_seq: seq, prev_hash: "p", hash: "h", captured_at_ms: at, bib: bib, capture_id: captureId)
}

let rowsRoster = makeRoster(races: [.init(id: "r1", name: "Cat 3 Men")], racers: [.init(bib: "101", name: "Ann Lee", race_id: "r1")])

func hubCapture(_ id: String, bib: String?, entered: String?, source: String, lap: Int?, lapMs: Int?, typical: Int?, flag: String?) -> Status.Capture {
    Status.Capture(id: id, bib: bib, entered_bib: entered, bib_source: source, lap: lap, lap_ms: lapMs, typical_lap_ms: typical, lap_flag: flag, voided: false)
}

@Suite struct RowsTests {
    @Test func beforeSync() {
        let entries = [e(1, .capture, at: 1000, bib: "999"), e(2, .capture, at: 2000), e(3, .bib_assignment, bib: "101", captureId: "e1"),
                       e(4, .capture, at: 3000, bib: "500"), e(5, .capture_void, captureId: "e4")]
        let rows = captureRows(entries, roster: rowsRoster, status: nil)
        #expect(rows.map(\.id) == ["e2", "e1"])
        #expect(rows[0].bib == nil && rows[0].name == nil && rows[0].race == nil && rows[0].chips == [.noBib] && rows[0].lap == nil && rows[0].enteredNote == nil)
        #expect(rows[1].bib == "101" && rows[1].name == "Ann Lee" && rows[1].race == "Cat 3 Men" && rows[1].chips.isEmpty)
        #expect(rows[1].lap == nil && rows[1].enteredNote == "entered: 999")
    }

    @Test func unknownBibOnlyOnceRosterLoaded() {
        let entries = [e(1, .capture, at: 1000, bib: "777")]
        #expect(captureRows(entries, roster: rowsRoster, status: nil)[0].chips == [.unknownBib])
        #expect(captureRows(entries, roster: nil, status: nil)[0].chips.isEmpty)
    }

    @Test func afterSyncHubWins() {
        let entries = [e(1, .capture, at: 1000)]
        let status = Status(captures: [hubCapture("e1", bib: "101", entered: nil, source: "ruling", lap: 3, lapMs: 90000, typical: 60000, flag: "long")])
        let row = captureRows(entries, roster: rowsRoster, status: status)[0]
        #expect(row.bib == "101" && row.name == "Ann Lee" && row.lap == 3 && row.lapFlag == .long)
        #expect(row.enteredNote == "entered: no bib" && row.locked)
        #expect(lapFlagLabel(.long) == "Long lap" && lapFlagLabel(.missed) == "Missed lap?" && lapFlagLabel(.short) == "Short lap")
    }

    @Test func hubVoidHides() {
        var voided = hubCapture("e1", bib: "1", entered: "1", source: "entered", lap: nil, lapMs: nil, typical: nil, flag: nil)
        voided.voided = true
        #expect(captureRows([e(1, .capture, at: 1, bib: "1")], roster: nil, status: Status(captures: [voided])).isEmpty)
    }

    // A correction made offline shows straight away, even on a crossing the hub already knows.
    @Test func unsentCorrectionWins() {
        let entries = [e(1, .capture, at: 1000, bib: "12"), e(2, .bib_assignment, bib: "21", captureId: "e1")]
        let status = Status(captures: [hubCapture("e1", bib: "12", entered: "12", source: "entered", lap: 1, lapMs: 1, typical: nil, flag: nil)])
        #expect(captureRows(entries, roster: rowsRoster, status: status, ackSeq: 1)[0].bib == "21")
        #expect(captureRows(entries, roster: rowsRoster, status: status, ackSeq: 2)[0].bib == "12") // sent: the hub's view again
    }
}
