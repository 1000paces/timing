import { describe, expect, it } from "vitest";
import { courseBoard, formatCutoff, parseCutoff } from "./course";

const zone = "America/Los_Angeles";
const start = Date.parse("2026-10-17T15:00:00Z"); // 8:00 am Pacific

describe("parseCutoff", () => {
  it("reads a clock time on the event's day, in its time zone", () => {
    expect(parseCutoff("2:30 pm", start, zone, "2026-10-17")).toEqual({ atMs: Date.parse("2026-10-17T21:30:00Z") });
    expect(parseCutoff("14:30", start, zone, "2026-10-17")).toEqual({ atMs: Date.parse("2026-10-17T21:30:00Z") });
  });
  it("reads an elapsed time from the start", () => {
    expect(parseCutoff("+6:30", start, zone, "2026-10-17")).toEqual({ atMs: start + 6.5 * 3_600_000 });
    expect(parseCutoff("6:30 elapsed", start, zone, "2026-10-17")).toEqual({ atMs: start + 6.5 * 3_600_000 });
  });
  it("empty clears the cutoff; nonsense and elapsed-without-a-start are errors", () => {
    expect(parseCutoff("  ", start, zone, "2026-10-17")).toBeNull();
    expect(parseCutoff("soon", start, zone, "2026-10-17")).toEqual({ error: "Enter a time like 2:30 pm, or +6:30 for elapsed" });
    expect(parseCutoff("+6:30", null, zone, "2026-10-17")).toEqual({ error: "Set a race's scheduled start before entering an elapsed cutoff" });
  });
});

describe("parseCutoff across time zones", () => {
  it("is right on the LA DST days", () => {
    expect(parseCutoff("5:00 am", null, zone, "2026-11-01")).toEqual({ atMs: Date.parse("2026-11-01T13:00:00Z") });
    expect(parseCutoff("5:00 am", null, zone, "2026-03-08")).toEqual({ atMs: Date.parse("2026-03-08T12:00:00Z") });
  });
  it("is right east of UTC", () => {
    expect(parseCutoff("5:00 am", null, "Australia/Sydney", "2026-10-04")).toEqual({ atMs: Date.parse("2026-10-03T18:00:00Z") });
    expect(parseCutoff("14:30", null, "Asia/Tokyo", "2026-10-17")).toEqual({ atMs: Date.parse("2026-10-17T05:30:00Z") });
  });
});

describe("parseCutoff range checks", () => {
  it.each(["13:00 pm", "0:30 am", "25:00", "9:75", "+6:75"])("rejects %s", (text) => {
    expect(parseCutoff(text, start, zone, "2026-10-17")).toEqual({ error: "Enter a time like 2:30 pm, or +6:30 for elapsed" });
  });
  it("accepts the edges", () => {
    expect(parseCutoff("12:00 am", start, zone, "2026-10-17")).toEqual({ atMs: Date.parse("2026-10-17T07:00:00Z") });
    expect(parseCutoff("23:59", start, zone, "2026-10-17")).toEqual({ atMs: Date.parse("2026-10-18T06:59:00Z") });
  });
});

describe("formatCutoff", () => {
  it("shows the clock time in the event's zone", () => {
    expect(formatCutoff(Date.parse("2026-10-17T21:30:00Z"), zone)).toBe("2:30 pm");
  });
});

const checkpoints = [{ id: "a1", name: "Aid 1", position: 1, distanceKm: 30, cutoffAtMs: null }];
const split = (checkpointId: string | null, atMs: number | null) => ({ checkpointId, atMs, elapsedMs: null, segmentMs: null, inserted: false });
const race = {
  startAtMs: 0,
  rows: [
    { bib: "1", name: "Ann", status: "FINISHED", splits: [split("a1", 1_000), split(null, 3_000)] },
    { bib: "2", name: "Bo", status: "RACING", splits: [split("a1", 1_200), split(null, null)] },
    { bib: "3", name: "Cy", status: "RACING", splits: [split("a1", null), split(null, null)] },
  ],
} as never;

describe("courseBoard", () => {
  it("counts who has passed each point and lists riders still out, furthest first, with an ETA at their next point", () => {
    const board = courseBoard(race, checkpoints, 3_000);
    expect(board.points.map((p) => [p.name, p.passed, p.toCome])).toEqual([["Aid 1", 2, 1], ["Finish", 1, 2]]);
    expect(board.out.map((r) => [r.bib, r.lastName, r.nextName, r.etaMs])).toEqual([
      ["2", "Aid 1", "Finish", 1_200 + 2_000],
      ["3", "Start", "Aid 1", 1_100],
    ]);
    expect(board.out.map((r) => r.late)).toEqual([false, true]);
  });
});
