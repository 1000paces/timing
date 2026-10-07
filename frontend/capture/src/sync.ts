import { RevokedError, type Api, type Roster, type Status } from "./api";
import { pickOffset, type ClockSample } from "./clock";
import type { CaptureDb } from "./db";
import { unsent } from "./log";

export type SyncState = {
  pending: number; // entries the hub hasn't stored yet
  online: boolean; // the last request reached the hub
  stopped: boolean; // the hub refused our chain: export and see an official
  revoked: boolean; // the hub refused this phone's credential: export and re-pair
  ackSeq: number; // the hub has stored entries up to here
  clockSynced: boolean;
  offsetMs: number | null; // hub time - phone time
  lastSyncAtMs: number | null;
  roster: Roster | null;
  status: Status | null;
  error: string | null;
};

export const BATCH = 500;
const PUSH_EVERY_MS = 5_000;
const CLOCK_EVERY_MS = 60_000;
const STATUS_EVERY_MS = 10_000;
const ROSTER_EVERY_MS = 60_000;

// 1 s, doubling, capped at 30 s.
export const nextBackoff = (previousMs: number) => Math.min(previousMs ? previousMs * 2 : 1000, 30_000);

type Deps = {
  db: CaptureDb;
  api: Api;
  now?: () => number;
  setTimer?: (fn: () => void, ms: number) => unknown;
  clearTimer?: (id: unknown) => void;
};

// Pushes the phone's log to the hub, keeps the clock offset, and pulls the
// roster and the status of this phone's crossings. Never deletes entries.
export function createSync({ db, api, now = Date.now, setTimer = (fn, ms) => setTimeout(fn, ms), clearTimer = (id) => clearTimeout(id as number) }: Deps) {
  let ackSeq = 0;
  let lastSeq = 0;
  let backoffMs = 0;
  let retryTimer: unknown = null;
  let tickTimer: unknown = null;
  let pushing: Promise<void> | null = null;
  const due = { clock: 0, status: 0, roster: 0, push: 0 };
  let halted = false; // stop() was called: no more timers
  let state: SyncState = { pending: 0, online: true, stopped: false, revoked: false, ackSeq: 0, clockSynced: false, offsetMs: null, lastSyncAtMs: null, roster: null, status: null, error: null };
  const listeners = new Set<(s: SyncState) => void>();
  const set = (patch: Partial<SyncState>) => {
    state = { ...state, ...patch };
    listeners.forEach((fn) => fn(state));
  };

  async function countPending() {
    const cursor = await db.transaction("entries").store.openCursor(null, "prev");
    lastSeq = cursor?.value.device_seq ?? 0;
    set({ pending: Math.max(0, lastSeq - ackSeq), ackSeq });
  }

  async function load() {
    ackSeq = ((await db.get("state", "ackSeq")) as number | undefined) ?? 0;
    set({
      stopped: ((await db.get("state", "stopped")) as boolean | undefined) ?? false,
      offsetMs: ((await db.get("state", "offsetMs")) as number | undefined) ?? null,
      clockSynced: (await db.get("state", "offsetMs")) != null,
      lastSyncAtMs: ((await db.get("state", "lastSyncAtMs")) as number | undefined) ?? null,
      roster: ((await db.get("state", "roster")) as Roster | undefined) ?? null,
      status: ((await db.get("state", "status")) as Status | undefined) ?? null,
    });
    await countPending();
  }

  // A revoked phone can never sync again: say so, and stop trying.
  function failed(e: unknown): boolean {
    if (e instanceof RevokedError) {
      set({ revoked: true, online: true, error: e.message });
      return true;
    }
    set({ online: false, error: (e as Error).message });
    return false;
  }

  async function pushOnce() {
    await countPending();
    if (state.stopped || state.revoked) return;
    for (;;) {
      const batch = await unsent(db, ackSeq, BATCH);
      if (!batch.length) break;
      let result;
      try {
        result = await api.push(batch);
      } catch (e) {
        if (failed(e) || halted) return;
        backoffMs = nextBackoff(backoffMs);
        if (retryTimer) clearTimer(retryTimer);
        retryTimer = setTimer(() => void pushNow(), backoffMs);
        return;
      }
      backoffMs = 0;
      if (result.conflict) {
        await db.put("state", true, "stopped");
        set({ stopped: true, online: true });
        return;
      }
      const advanced = result.ackSeq > ackSeq;
      ackSeq = result.ackSeq;
      await db.put("state", ackSeq, "ackSeq");
      await db.put("state", now(), "lastSyncAtMs");
      set({ online: true, error: null, lastSyncAtMs: now() });
      await countPending();
      if (!advanced) break;
    }
    await countPending();
  }

  // One push at a time; a tap during a push is picked up by a follow-up push.
  function pushNow(): Promise<void> {
    if (pushing) return pushing.then(() => pushOnce());
    pushing = pushOnce().finally(() => {
      pushing = null;
    });
    return pushing;
  }

  async function syncClock() {
    const samples: ClockSample[] = [];
    try {
      for (let i = 0; i < 5; i++) {
        const t0 = now();
        const { t1, t2 } = await api.clock(t0);
        samples.push({ t0, t1, t2, t3: now() });
      }
    } catch (e) {
      failed(e);
      return;
    }
    const { offsetMs } = pickOffset(samples);
    await db.put("state", offsetMs, "offsetMs");
    set({ offsetMs, clockSynced: true, online: true });
  }

  async function refreshStatus() {
    try {
      const status = await api.status();
      await db.put("state", status, "status");
      set({ status, online: true });
    } catch (e) {
      failed(e);
    }
  }

  async function refreshRoster() {
    try {
      const roster = await api.roster(state.roster?.version ?? null);
      if (roster) {
        await db.put("state", roster, "roster");
        set({ roster });
      }
      set({ online: true });
    } catch (e) {
      failed(e);
    }
  }

  // One pass of the loop. Whatever happens in it (a storage error, say), the
  // next pass is scheduled — unless stop() was called.
  async function tick() {
    if (halted) return;
    try {
      await step();
    } catch (e) {
      set({ error: (e as Error).message });
    } finally {
      if (!halted) tickTimer = setTimer(() => void tick(), 1000);
    }
  }

  async function step() {
    if (state.revoked) return;
    const t = now();
    if (t >= due.clock) {
      due.clock = t + CLOCK_EVERY_MS;
      await syncClock();
    }
    if (t >= due.roster) {
      due.roster = t + ROSTER_EVERY_MS;
      await refreshRoster();
    }
    if (state.pending > 0 && t >= due.push) {
      due.push = t + PUSH_EVERY_MS;
      await pushNow();
    }
    if (t >= due.status) {
      due.status = t + STATUS_EVERY_MS;
      await refreshStatus();
    }
  }

  return {
    state: () => state,
    subscribe(fn: (s: SyncState) => void) {
      listeners.add(fn);
      return () => listeners.delete(fn);
    },
    load,
    pushNow,
    syncClock,
    refreshStatus,
    refreshRoster,
    // After a tap: count it, and push straight away (status follows).
    async kick() {
      await countPending();
      await pushNow();
      await refreshStatus();
    },
    // Back online: retry everything now instead of waiting out the backoff.
    online() {
      backoffMs = 0;
      due.clock = due.status = due.roster = due.push = 0;
    },
    async start() {
      halted = false;
      await load();
      void tick();
    },
    stop() {
      halted = true;
      if (tickTimer) clearTimer(tickTimer);
      if (retryTimer) clearTimer(retryTimer);
    },
  };
}

export type Sync = ReturnType<typeof createSync>;
