import { openDB, type DBSchema, type IDBPDatabase } from "idb";
import type { Entry } from "./log";

export type Pairing = { deviceId: string; credential: string; eventId: string; name: string };

interface CaptureSchema extends DBSchema {
  pairing: { key: string; value: Pairing };
  entries: { key: number; value: Entry };
  state: { key: string; value: unknown };
  archive: { key: number; value: { pairing: Pairing | null; entries: Entry[]; archivedAtMs: number } };
}

export type CaptureDb = IDBPDatabase<CaptureSchema>;

// The phone's own storage: its pairing, its append-only log (by device_seq),
// and sync state (ack, clock, roster, status).
export function openCaptureDb(name = "timing-capture"): Promise<CaptureDb> {
  return openDB<CaptureSchema>(name, 2, {
    upgrade(db, oldVersion) {
      if (oldVersion < 1) {
        db.createObjectStore("pairing");
        db.createObjectStore("entries", { keyPath: "device_seq" });
        db.createObjectStore("state");
      }
      // Logs from earlier pairings, kept rather than deleted.
      if (oldVersion < 2) db.createObjectStore("archive", { autoIncrement: true });
    },
  });
}
