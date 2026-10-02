import { formatElapsed, formatGap } from "../format";
import type { RaceStandings } from "../queries";

const STATE_LABEL: Record<string, string> = { NOT_STARTED: "not started", IN_PROGRESS: "in progress", FINISH_OPEN: "finish open" };

export function Standings({ race }: { race: RaceStandings }) {
  return (
    <section className="panel" aria-label={race.race.name}>
      <h3>
        {race.race.name} — {STATE_LABEL[race.state] ?? race.state} — {race.lapCount ? `${race.lapCount} laps` : "lap count not set"}
      </h3>
      <table>
        <thead>
          <tr>
            <th className="num">#</th>
            <th>Bib</th>
            <th>Name</th>
            <th>Status</th>
            <th className="num">Laps</th>
            <th className="num">Time</th>
            <th className="num">Gap</th>
          </tr>
        </thead>
        <tbody>
          {race.rows.map((row) => (
            <tr key={row.bib}>
              <td className="num">{row.place ?? "–"}</td>
              <td>{row.bib}</td>
              <td>{row.name}</td>
              <td data-testid="rider-status">{row.status.toLowerCase()}</td>
              <td className="num">{row.laps}</td>
              <td className="num">{formatElapsed(row.elapsedMs)}</td>
              <td className="num">{formatGap(row.gapLapsDown, row.gapMs)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}
