import { describe, expect, it } from "vitest";
import { kindLabel, midpoint, positionLabel } from "./racerPanel";

describe("racer panel helpers", () => {
  it("writes positions as ordinals", () => {
    expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 101].map(positionLabel)).toEqual(["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "23rd", "101st"]);
  });

  it("names why a crossing didn't count", () => {
    expect(["DUPLICATE", "BEFORE_START", "AFTER_FINISH", "AFTER_PULL", "LAP"].map(kindLabel)).toEqual(["duplicate", "before start", "after finish", "after pull", null]);
  });

  it("finds the midpoint between two crossings (or a lap after the last)", () => {
    expect(midpoint(1000, 3000)).toBe(2000);
    expect(midpoint(1000, 2001)).toBe(1500);
  });
});
