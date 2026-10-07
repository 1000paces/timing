import type { Entry } from "./log";

export type Roster = { event: { name: string; races: { id: string; name: string }[] }; racers: { bib: string; name: string; race_id: string }[]; version: string };
export type StatusCapture = {
  id: string;
  bib: string | null;
  entered_bib: string | null;
  bib_source: "ruling" | "device" | "entered";
  lap: number | null;
  lap_ms: number | null;
  typical_lap_ms: number | null;
  lap_flag: "missed" | "long" | "short" | null;
  voided: boolean;
};
export type Status = { captures: StatusCapture[] };
export type Paired = { device_id: string; credential: string; event_id: string };

export interface Api {
  pair(token: string, name: string): Promise<Paired>;
  clock(t0: number): Promise<{ t1: number; t2: number }>;
  push(entries: Entry[]): Promise<{ conflict: boolean; ackSeq: number }>;
  roster(version: string | null): Promise<Roster | null>; // null = unchanged
  status(): Promise<Status>;
}

// The hub's /sync/v1 API, as the paired device.
export function hubApi(device: () => { deviceId: string; credential: string; offsetMs: number | null } | null): Api {
  const headers = (extra: Record<string, string> = {}) => {
    const d = device();
    const h: Record<string, string> = { "Content-Type": "application/json", ...extra };
    if (d) h.Authorization = `Device ${d.deviceId}:${d.credential}`;
    if (d?.offsetMs != null) h["X-Clock-Offset-Ms"] = String(d.offsetMs);
    return h;
  };
  const call = async (method: string, path: string, body?: unknown, extra?: Record<string, string>) => {
    const response = await fetch(path, { method, headers: headers(extra), body: body === undefined ? undefined : JSON.stringify(body) });
    if (response.status === 401) throw new Error("This phone has been revoked or unpaired on the hub");
    return response;
  };
  return {
    async pair(token, name) {
      const response = await fetch("/devices/pair", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ token, name }) });
      const body = await response.json();
      if (!response.ok) throw new Error(body.error ?? "Pairing failed");
      return body;
    },
    async clock(t0) {
      const response = await call("POST", "/sync/v1/clock", { t0 });
      if (!response.ok) throw new Error(`clock ${response.status}`);
      return response.json();
    },
    async push(entries) {
      const response = await call("POST", "/sync/v1/push", { entries });
      const body = await response.json();
      if (response.status === 409) return { conflict: true, ackSeq: body.ack_seq };
      if (!response.ok) throw new Error(body.error ?? `push ${response.status}`);
      return { conflict: false, ackSeq: body.ack_seq };
    },
    async roster(version) {
      const response = await call("GET", "/sync/v1/roster", undefined, version ? { "If-None-Match": version } : {});
      if (response.status === 304) return null;
      if (!response.ok) throw new Error(`roster ${response.status}`);
      return response.json();
    },
    async status() {
      const response = await call("GET", "/sync/v1/status");
      if (!response.ok) throw new Error(`status ${response.status}`);
      return response.json();
    },
  };
}
