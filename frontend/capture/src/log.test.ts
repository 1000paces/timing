import "fake-indexeddb/auto";
import { describe, expect, it } from "vitest";
import { openCaptureDb } from "./db";
import { digest, genesis } from "./hash";
import { allEntries, appendBibAssignment, appendCapture, appendLocation, appendVoid, canUnpair, startNewPairing, unsent } from "./log";

let n = 0;
const fresh = async () => {
  const db = await openCaptureDb(`test-${n++}`);
  await db.put("pairing", { deviceId: "dev-1", credential: "c", eventId: "e", name: "Phone" }, "pairing");
  return db;
};

describe("the phone's log", () => {
  it("stamps a capture with its checkpoint, and logs location changes", async () => {
    const db = await fresh();
    const capture = await appendCapture(db, { atMs: 1_000, offsetMs: 0, bib: "7", checkpointId: "a1" });
    expect(capture.checkpoint_id).toBe("a1");
    const finish = await appendCapture(db, { atMs: 2_000, offsetMs: 0, bib: "7", checkpointId: null });
    expect("checkpoint_id" in finish).toBe(false); // omitted, so it hashes as before
    const moved = await appendLocation(db, "a2", 3_000, 0);
    expect([moved.kind, moved.checkpoint_id, moved.captured_at_ms]).toEqual(["location", "a2", 3_000]);
  });

  it("numbers entries from 1 and chains them from the device's genesis", async () => {
    const db = await fresh();
    const a = await appendCapture(db, { atMs: 1000, offsetMs: -20, bib: "101" });
    const b = await appendCapture(db, { atMs: 2000, offsetMs: null, bib: "" });
    const fix = await appendBibAssignment(db, b.id, " 102 ");
    const voided = await appendVoid(db, a.id);
    expect([a, b, fix, voided].map((e) => e.device_seq)).toEqual([1, 2, 3, 4]);
    expect(a.prev_hash).toBe(await genesis("dev-1"));
    expect(b.prev_hash).toBe(a.hash);
    const { hash, ...rest } = voided;
    expect(hash).toBe(await digest(rest));
    expect(b).not.toHaveProperty("bib"); // blank bib = no bib
    expect(b).not.toHaveProperty("clock_offset_ms"); // Review Focus 3: no offset before a clock sync
    expect(fix.bib).toBe("102");
    expect(voided).toMatchObject({ kind: "capture_void", capture_id: a.id });
  });

  it("concurrent taps still form one chain", async () => {
    const db = await fresh();
    const taps = await Promise.all([1, 2, 3].map((i) => appendCapture(db, { atMs: i, offsetMs: 0, bib: String(i) })));
    expect(taps.map((t) => t.device_seq).sort()).toEqual([1, 2, 3]);
    const entries = await allEntries(db);
    for (let i = 1; i < entries.length; i++) expect(entries[i].prev_hash).toBe(entries[i - 1].hash);
  });

  it("lists what hasn't been sent, and refuses unpairing until everything has", async () => {
    const db = await fresh();
    for (const bib of ["1", "2", "3"]) await appendCapture(db, { atMs: 1, offsetMs: 0, bib });
    expect((await unsent(db, 1, 500)).map((e) => e.device_seq)).toEqual([2, 3]);
    expect((await unsent(db, 0, 2)).map((e) => e.device_seq)).toEqual([1, 2]);
    expect(canUnpair(3, 2)).toBe(false);
    expect(canUnpair(3, 3)).toBe(true);
  });

  // Review I4: re-pairing keeps the old log (archived), never deletes it.
  it("re-pairing archives the old log and starts a fresh one", async () => {
    const db = await fresh();
    await appendCapture(db, { atMs: 1, offsetMs: 0, bib: "1" });
    await startNewPairing(db, { deviceId: "dev-2", credential: "c2", eventId: "e2", name: "Phone" });
    expect(await allEntries(db)).toEqual([]);
    const archived = await db.getAll("archive");
    expect(archived).toHaveLength(1);
    expect(archived[0].pairing?.deviceId).toBe("dev-1");
    expect(archived[0].entries.map((e: { bib?: string }) => e.bib)).toEqual(["1"]);
    expect((await appendCapture(db, { atMs: 2, offsetMs: 0, bib: "2" })).device_seq).toBe(1);
  });
});
