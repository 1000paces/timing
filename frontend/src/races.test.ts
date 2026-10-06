import { describe, expect, it } from "vitest";
import { sortRaces, statusLabel, unassignedLabel } from "./races";

describe("sortRaces", () => {
  it("orders by scheduled start time, then race name; unscheduled races last", () => {
    const rows = [
      { id: "1", name: "Women Open", scheduledAtMs: 18_00, startAtMs: null },
      { id: "2", name: "Juniors", scheduledAtMs: null, startAtMs: null },
      { id: "3", name: "Elite Men", scheduledAtMs: 19_00, startAtMs: null },
      { id: "4", name: "Masters 35+", scheduledAtMs: 18_00, startAtMs: null },
    ];
    expect(sortRaces(rows).map((r) => r.name)).toEqual(["Masters 35+", "Women Open", "Elite Men", "Juniors"]);
  });
});

import { cohortLapWarnings, defaultRaceName } from "./races";

describe("defaultRaceName", () => {
  it("joins category, age group and gender, skipping blanks (same rule as the hub)", () => {
    expect(defaultRaceName("Cat 3", "Masters 35+", "men")).toBe("Cat 3 Masters 35+ Men");
    expect(defaultRaceName("Novice", null, "women")).toBe("Novice Women");
    expect(defaultRaceName(" ", "", "open")).toBe("Open");
  });
});

describe("cohortLapWarnings", () => {
  const race = (name: string, scheduledAtMs: number, expectedLaps: number | null, finishWithLeader = true) => ({
    name,
    scheduledAtMs,
    expectedLaps,
    finishWithLeader,
  });

  it("flags finish-with-leader races at one scheduled start with different expected laps", () => {
    const warnings = cohortLapWarnings([race("A", 1, 5), race("B", 1, 4), race("C", 1, 3, false), race("D", 2, 9)]);
    expect(warnings).toEqual(["A and B finish together but expect different laps (5, 4)"]);
    expect(cohortLapWarnings([race("A", 1, 5), race("B", 1, 5)])).toEqual([]);
  });
});

describe("unassignedLabel", () => {
  const at = (h: number, m: number, sec: number) => new Date(2026, 9, 18, h, m, sec).getTime();
  const starts = [at(10, 0, 0), at(10, 0, 30), at(11, 0, 0)];

  it("shows time of day and elapsed since the latest start before the crossing", () => {
    expect(unassignedLabel({ bib: null, atMs: at(10, 23, 30) }, starts)).toBe("No bib · 10:23:30 · +23:00.0");
    expect(unassignedLabel({ bib: "400", atMs: at(11, 5, 0) }, starts)).toBe("Unknown racer: bib 400 · 11:05:00 · +5:00.0");
  });

  it("omits elapsed before any start", () => {
    expect(unassignedLabel({ bib: null, atMs: at(9, 0, 0) }, starts)).toBe("No bib · 09:00:00");
  });
});

describe("statusLabel", () => {
  it("capitalises racing statuses and keeps official ones upper case", () => {
    expect(["FINISHED", "RACING", "PULLED", "DNF", "DNS", "DSQ"].map(statusLabel)).toEqual(["Finished", "Racing", "Pulled", "DNF", "DNS", "DSQ"]);
  });
});
