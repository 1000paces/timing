import Foundation

// One crossing as the phone shows it.
struct Row: Identifiable, Equatable {
    enum Chip: String { case noBib = "No bib", unknownBib = "Unknown bib" }
    enum LapFlag: String { case missed, long, short }

    var id: String
    var atMs: Int
    var bib: String?
    var enteredNote: String? // "entered: 999" when the shown bib differs from the tap
    var name: String?
    var race: String?
    var chips: [Chip]
    var lap: Int? // from the hub, after a sync
    var lapMs: Int?
    var typicalLapMs: Int?
    var lapFlag: LapFlag?
    var locked: Bool // an official assigned the bib on the hub
}

func lapFlagLabel(_ flag: Row.LapFlag) -> String {
    switch flag {
    case .missed: return "Missed lap?"
    case .long: return "Long lap"
    case .short: return "Short lap"
    }
}

// This phone's crossings, newest first: deleted ones dropped; the bib is the
// hub's resolved one once synced, else the phone's latest correction, else
// what was typed. ackSeq: the hub has entries up to here; a correction made
// after that (still on the phone) wins over the hub's cached view.
// A port of frontend/capture/src/rows.ts.
func captureRows(_ entries: [Entry], roster: Roster?, status: Status?, ackSeq: Int = .max) -> [Row] {
    let voided = Set(entries.filter { $0.kind == .capture_void }.compactMap(\.capture_id))
    var fixes: [String: String?] = [:]
    var unsentFixes: [String: String?] = [:]
    for fix in entries where fix.kind == .bib_assignment {
        guard let id = fix.capture_id else { continue }
        fixes[id] = .some(fix.bib)
        if fix.device_seq > ackSeq { unsentFixes[id] = .some(fix.bib) }
    }
    let hub = Dictionary((status?.captures ?? []).map { ($0.id, $0) }, uniquingKeysWith: { $1 })
    let races = Dictionary((roster?.event.races ?? []).map { ($0.id, $0.name) }, uniquingKeysWith: { $1 })
    let racers = Dictionary((roster?.racers ?? []).map { ($0.bib, $0) }, uniquingKeysWith: { $1 })
    return entries
        .filter { $0.kind == .capture && !voided.contains($0.id) && hub[$0.id]?.voided != true }
        .sorted { $0.device_seq > $1.device_seq }
        .map { e in
            let known = hub[e.id]
            let entered = e.bib
            let bib: String? = if let fix = unsentFixes[e.id] { fix } else if let known { known.bib } else if let fix = fixes[e.id] { fix } else { entered }
            let racer = bib.flatMap { racers[$0] }
            return Row(
                id: e.id, atMs: e.captured_at_ms ?? 0, bib: bib,
                enteredNote: bib != entered ? "entered: \(entered ?? "no bib")" : nil,
                name: racer?.name, race: racer.flatMap { races[$0.race_id] },
                chips: bib == nil ? [.noBib] : (racer != nil || roster == nil ? [] : [.unknownBib]),
                lap: known?.lap, lapMs: known?.lap_ms, typicalLapMs: known?.typical_lap_ms,
                lapFlag: known?.lap_flag.flatMap(Row.LapFlag.init(rawValue:)),
                locked: known?.bib_source == "ruling")
        }
}
