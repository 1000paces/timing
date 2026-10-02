export type StartRow = { id: string; name: string; scheduledAtMs: number | null; startAtMs: number | null };

// Races in order of their start group's scheduled time, then name. Waves are
// formed by hand on the Start screen: select races, press Start, repeat.
export function sortRaces<T extends StartRow>(rows: T[]): T[] {
  return [...rows].sort(
    (a, b) => (a.scheduledAtMs ?? Infinity) - (b.scheduledAtMs ?? Infinity) || a.name.localeCompare(b.name),
  );
}
