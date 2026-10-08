import { describe, expect, it } from "vitest";
import type { RaceStandings, Row } from "./queries";
import { groupWaves } from "./waves";

const row = (bib: string, laps: number, elapsedMs: number | null, status = "RACING", place: number | null = 1): Row =>
  ({ place, bib, name: `Racer ${bib}`, status, laps, elapsedMs, gapLapsDown: null, gapMs: null });
const race = (id: string, startAtMs: number | null, rows: Row[]): RaceStandings =>
  ({ race: { id, name: `Race ${id}` }, state: "IN_PROGRESS", lapCount: null, startAtMs, rows });

describe("groupWaves", () => {
  it("puts races scheduled together in one wave, waves in time order, unscheduled last", () => {
    const waves = groupWaves([
      { ...race("b", null, []), scheduledAtMs: 2_000 },
      { ...race("a", null, []), scheduledAtMs: 1_000 },
      { ...race("c", null, []), scheduledAtMs: 2_000 },
      { ...race("d", null, []), scheduledAtMs: null },
    ]);
    expect(waves.map((w) => [w.scheduledAtMs, w.raceNames])).toEqual([
      [1_000, ["Race a"]],
      [2_000, ["Race b", "Race c"]],
      [null, ["Race d"]],
    ]);
  });

  it("orders the wave as on the road: most laps, then who crossed the line first, whatever their race's start", () => {
    // Race "late" went off 60 s after "early": its 290 s lap ends at 350 s on the road, after early's 300 s.
    const [wave] = groupWaves([
      { ...race("early", 0, [row("1", 1, 300_000), row("2", 0, null)]), scheduledAtMs: 0 },
      { ...race("late", 60_000, [row("3", 1, 290_000), row("4", 2, 700_000)]), scheduledAtMs: 0 },
    ]);
    expect(wave.rows.map((r) => [r.position, r.bib, r.raceName])).toEqual([
      [1, "4", "Race late"],
      [2, "1", "Race early"],
      [3, "3", "Race late"],
      [null, "2", "Race early"], // no laps yet: listed, not placed
    ]);
  });

  it("lists DNF, DNS and DSQ after everyone else, unplaced", () => {
    const [wave] = groupWaves([
      { ...race("a", 0, [row("1", 3, 900_000, "DNF", null), row("2", 1, 300_000), row("3", 0, null, "DNS", null)]), scheduledAtMs: 0 },
    ]);
    expect(wave.rows.map((r) => [r.position, r.bib])).toEqual([[1, "2"], [null, "1"], [null, "3"]]);
  });
});
