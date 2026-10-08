import { describe, expect, it } from "vitest";
import { DEFAULT_START_SORT, sortRaces, startSortFromSearch, startSortToSearch, statusLabel, unassignedLabel, type StartSort } from "./races";

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

  const rows = [
    { id: "1", name: "Women Open", scheduledAtMs: 18_00, startAtMs: 18_05 },
    { id: "2", name: "Juniors", scheduledAtMs: null, startAtMs: null },
    { id: "3", name: "Elite Men", scheduledAtMs: 19_00, startAtMs: null },
    { id: "4", name: "Masters 35+", scheduledAtMs: 18_00, startAtMs: 18_01 },
    { id: "5", name: "Cat 10", scheduledAtMs: 19_00, startAtMs: null },
    { id: "6", name: "Cat 9", scheduledAtMs: 19_00, startAtMs: null },
  ];
  const names = (sort: StartSort) => sortRaces(rows, sort).map((r) => r.name);

  it("sorts by race name, numbers in order, either way", () => {
    expect(names({ key: "race", dir: "asc" })).toEqual(["Cat 9", "Cat 10", "Elite Men", "Juniors", "Masters 35+", "Women Open"]);
    expect(names({ key: "race", dir: "desc" })).toEqual(["Women Open", "Masters 35+", "Juniors", "Elite Men", "Cat 10", "Cat 9"]);
  });

  it("sorts by scheduled time either way; unscheduled races stay last; ties by name", () => {
    expect(names({ key: "scheduled", dir: "desc" })).toEqual(["Cat 9", "Cat 10", "Elite Men", "Masters 35+", "Women Open", "Juniors"]);
  });

  it("sorts by status: not started first (by schedule), then started by start time", () => {
    expect(names({ key: "status", dir: "asc" })).toEqual(["Cat 9", "Cat 10", "Elite Men", "Juniors", "Masters 35+", "Women Open"]);
    expect(names({ key: "status", dir: "desc" })).toEqual(["Women Open", "Masters 35+", "Cat 9", "Cat 10", "Elite Men", "Juniors"]);
  });

  it("keeps the sort in the address", () => {
    expect(startSortFromSearch("?sort=status&dir=desc")).toEqual({ key: "status", dir: "desc" });
    expect(startSortFromSearch("?sort=bogus")).toEqual(DEFAULT_START_SORT);
    expect(startSortToSearch({ key: "race", dir: "asc" })).toBe("?sort=race&dir=asc");
    expect(startSortToSearch(DEFAULT_START_SORT)).toBe("");
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

describe("results race filter in the page address", () => {
  it("reads and writes repeated race ids", async () => {
    const { raceIdsFromSearch, raceIdsToSearch } = await import("./races");
    expect(raceIdsFromSearch("?race=a&race=b")).toEqual(["a", "b"]);
    expect(raceIdsFromSearch("")).toEqual([]);
    expect(raceIdsToSearch(["a", "b"])).toBe("?race=a&race=b");
    expect(raceIdsToSearch([])).toBe("");
  });
});
