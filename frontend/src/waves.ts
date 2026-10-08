import type { RaceStandings, Row } from "./queries";

export type WaveRow = Row & { raceId: string; raceName: string; position: number | null };
export type Wave = { scheduledAtMs: number | null; raceNames: string[]; rows: WaveRow[] };

const OUT = new Set(["DNF", "DNS", "DSQ"]);

// Results by wave (races sharing a scheduled start), each in order on the road:
// most laps, then whoever crossed the line first. A racer's last crossing is
// their race's start plus their elapsed time, so staggered starts compare fairly.
export function groupWaves(races: (RaceStandings & { scheduledAtMs: number | null })[]): Wave[] {
  const groups = new Map<number | null, typeof races>();
  for (const race of races) groups.set(race.scheduledAtMs, [...(groups.get(race.scheduledAtMs) ?? []), race]);
  return [...groups.entries()]
    .sort(([a], [b]) => (a ?? Infinity) - (b ?? Infinity))
    .map(([scheduledAtMs, group]) => {
      const rows = group.flatMap((race) =>
        race.rows.map((row) => ({
          ...row,
          raceId: race.race.id,
          raceName: race.race.name,
          crossedAt: race.startAtMs != null && row.elapsedMs != null ? race.startAtMs + row.elapsedMs : Infinity,
          placed: row.laps > 0 && !OUT.has(row.status),
        })),
      );
      rows.sort((a, b) => Number(b.placed) - Number(a.placed) || b.laps - a.laps || a.crossedAt - b.crossedAt ||
        a.bib.localeCompare(b.bib, undefined, { numeric: true }));
      let position = 0;
      return {
        scheduledAtMs,
        raceNames: group.map((race) => race.race.name),
        rows: rows.map(({ crossedAt: _crossedAt, placed, ...row }) => ({ ...row, position: placed ? ++position : null })),
      };
    });
}
