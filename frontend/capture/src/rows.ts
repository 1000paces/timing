import type { Roster, Status } from "./api";
import type { Entry } from "./log";

export type Row = {
  id: string;
  atMs: number;
  bib: string | null;
  enteredNote: string | null; // "entered: 999" when the shown bib differs from the tap
  name: string | null;
  race: string | null;
  chips: ("No bib" | "Unknown bib")[];
  lap: number | null; // from the hub, after a sync
  lapMs: number | null;
  typicalLapMs: number | null;
  lapFlag: "missed" | "long" | "short" | null;
  locked: boolean; // an official assigned the bib on the hub
};

// This phone's crossings, newest first: deleted ones dropped; the bib is the
// hub's resolved one once synced, else the phone's latest correction, else
// what was typed.
// ackSeq: the hub has entries up to here; a correction made after that (still on
// the phone) wins over the hub's cached view of the crossing.
export function captureRows(entries: Entry[], roster: Roster | null, status: Status | null, ackSeq = Number.POSITIVE_INFINITY): Row[] {
  const voided = new Set(entries.filter((e) => e.kind === "capture_void").map((e) => e.capture_id));
  const fixEntries = entries.filter((e) => e.kind === "bib_assignment");
  const fixes = new Map(fixEntries.map((e) => [e.capture_id, e.bib ?? null]));
  const unsentFixes = new Map(fixEntries.filter((e) => e.device_seq > ackSeq).map((e) => [e.capture_id, e.bib ?? null]));
  const hub = new Map((status?.captures ?? []).map((c) => [c.id, c]));
  const races = new Map((roster?.event.races ?? []).map((r) => [r.id, r.name]));
  const racers = new Map((roster?.racers ?? []).map((r) => [r.bib, r]));
  return entries
    .filter((e) => e.kind === "capture" && !voided.has(e.id) && !hub.get(e.id)?.voided)
    .sort((a, b) => b.device_seq - a.device_seq)
    .map((e) => {
      const known = hub.get(e.id);
      const entered = e.bib ?? null;
      const bib = unsentFixes.has(e.id) ? unsentFixes.get(e.id)! : known ? known.bib : (fixes.get(e.id) ?? entered);
      const racer = bib ? racers.get(bib) : undefined;
      return {
        id: e.id,
        atMs: e.captured_at_ms ?? 0,
        bib,
        enteredNote: bib !== entered ? `entered: ${entered ?? "no bib"}` : null,
        name: racer?.name ?? null,
        race: racer ? (races.get(racer.race_id) ?? null) : null,
        chips: !bib ? ["No bib"] : racer || !roster ? [] : ["Unknown bib"],
        lap: known?.lap ?? null,
        lapMs: known?.lap_ms ?? null,
        typicalLapMs: known?.typical_lap_ms ?? null,
        lapFlag: known?.lap_flag ?? null,
        locked: known?.bib_source === "ruling",
      };
    });
}
