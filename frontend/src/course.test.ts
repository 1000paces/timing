import { describe, expect, it } from "vitest";
import { formatCutoff, parseCutoff } from "./course";

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

describe("formatCutoff", () => {
  it("shows the clock time in the event's zone", () => {
    expect(formatCutoff(Date.parse("2026-10-17T21:30:00Z"), zone)).toBe("2:30 pm");
  });
});
