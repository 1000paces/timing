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

// <input type="datetime-local"> uses local time as "YYYY-MM-DDTHH:MM".
export function toLocalInput(ms: number | null | undefined): string {
  if (ms == null) return "";
  const d = new Date(ms);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function fromLocalInput(value: string): number | null {
  if (!value) return null;
  const ms = new Date(value).getTime();
  return Number.isNaN(ms) ? null : ms;
}
