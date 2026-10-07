import { describe, expect, it } from "vitest";
import type { Status } from "./api";
import type { Entry } from "./log";
import { captureRows } from "./rows";

const e = (seq: number, kind: Entry["kind"], extra: Partial<Entry>): Entry =>
  ({ id: `e${seq}`, kind, device_seq: seq, prev_hash: "p", hash: "h", ...extra }) as Entry;
const roster = { event: { name: "CX", races: [{ id: "r1", name: "Cat 3 Men" }] }, racers: [{ bib: "101", name: "Ann Lee", race_id: "r1" }], version: "v" };

describe("captureRows", () => {
  it("before a sync: local corrections, roster names, chips, and no lap yet", () => {
    const entries = [e(1, "capture", { captured_at_ms: 1000, bib: "999" }), e(2, "capture", { captured_at_ms: 2000 }),
      e(3, "bib_assignment", { capture_id: "e1", bib: "101" }), e(4, "capture", { captured_at_ms: 3000, bib: "500" }),
      e(5, "capture_void", { capture_id: "e4" })];
    const rows = captureRows(entries, roster, null);
    expect(rows.map((r) => [r.id, r.bib, r.name, r.race, r.chips, r.lap, r.enteredNote])).toEqual([
      ["e2", null, null, null, ["No bib"], null, null],
      ["e1", "101", "Ann Lee", "Cat 3 Men", [], null, "entered: 999"],
    ]);
  });

  it("after a sync: the hub's resolved bib, lap and warning win", () => {
    const entries = [e(1, "capture", { captured_at_ms: 1000 })];
    const status = { captures: [{ id: "e1", bib: "101", entered_bib: null, bib_source: "ruling", lap: 3, lap_ms: 90000, typical_lap_ms: 60000, lap_flag: "long", voided: false }] } satisfies Status;
    const [row] = captureRows(entries, roster, status);
    expect([row.bib, row.name, row.lap, row.lapFlag, row.enteredNote, row.locked]).toEqual(["101", "Ann Lee", 3, "long", "entered: no bib", true]);
  });
});
