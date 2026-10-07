import { describe, expect, it } from "vitest";
import { initialSearch, rememberSearch, type KeyValueStore } from "./rememberedSearch";

const memory = (): KeyValueStore => {
  const data = new Map<string, string>();
  return { getItem: (k) => data.get(k) ?? null, setItem: (k, v) => void data.set(k, v), removeItem: (k) => void data.delete(k) };
};

describe("remembered filters", () => {
  it("uses the address when it has filters, else the last ones remembered for this screen", () => {
    const store = memory();
    rememberSearch("results:e1", "?race=a", store);
    expect(initialSearch("results:e1", "?race=b", store)).toBe("?race=b");
    expect(initialSearch("results:e1", "", store)).toBe("?race=a");
    expect(initialSearch("results:e2", "", store)).toBe("");
  });

  it("forgets when the filters are cleared, and survives a storage that throws", () => {
    const store = memory();
    rememberSearch("results:e1", "?race=a", store);
    rememberSearch("results:e1", "", store);
    expect(initialSearch("results:e1", "", store)).toBe("");
    const broken: KeyValueStore = { getItem: () => { throw new Error("blocked"); }, setItem: () => { throw new Error("blocked"); }, removeItem: () => {} };
    expect(initialSearch("results:e1", "", broken)).toBe("");
    expect(() => rememberSearch("results:e1", "?race=a", broken)).not.toThrow();
  });
});
