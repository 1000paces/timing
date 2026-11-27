import type { CheckpointInfo, RaceStandings } from "./queries";

// Cutoffs are stored as clock times; officials may type either a clock time
// ("2:30 pm", "14:30") or an elapsed time from the start ("+6:30", "6:30 elapsed").

const ELAPSED = /^\+?\s*(\d{1,2}):(\d{2})(?:\s*elapsed)?$/i;
const CLOCK = /^(\d{1,2}):(\d{2})\s*(am|pm)?$/i;

const BAD_FORMAT = "Enter a time like 2:30 pm, or +6:30 for elapsed";

export type Cutoff = { atMs: number } | { error: string } | null;

export function parseCutoff(text: string, startMs: number | null, timeZone: string, date: string): Cutoff {
  const t = text.trim();
  if (!t) return null;
  const elapsed = t.startsWith("+") || /elapsed$/i.test(t) ? t.match(ELAPSED) : null;
  if (elapsed) {
    if (Number(elapsed[2]) > 59) return { error: BAD_FORMAT };
    if (startMs == null) return { error: "Set a race's scheduled start before entering an elapsed cutoff" };
    return { atMs: startMs + (Number(elapsed[1]) * 60 + Number(elapsed[2])) * 60_000 };
  }
  const clock = t.match(CLOCK);
  if (!clock) return { error: BAD_FORMAT };
  const h = Number(clock[1]);
  if (Number(clock[2]) > 59 || (clock[3] ? h < 1 || h > 12 : h > 23)) return { error: BAD_FORMAT };
  let hour = Number(clock[1]) % (clock[3] ? 12 : 24);
  if (clock[3]?.toLowerCase() === "pm") hour += 12;
  return { atMs: zonedMs(date, hour, Number(clock[2]), timeZone) };
}

// The instant a wall-clock time on a date happens in a time zone.
function zonedMs(date: string, hour: number, minute: number, timeZone: string): number {
  const wall = Date.parse(`${date}T${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}:00Z`);
  const fmt = new Intl.DateTimeFormat("en-US", { timeZone, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" });
  // Zone offset at an instant: what the wall clock shows there, read as UTC, minus the instant.
  const offsetAt = (ms: number) => {
    const parts = fmt.formatToParts(ms).reduce<Record<string, string>>((acc, p) => ({ ...acc, [p.type]: p.value }), {});
    return Date.parse(`${parts.year}-${parts.month}-${parts.day}T${parts.hour}:${parts.minute}:00Z`) - ms;
  };
  // Second pass: the first offset is taken at the wall time read as UTC, which can be across a DST change.
  return wall - offsetAt(wall - offsetAt(wall));
}

export function formatCutoff(atMs: number, timeZone: string): string {
  return new Intl.DateTimeFormat("en-US", { timeZone, hour: "numeric", minute: "2-digit" }).format(atMs).replace(/\s?([AP])M$/, (_, x) => ` ${x.toLowerCase()}m`);
}

// The cutoff with its date when that isn't the event's own day (e.g. past midnight).
export function describeCutoff(atMs: number, timeZone: string, eventDate: string): string {
  const day = new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" }).format(atMs);
  if (day === eventDate) return formatCutoff(atMs, timeZone);
  const date = new Intl.DateTimeFormat("en-US", { timeZone, weekday: "short", month: "short", day: "numeric" }).format(atMs);
  return `${formatCutoff(atMs, timeZone)}, ${date}`;
}

// A saved cutoff is shown as text; while that text is unchanged the saved
// instant is kept as is, not re-read from the text (which drops its date).
export function cutoffToSave(text: string, saved: { text: string; atMs: number | null }, parse: (text: string) => Cutoff): Cutoff {
  if (text === saved.text && saved.atMs != null) return { atMs: saved.atMs };
  return parse(text);
}

export type Board = {
  points: { id: string | null; name: string; passed: number; toCome: number; cutoffAtMs: number | null }[];
  out: { bib: string; name: string; lastName: string; lastAtMs: number | null; nextName: string; etaMs: number | null; late: boolean }[];
};

const median = (xs: number[]) => {
  const s = [...xs].sort((a, b) => a - b);
  return s.length ? (s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1] + s[s.length / 2]) / 2) : null;
};

// As the engine's overdue problem: late once 1.5× the expected segment has gone
// by, the expected segment being the rider's own pace (when distances are known)
// or the median of at least 3 others in the race between the same two points.
const OVERDUE_FACTOR = 1.5;
const MIN_FIELD = 3;

type BoardOptions = { finishCutoffAtMs?: number | null; finishDistanceKm?: number | null };

// Where everyone is on a course race: per point, how many have passed and are
// still to come; then each rider still out, furthest first, with an ETA at
// their next point from the field's median time on that segment. A rider is
// late when overdue (as above) or their next point's cutoff has passed.
export function courseBoard(race: RaceStandings, checkpoints: CheckpointInfo[], nowMs: number, options: BoardOptions = {}): Board {
  const { finishCutoffAtMs = null, finishDistanceKm = null } = options;
  const names = [...checkpoints.map((c) => c.name), "Finish"];
  const ids = [...checkpoints.map((c) => c.id), null];
  const cutoffs = [...checkpoints.map((c) => c.cutoffAtMs), finishCutoffAtMs];
  const kms = [...checkpoints.map((c) => c.distanceKm), finishDistanceKm];
  const at = (r: RaceStandings["rows"][number], i: number) => r.splits.find((s) => s.checkpointId === ids[i])?.atMs ?? null;
  const racing = race.rows.filter((r) => r.status === "RACING");
  const points = ids.map((id, i) => {
    const passed = race.rows.filter((r) => at(r, i) != null).length;
    return { id, name: names[i], passed, toCome: racing.filter((r) => at(r, i) == null).length, cutoffAtMs: cutoffs[i] };
  });
  const times = (i: number) =>
    race.rows.flatMap((r) => {
      const to = at(r, i);
      const from = i === 0 ? race.startAtMs : at(r, i - 1);
      return to != null && from != null ? [to - from] : [];
    });
  const ownPace = (last: number, lastAtMs: number, next: number) => {
    const lastKm = last >= 0 ? kms[last] : null;
    const nextKm = kms[next];
    if (lastKm == null || lastKm <= 0 || nextKm == null || nextKm <= lastKm || race.startAtMs == null) return null;
    return ((lastAtMs - race.startAtMs) * (nextKm - lastKm)) / lastKm;
  };
  const out = racing.map((r) => {
    const last = ids.reduce((acc, _, i) => (at(r, i) != null ? i : acc), -1);
    const lastAtMs = last >= 0 ? at(r, last) : race.startAtMs;
    const next = Math.min(last + 1, ids.length - 1);
    const segment = times(next);
    const seg = median(segment);
    const etaMs = lastAtMs != null && seg != null ? lastAtMs + seg : null;
    const expected = (lastAtMs != null ? ownPace(last, lastAtMs, next) : null) ?? (segment.length >= MIN_FIELD ? seg : null);
    const overdue = lastAtMs != null && expected != null && nowMs > lastAtMs + Math.round(expected * OVERDUE_FACTOR);
    const cutoff = cutoffs[next];
    const late = overdue || (cutoff != null && nowMs > cutoff);
    return { bib: r.bib, name: r.name, lastName: last >= 0 ? names[last] : "Start", lastAtMs, nextName: names[next], etaMs, late, _last: last };
  });
  out.sort((a, b) => b._last - a._last || (a.lastAtMs ?? 0) - (b.lastAtMs ?? 0));
  return { points, out: out.map(({ _last, ...rest }) => rest) };
}
