import Paper from "@mui/material/Paper";
import Stack from "@mui/material/Stack";
import Table from "@mui/material/Table";
import TableBody from "@mui/material/TableBody";
import TableCell from "@mui/material/TableCell";
import TableHead from "@mui/material/TableHead";
import TableRow from "@mui/material/TableRow";
import Typography from "@mui/material/Typography";
import { courseBoard, formatCutoff } from "../course";
import { formatClock } from "../format";
import type { CheckpointInfo, RaceStandings, Row } from "../queries";

type Props = { race: RaceStandings; checkpoints: CheckpointInfo[]; finishCutoffAtMs: number | null; finishDistanceKm: number | null; timeZone: string; onRowClick?: (row: Row) => void };

// Where everyone is on a course race: a tile per point, then who is still out.
// Recomputed on each render; the standings poll every few seconds.
export function CourseBoard({ race, checkpoints, finishCutoffAtMs, finishDistanceKm, timeZone, onRowClick }: Props) {
  const board = courseBoard(race, checkpoints, Date.now(), { finishCutoffAtMs, finishDistanceKm });
  return (
    <Paper component="section" aria-label={`${race.race.name} course`} sx={{ p: 2, mb: 2 }}>
      <Typography variant="h6" component="h3" gutterBottom>{race.race.name}</Typography>
      <Stack direction="row" useFlexGap sx={{ flexWrap: "wrap", gap: 1, mb: 2 }}>
        {board.points.map((p) => (
          <Paper key={p.id ?? "finish"} variant="outlined" data-testid="course-point" sx={{ p: 1, minWidth: 120 }}>
            <Typography variant="subtitle2">{p.name}</Typography>
            <Typography variant="body2">{p.passed} passed · {p.toCome} to come</Typography>
            {p.cutoffAtMs != null && <Typography variant="caption" color="text.secondary">Cutoff {formatCutoff(p.cutoffAtMs, timeZone)}</Typography>}
          </Paper>
        ))}
      </Stack>
      <Table size="small">
        <TableHead>
          <TableRow>
            <TableCell align="center">Bib</TableCell>
            <TableCell>Name</TableCell>
            <TableCell>Last seen</TableCell>
            <TableCell>Next</TableCell>
            <TableCell align="right">ETA</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          {board.out.map((o) => {
            const row = race.rows.find((r) => r.bib === o.bib);
            return (
              <TableRow key={o.bib} hover data-testid="course-out" onClick={onRowClick && row ? () => onRowClick(row) : undefined}
                sx={{ ...(onRowClick ? { cursor: "pointer" } : {}), ...(o.late ? { bgcolor: "warning.light" } : {}) }}>
                <TableCell align="center">{o.bib}</TableCell>
                <TableCell>{o.name}</TableCell>
                <TableCell>{o.lastName}{o.lastAtMs != null ? ` ${formatClock(o.lastAtMs)}` : ""}</TableCell>
                <TableCell>{o.nextName}</TableCell>
                <TableCell align="right" sx={{ fontVariantNumeric: "tabular-nums" }}>{o.etaMs != null ? formatClock(o.etaMs) : "—"}</TableCell>
              </TableRow>
            );
          })}
          {board.out.length === 0 && (
            <TableRow><TableCell colSpan={5}><Typography color="text.secondary">No one is out on the course.</Typography></TableCell></TableRow>
          )}
        </TableBody>
      </Table>
    </Paper>
  );
}
