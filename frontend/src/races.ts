import { formatClock, formatElapsed } from "./format";

export type StartRow = { id: string; name: string; scheduledAtMs: number | null; startAtMs: number | null };

// Races in order of their start group's scheduled time, then name. Waves are
// formed by hand on the Start screen: select races, press Start, repeat.
export function sortRaces<T extends StartRow>(rows: T[]): T[] {
  return [...rows].sort(
    (a, b) => (a.scheduledAtMs ?? Infinity) - (b.scheduledAtMs ?? Infinity) || a.name.localeCompare(b.name),
  );
}

const GENDER_LABEL: Record<string, string> = { men: "Men", women: "Women", open: "Open" };

// Same rule as Race#default_name on the hub.
export function defaultRaceName(category: string | null, ageGroup: string | null, gender: string): string {
  return [category, ageGroup, GENDER_LABEL[gender]].map((part) => part?.trim()).filter(Boolean).join(" ");
}

type CohortRace = { name: string; scheduledAtMs: number; expectedLaps: number | null; finishWithLeader: boolean };

// Finish-with-leader races at the same scheduled start share one lap count, so
// their expected laps should agree.
export function cohortLapWarnings(races: CohortRace[]): string[] {
  const cohorts = new Map<number, CohortRace[]>();
  for (const race of races.filter((r) => r.finishWithLeader)) {
    cohorts.set(race.scheduledAtMs, [...(cohorts.get(race.scheduledAtMs) ?? []), race]);
  }
  return [...cohorts.values()]
    .filter((cohort) => new Set(cohort.map((r) => r.expectedLaps)).size > 1)
    .map((cohort) => {
      const names = cohort.map((r) => r.name);
      const list = names.length > 2 ? `${names.slice(0, -1).join(", ")} and ${names.at(-1)}` : names.join(" and ");
      return `${list} finish together but expect different laps (${cohort.map((r) => r.expectedLaps ?? "none").join(", ")})`;
    });
}

// A review-queue line for a crossing with no bib or an unregistered one: its
// time of day, and how long after the latest race start before it.
export function unassignedLabel(item: { bib: string | null; atMs: number }, startsMs: number[]): string {
  const what = item.bib ? `Unknown rider: bib ${item.bib}` : "No bib";
  const start = Math.max(...startsMs.filter((s) => s <= item.atMs));
  const parts = [what, formatClock(item.atMs)];
  if (Number.isFinite(start)) parts.push(`+${formatElapsed(item.atMs - start)}`);
  return parts.join(" · ");
}
