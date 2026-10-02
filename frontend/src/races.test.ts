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
