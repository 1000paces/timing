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
