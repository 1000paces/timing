// Cutoffs are stored as clock times; officials may type either a clock time
// ("2:30 pm", "14:30") or an elapsed time from the start ("+6:30", "6:30 elapsed").

const ELAPSED = /^\+?\s*(\d{1,2}):(\d{2})(?:\s*elapsed)?$/i;
const CLOCK = /^(\d{1,2}):(\d{2})\s*(am|pm)?$/i;

export type Cutoff = { atMs: number } | { error: string } | null;

export function parseCutoff(text: string, startMs: number | null, timeZone: string, date: string): Cutoff {
  const t = text.trim();
  if (!t) return null;
  const elapsed = t.startsWith("+") || /elapsed$/i.test(t) ? t.match(ELAPSED) : null;
  if (elapsed) {
    if (startMs == null) return { error: "Set a race's scheduled start before entering an elapsed cutoff" };
    return { atMs: startMs + (Number(elapsed[1]) * 60 + Number(elapsed[2])) * 60_000 };
  }
  const clock = t.match(CLOCK);
  if (!clock) return { error: "Enter a time like 2:30 pm, or +6:30 for elapsed" };
  let hour = Number(clock[1]) % (clock[3] ? 12 : 24);
  if (clock[3]?.toLowerCase() === "pm") hour += 12;
  return { atMs: zonedMs(date, hour, Number(clock[2]), timeZone) };
}

// The instant a wall-clock time on a date happens in a time zone.
function zonedMs(date: string, hour: number, minute: number, timeZone: string): number {
  const guess = Date.parse(`${date}T${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}:00Z`);
  const parts = new Intl.DateTimeFormat("en-US", { timeZone, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" })
    .formatToParts(guess).reduce<Record<string, string>>((acc, p) => ({ ...acc, [p.type]: p.value }), {});
  const shown = Date.parse(`${parts.year}-${parts.month}-${parts.day}T${parts.hour}:${parts.minute}:00Z`);
  return guess - (shown - guess);
}

export function formatCutoff(atMs: number, timeZone: string): string {
  return new Intl.DateTimeFormat("en-US", { timeZone, hour: "numeric", minute: "2-digit" }).format(atMs).replace(/\s?([AP])M$/, (_, x) => ` ${x.toLowerCase()}m`);
}
