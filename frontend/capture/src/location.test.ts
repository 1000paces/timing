import { describe, expect, it } from "vitest";
import { locationName, shouldAdopt } from "./location";

const roster = { checkpoints: [{ id: "a1", name: "Aid 1" }] } as never;

describe("shouldAdopt", () => {
  it("takes the hub's location when an official moved the phone after its own last change", () => {
    expect(shouldAdopt({ checkpointId: null, changedAtMs: 1_000 }, { checkpoint_id: "a1", checkpoint_set_at_ms: 2_000 })).toBe(true);
  });
  it("keeps the phone's when its change is newer, or the hub already agrees", () => {
    expect(shouldAdopt({ checkpointId: null, changedAtMs: 3_000 }, { checkpoint_id: "a1", checkpoint_set_at_ms: 2_000 })).toBe(false);
    expect(shouldAdopt({ checkpointId: "a1", changedAtMs: 1_000 }, { checkpoint_id: "a1", checkpoint_set_at_ms: 2_000 })).toBe(false);
  });
  it("a phone that never chose takes whatever the hub has set, and ignores a hub that never set one", () => {
    expect(shouldAdopt(null, { checkpoint_id: "a1", checkpoint_set_at_ms: 2_000 })).toBe(true);
    expect(shouldAdopt(null, { checkpoint_id: null, checkpoint_set_at_ms: null })).toBe(false);
  });
});

describe("locationName", () => {
  it("names the finish and known checkpoints", () => {
    expect(locationName(null, roster)).toBe("Finish");
    expect(locationName("a1", roster)).toBe("Aid 1");
    expect(locationName("zz", roster)).toBe("Unknown checkpoint");
  });
});
