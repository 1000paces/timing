export function formatElapsed(ms: number | null | undefined): string {
  if (ms == null) return "";
  const tenths = Math.round(ms / 100);
  const totalSeconds = Math.floor(tenths / 10);
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = `${String(totalSeconds % 60).padStart(2, "0")}.${tenths % 10}`;
  return hours > 0 ? `${hours}:${String(minutes).padStart(2, "0")}:${seconds}` : `${minutes}:${seconds}`;
}

export function formatGap(lapsDown: number | null | undefined, ms: number | null | undefined): string {
  if (lapsDown && lapsDown > 0) return `-${lapsDown} lap${lapsDown === 1 ? "" : "s"}`;
  if (ms != null) return `+${formatElapsed(ms)}`;
  return "";
}

export function formatClock(ms: number): string {
  return new Date(ms).toLocaleTimeString([], { hour12: false });
}

export function formatScheduled(ms: number): string {
  return new Date(ms).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
}

// <input type="datetime-local"> uses local time as "YYYY-MM-DDTHH:MM" (":SS" with step=1).
export function toLocalInput(ms: number | null | undefined, { seconds = false } = {}): string {
  if (ms == null) return "";
  const d = new Date(ms);
  const pad = (n: number) => String(n).padStart(2, "0");
  const time = `${pad(d.getHours())}:${pad(d.getMinutes())}${seconds ? `:${pad(d.getSeconds())}` : ""}`;
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${time}`;
}

export function fromLocalInput(value: string): number | null {
  if (!value) return null;
  const ms = new Date(value).getTime();
  return Number.isNaN(ms) ? null : ms;
}

// The start to record from the Start time field, or null when it still shows the
// recorded start (the field can't hold milliseconds, so compare as displayed).
export function startCorrection(value: string, recordedMs: number | null): number | null {
  if (!value || value === toLocalInput(recordedMs, { seconds: true })) return null;
  return fromLocalInput(value);
}
