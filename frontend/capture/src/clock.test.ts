import { describe, expect, it } from "vitest";
import { pickOffset } from "./clock";
import { nextBackoff } from "./sync";

describe("clock and retries", () => {
  it("keeps the offset from the fastest round trip", () => {
    // offset = ((t1 - t0) + (t2 - t3)) / 2 ; rtt = (t3 - t0) - (t2 - t1)
    const slow = { t0: 0, t1: 600, t2: 600, t3: 400 }; // rtt 400, offset 400
    const fast = { t0: 1000, t1: 1550, t2: 1550, t3: 1100 }; // rtt 100, offset 500
    expect(pickOffset([slow, fast])).toEqual({ offsetMs: 500, rttMs: 100 });
  });

  it("backs off 1 s, doubling, to a 30 s cap", () => {
    const seq: number[] = [];
    let ms = 0;
    for (let i = 0; i < 7; i++) seq.push((ms = nextBackoff(ms)));
    expect(seq).toEqual([1000, 2000, 4000, 8000, 16000, 30000, 30000]);
  });
});
