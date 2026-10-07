import "fake-indexeddb/auto";
import { describe, expect, it } from "vitest";
import type { Api } from "./api";
import { openCaptureDb, type CaptureDb } from "./db";
import { appendCapture, type Entry } from "./log";
import { RevokedError } from "./api";
import { createSync } from "./sync";

let n = 0;
async function setup() {
  const db = await openCaptureDb(`sync-${n++}`);
  await db.put("pairing", { deviceId: "dev-1", credential: "c", eventId: "e", name: "Phone" }, "pairing");
  return db;
}

// A hub that stores whatever continues the chain.
function fakeHub(opts: { fail?: boolean; conflict?: boolean } = {}) {
  const stored: Entry[] = [];
  const api: Api = {
    pair: async () => { throw new Error("unused"); },
    clock: async (t0) => ({ t1: t0 + 50, t2: t0 + 50 }),
    push: async (entries) => {
      if (opts.fail) throw new Error("offline");
      if (opts.conflict) return { conflict: true, ackSeq: stored.length };
      for (const e of entries) if (e.device_seq === stored.length + 1) stored.push(e);
      return { conflict: false, ackSeq: stored.length };
    },
    roster: async () => null,
    status: async () => ({ captures: [] }),
  };
  return { api, stored };
}

const sync = (db: CaptureDb, api: Api) => createSync({ db, api, now: () => 0, setTimer: () => 0, clearTimer: () => {} });

describe("sync", () => {
  it("pushes everything unsent and remembers the ack", async () => {
    const db = await setup();
    for (const bib of ["1", "2", "3"]) await appendCapture(db, { atMs: 1, offsetMs: 0, bib });
    const { api, stored } = fakeHub();
    const s = sync(db, api);
    await s.pushNow();
    expect(stored.map((e) => e.device_seq)).toEqual([1, 2, 3]);
    expect(s.state().pending).toBe(0);
    expect(await db.get("state", "ackSeq")).toBe(3);
  });

  // Review Focus 4: a restart picks up from the stored ack
  it("a restarted app resumes from the stored ack", async () => {
    const db = await setup();
    for (const bib of ["1", "2"]) await appendCapture(db, { atMs: 1, offsetMs: 0, bib });
    const hub = fakeHub();
    await sync(db, hub.api).pushNow();
    await appendCapture(db, { atMs: 2, offsetMs: 0, bib: "3" });
    const restarted = sync(db, hub.api);
    await restarted.load();
    expect(restarted.state().pending).toBe(1);
    await restarted.pushNow();
    expect(hub.stored.map((e) => e.device_seq)).toEqual([1, 2, 3]);
  });

  it("an unreachable hub leaves entries pending and offline", async () => {
    const db = await setup();
    await appendCapture(db, { atMs: 1, offsetMs: 0, bib: "1" });
    const s = sync(db, fakeHub({ fail: true }).api);
    await s.pushNow();
    expect(s.state()).toMatchObject({ pending: 1, online: false, stopped: false });
  });

  it("a chain mismatch stops syncing until re-paired", async () => {
    const db = await setup();
    await appendCapture(db, { atMs: 1, offsetMs: 0, bib: "1" });
    const s = sync(db, fakeHub({ conflict: true }).api);
    await s.pushNow();
    expect(s.state().stopped).toBe(true);
    expect(await db.get("state", "stopped")).toBe(true);
  });

  it("clock sync stores the offset and marks the clock synced", async () => {
    const db = await setup();
    const s = sync(db, fakeHub().api);
    await s.syncClock();
    expect(s.state()).toMatchObject({ clockSynced: true, offsetMs: 50 });
  });

  // Review I2: a revoked phone says so and stops retrying.
  it("a revoked phone is marked revoked and stops retrying", async () => {
    const db = await setup();
    await appendCapture(db, { atMs: 1, offsetMs: 0, bib: "1" });
    const { api } = fakeHub();
    api.push = async () => { throw new RevokedError(); };
    const timers: unknown[] = [];
    const s = createSync({ db, api, now: () => 0, setTimer: (fn) => timers.push(fn), clearTimer: () => {} });
    await s.pushNow();
    expect(s.state().revoked).toBe(true);
    expect(timers).toHaveLength(0);
  });

  // Review M1: the loop survives a failing step, and stops for good when stopped.
  it("the tick loop keeps going after a storage error and stops when told", async () => {
    const db = await setup();
    const { api } = fakeHub();
    let pending: (() => void) | null = null;
    const s = createSync({ db, api, now: () => 0, setTimer: (fn) => { pending = fn as () => void; return 1; }, clearTimer: () => {} });
    await s.start();
    await new Promise((r) => setTimeout(r, 20));
    db.close(); // every storage call now throws
    const fire = pending!;
    pending = null;
    fire();
    await new Promise((r) => setTimeout(r, 20));
    expect(pending).not.toBeNull(); // rescheduled despite the error
    s.stop();
    const late = pending!;
    pending = null;
    late(); // a timer that fires just after stop()
    await new Promise((r) => setTimeout(r, 20));
    expect(pending).toBeNull();
  });
});
