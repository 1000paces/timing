import { afterEach, describe, expect, it, vi } from "vitest";
import { hubApi, RevokedError } from "./api";

const device = () => ({ deviceId: "d", credential: "c", offsetMs: null });

describe("hub api", () => {
  afterEach(() => vi.unstubAllGlobals());

  // Review I5: a hung request gives up instead of stalling sync.
  it("times out a request that never answers", async () => {
    vi.stubGlobal("fetch", (_url: string, init: RequestInit) =>
      new Promise((_resolve, reject) => init.signal?.addEventListener("abort", () => reject(new DOMException("timed out", "TimeoutError")))));
    await expect(hubApi(device, { timeoutMs: 30 }).status()).rejects.toThrow();
  });

  it("a 401 is a RevokedError", async () => {
    vi.stubGlobal("fetch", async () => new Response("{}", { status: 401 }));
    await expect(hubApi(device).status()).rejects.toBeInstanceOf(RevokedError);
  });
});
