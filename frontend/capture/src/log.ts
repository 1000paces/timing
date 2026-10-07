import type { CaptureDb, Pairing } from "./db";
import { digest, genesis, uuidv7 } from "./hash";

export type Entry = {
  id: string;
  kind: "capture" | "bib_assignment" | "capture_void";
  device_seq: number;
  prev_hash: string;
  hash: string;
  captured_at_ms?: number;
  clock_offset_ms?: number;
  bib?: string;
  capture_id?: string;
};

type Body = Omit<Entry, "id" | "device_seq" | "prev_hash" | "hash">;

// Appends run one at a time, so concurrent taps still form one chain.
let queue: Promise<unknown> = Promise.resolve();

async function append(db: CaptureDb, body: Body): Promise<Entry> {
  const run = queue.then(async () => {
    const pairing = await db.get("pairing", "pairing");
    if (!pairing) throw new Error("This phone isn't paired");
    const cursor = await db.transaction("entries").store.openCursor(null, "prev");
    const last = cursor?.value;
    const draft: Omit<Entry, "hash"> = {
      id: uuidv7(),
      device_seq: (last?.device_seq ?? 0) + 1,
      prev_hash: last?.hash ?? (await genesis(pairing.deviceId)),
      ...Object.fromEntries(Object.entries(body).filter(([, v]) => v != null && v !== "")),
    } as Omit<Entry, "hash">;
    const entry = { ...draft, hash: await digest(draft) } as Entry;
    // add (not put): a second writer for the same seq fails instead of overwriting.
    // "strict": the tap is flushed to disk before we confirm it.
    const tx = db.transaction("entries", "readwrite", { durability: "strict" });
    await tx.store.add(entry);
    await tx.done;
    return entry;
  });
  queue = run.catch(() => undefined);
  return run;
}

// Resolves only after the entry is committed to the phone's storage.
export function appendCapture(db: CaptureDb, tap: { atMs: number; offsetMs: number | null; bib: string }): Promise<Entry> {
  return append(db, { kind: "capture", captured_at_ms: Math.round(tap.atMs), clock_offset_ms: tap.offsetMs ?? undefined, bib: tap.bib.trim() || undefined });
}

export const appendBibAssignment = (db: CaptureDb, captureId: string, bib: string) =>
  append(db, { kind: "bib_assignment", capture_id: captureId, bib: bib.trim() });

export const appendVoid = (db: CaptureDb, captureId: string) => append(db, { kind: "capture_void", capture_id: captureId });

export const allEntries = (db: CaptureDb) => db.getAll("entries");

export const unsent = (db: CaptureDb, ackSeq: number, limit: number) =>
  db.getAll("entries", IDBKeyRange.lowerBound(ackSeq, true), limit);

// The phone never drops entries the hub hasn't stored.
export const canUnpair = (lastSeq: number, ackSeq: number) => ackSeq >= lastSeq;

// Re-pairing (a new event, or after a revoke) never deletes the old log: it is
// archived on the phone, then a fresh log and sync state begin.
export async function startNewPairing(db: CaptureDb, next: Pairing): Promise<void> {
  const tx = db.transaction(["pairing", "entries", "state", "archive"], "readwrite");
  const previous = await tx.objectStore("pairing").get("pairing");
  const entries = await tx.objectStore("entries").getAll();
  if (previous || entries.length) await tx.objectStore("archive").add({ pairing: previous ?? null, entries, archivedAtMs: Date.now() });
  await tx.objectStore("entries").clear();
  await tx.objectStore("state").clear();
  await tx.objectStore("pairing").put(next, "pairing");
  await tx.done;
}
