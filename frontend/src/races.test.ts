import { describe, expect, it } from "vitest";
import { sortRaces } from "./races";

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
