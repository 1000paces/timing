import { describe, expect, it } from "vitest";
import { courseBoard, cutoffToSave, describeCutoff, formatCutoff, parseCutoff } from "./course";

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

describe("describeCutoff", () => {
  it("is the clock time on the event's day, with the date when it falls on another day", () => {
    expect(describeCutoff(Date.parse("2026-10-17T21:30:00Z"), zone, "2026-10-17")).toBe("2:30 pm");
    expect(describeCutoff(Date.parse("2026-10-18T08:30:00Z"), zone, "2026-10-17")).toBe("1:30 am, Sun, Oct 18");
  });
});

describe("cutoffToSave", () => {
  const parse = (text: string) => parseCutoff(text, start, zone, "2026-10-17");
  const nextDay = Date.parse("2026-10-18T08:30:00Z"); // 1:30 am the day after, shown as "1:30 am"
  it("keeps the saved instant while its text is unchanged", () => {
    expect(cutoffToSave("1:30 am", { text: "1:30 am", atMs: nextDay }, parse)).toEqual({ atMs: nextDay });
  });
  it("reads the text once it changes", () => {
    expect(cutoffToSave("2:30 am", { text: "1:30 am", atMs: nextDay }, parse)).toEqual({ atMs: Date.parse("2026-10-17T09:30:00Z") });
    expect(cutoffToSave("", { text: "1:30 am", atMs: nextDay }, parse)).toBeNull();
    expect(cutoffToSave("2:30 pm", { text: "", atMs: null }, parse)).toEqual({ atMs: Date.parse("2026-10-17T21:30:00Z") });
  });
});

describe("courseBoard", () => {
  it("counts who has passed each point and lists riders still out, furthest first, with an ETA at their next point", () => {
    const board = courseBoard(race, checkpoints, 3_000);
    expect(board.points.map((p) => [p.name, p.passed, p.toCome])).toEqual([["Aid 1", 2, 1], ["Finish", 1, 2]]);
    expect(board.out.map((r) => [r.bib, r.lastName, r.nextName, r.etaMs])).toEqual([
      ["2", "Aid 1", "Finish", 1_200 + 2_000],
      ["3", "Start", "Aid 1", 1_100],
    ]);
  });

  it("finds splits by checkpoint, not by position in the list", () => {
    const shuffled = {
      startAtMs: 0,
      rows: [
        { bib: "1", name: "Ann", status: "FINISHED", splits: [split(null, 3_000), split("a1", 1_000)] },
        { bib: "2", name: "Bo", status: "RACING", splits: [split("a1", 1_200)] },
      ],
    } as never;
    const board = courseBoard(shuffled, checkpoints, 1_500);
    expect(board.points.map((p) => [p.name, p.passed, p.toCome])).toEqual([["Aid 1", 2, 0], ["Finish", 1, 1]]);
    expect(board.out.map((r) => [r.bib, r.lastName, r.etaMs])).toEqual([["2", "Aid 1", 1_200 + 2_000]]);
  });

  it("is late as the engine's overdue rule: 1.5x the field's median segment, once at least 3 have done it", () => {
    // Two riders have reached Aid 1 (median 1,100): too few to call anyone overdue.
    expect(courseBoard(race, checkpoints, 99_000).out.find((r) => r.bib === "3")?.late).toBe(false);
    const field = {
      startAtMs: 0,
      rows: [
        { bib: "1", name: "Ann", status: "RACING", splits: [split("a1", 1_000), split(null, null)] },
        { bib: "2", name: "Bo", status: "RACING", splits: [split("a1", 1_100), split(null, null)] },
        { bib: "3", name: "Cy", status: "RACING", splits: [split("a1", 1_200), split(null, null)] },
        { bib: "4", name: "Di", status: "RACING", splits: [split("a1", null), split(null, null)] },
      ],
    } as never;
    const noKm = [{ ...checkpoints[0], distanceKm: null }];
    expect(courseBoard(field, noKm, 1_650).out.find((r) => r.bib === "4")?.late).toBe(false);
    expect(courseBoard(field, noKm, 1_651).out.find((r) => r.bib === "4")?.late).toBe(true);
  });

  it("uses the rider's own pace when distances are known", () => {
    // Bo reached Aid 1 (30 km) at 1,200: 70 km more should take 2,800; overdue after 4,200 more.
    expect(courseBoard(race, checkpoints, 5_400, { finishDistanceKm: 100 }).out.find((r) => r.bib === "2")?.late).toBe(false);
    expect(courseBoard(race, checkpoints, 5_401, { finishDistanceKm: 100 }).out.find((r) => r.bib === "2")?.late).toBe(true);
  });

  it("is late once the next point's cutoff has passed", () => {
    const withCutoff = [{ ...checkpoints[0], cutoffAtMs: 2_000 }];
    expect(courseBoard(race, withCutoff, 2_000).out.find((r) => r.bib === "3")?.late).toBe(false);
    expect(courseBoard(race, withCutoff, 2_001).out.find((r) => r.bib === "3")?.late).toBe(true);
    expect(courseBoard(race, checkpoints, 3_001, { finishCutoffAtMs: 3_000 }).out.find((r) => r.bib === "2")?.late).toBe(true);
  });
});
