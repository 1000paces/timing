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
});
