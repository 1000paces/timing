import { describe, expect, it } from "vitest";
import { formatElapsed, formatGap, formatScheduled } from "./format";

describe("formatElapsed", () => {
  it("formats minutes, seconds and tenths", () => {
    expect(formatElapsed(61_500)).toBe("1:01.5");
    expect(formatElapsed(0)).toBe("0:00.0");
    expect(formatElapsed(3_600_000)).toBe("1:00:00.0");
    expect(formatElapsed(59_960)).toBe("1:00.0");
  });

  it("is blank for missing values", () => {
    expect(formatElapsed(null)).toBe("");
    expect(formatElapsed(undefined)).toBe("");
  });
});

describe("formatGap", () => {
  it("shows laps down, else the time gap", () => {
    expect(formatGap(1, null)).toBe("-1 lap");
    expect(formatGap(2, null)).toBe("-2 laps");
    expect(formatGap(0, 40_000)).toBe("+0:40.0");
    expect(formatGap(null, null)).toBe("");
  });
});

describe("formatScheduled", () => {
  it("shows a local time of day without seconds", () => {
    const sixPm = new Date(2026, 9, 18, 18, 0, 0).getTime();
    expect(formatScheduled(sixPm)).toBe(new Date(sixPm).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }));
    expect(formatScheduled(sixPm)).not.toMatch(/:\d\d:\d\d/);
  });
});

import { fromLocalInput, startCorrection, toLocalInput } from "./format";

describe("local date-time inputs", () => {
  it("round-trips through the browser's datetime-local format", () => {
    const sixPm = new Date(2026, 9, 18, 18, 0, 0).getTime();
    expect(toLocalInput(sixPm)).toBe("2026-10-18T18:00");
    expect(fromLocalInput("2026-10-18T18:00")).toBe(sixPm);
    expect(fromLocalInput("")).toBeNull();
    expect(toLocalInput(null)).toBe("");
  });
});

describe("start time corrections", () => {
  const recorded = new Date(2026, 9, 18, 18, 0, 23, 481).getTime();

  it("shows the recorded start to the second", () => {
    expect(toLocalInput(recorded, { seconds: true })).toBe("2026-10-18T18:00:23");
  });

  it("leaves an untouched start alone, even though the field drops milliseconds", () => {
    expect(startCorrection(toLocalInput(recorded, { seconds: true }), recorded)).toBeNull();
  });

  it("returns the new start when the field was changed", () => {
    expect(startCorrection("2026-10-18T18:00:30", recorded)).toBe(new Date(2026, 9, 18, 18, 0, 30).getTime());
    expect(startCorrection("2026-10-18T18:01", null)).toBe(new Date(2026, 9, 18, 18, 1).getTime());
    expect(startCorrection("", recorded)).toBeNull();
  });
});
