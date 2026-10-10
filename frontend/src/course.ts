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

export type Board = {
  points: { id: string | null; name: string; passed: number; toCome: number; cutoffAtMs: number | null }[];
  out: { bib: string; name: string; lastName: string; lastAtMs: number | null; nextName: string; etaMs: number | null; late: boolean }[];
};

// The lower median: with an even count, the faster of the middle two.
const median = (xs: number[]) => {
  const s = [...xs].sort((a, b) => a - b);
  return s.length ? s[Math.floor((s.length - 1) / 2)] : null;
};

// Where everyone is on a course race: per point, how many have passed and are
// still to come; then each rider still out, furthest first, with an ETA at
// their next point from the field's median time on that segment.
export function courseBoard(race: RaceStandings, checkpoints: CheckpointInfo[], nowMs: number, finishCutoffAtMs: number | null = null): Board {
  const names = [...checkpoints.map((c) => c.name), "Finish"];
  const ids = [...checkpoints.map((c) => c.id), null];
  const cutoffs = [...checkpoints.map((c) => c.cutoffAtMs), finishCutoffAtMs];
  const racing = race.rows.filter((r) => r.status === "RACING");
  const points = ids.map((id, i) => {
    const passed = race.rows.filter((r) => r.splits[i]?.atMs != null).length;
    return { id, name: names[i], passed, toCome: racing.filter((r) => r.splits[i]?.atMs == null).length, cutoffAtMs: cutoffs[i] };
  });
  const segment = (i: number) =>
    median(race.rows.flatMap((r) => {
      const to = r.splits[i]?.atMs;
      const from = i === 0 ? race.startAtMs : r.splits[i - 1]?.atMs;
      return to != null && from != null ? [to - from] : [];
    }));
  const out = racing.map((r) => {
    const last = r.splits.reduce((acc, s, i) => (s.atMs != null ? i : acc), -1);
    const lastAtMs = last >= 0 ? r.splits[last].atMs : race.startAtMs;
    const next = Math.min(last + 1, ids.length - 1);
    const seg = segment(next);
    const etaMs = lastAtMs != null && seg != null ? lastAtMs + seg : null;
    return { bib: r.bib, name: r.name, lastName: last >= 0 ? names[last] : "Start", lastAtMs, nextName: names[next], etaMs, late: etaMs != null && nowMs > etaMs, _last: last };
  });
  out.sort((a, b) => b._last - a._last || (a.lastAtMs ?? 0) - (b.lastAtMs ?? 0));
  return { points, out: out.map(({ _last, ...rest }) => rest) };
}
