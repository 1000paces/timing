import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { canonicalJson, digest, genesis } from "./hash";

// Shared with the hub's DeviceHash test: both sides must agree byte for byte.
const vector = JSON.parse(readFileSync(path.resolve(import.meta.dirname, "../../../test/fixtures/files/device_hash_vector.json"), "utf8"));

describe("device log checksum", () => {
  it("sorts keys and omits nulls", () => {
    expect(canonicalJson({ b: 1, a: null, c: "x", d: undefined })).toBe('{"b":1,"c":"x"}');
  });

  it("reproduces the hub's vector", async () => {
    expect(await genesis(vector.device_id)).toBe(vector.genesis);
    for (const e of vector.entries) {
      expect(canonicalJson(e.entry)).toBe(e.canonical);
      expect(await digest(e.entry)).toBe(e.hash);
    }
  });

  // Pinned literally (from before checkpoints existed), as in the hub's DeviceHash test:
  // a finish capture, with or without a null checkpoint_id, hashes exactly as old phones hash it.
  it("hashes a finish capture as it always has", async () => {
    const finish = {
      id: "e1", kind: "capture", device_seq: 1, captured_at_ms: 1000, clock_offset_ms: -25, bib: "101",
      prev_hash: "0388fb626ca89a127847443989334b8c29e17567bc03a7a2ed13effca701a4a1",
    };
    const golden = "4b12d73ab756f7c1d5f7892cd87da2b3d29b95827e5d1a95e3527878ceaefb4e";
    expect(await digest(finish)).toBe(golden);
    expect(await digest({ ...finish, checkpoint_id: null })).toBe(golden);
  });
});
