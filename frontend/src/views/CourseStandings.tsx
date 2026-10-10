import Chip from "@mui/material/Chip";
import Paper from "@mui/material/Paper";
import Table from "@mui/material/Table";
import TableBody from "@mui/material/TableBody";
import TableCell from "@mui/material/TableCell";
import TableHead from "@mui/material/TableHead";
import TableRow from "@mui/material/TableRow";
import Typography from "@mui/material/Typography";
import type { ReactNode } from "react";
import { formatClock, formatElapsed, formatGap } from "../format";
import type { CheckpointInfo, RaceStandings, Row, Split } from "../queries";
import { STATUS_COLOR, statusLabel } from "../races";

const STATE_LABEL: Record<string, string> = { NOT_STARTED: "not started", IN_PROGRESS: "in progress", FINISH_OPEN: "finish open" };
const num = { textAlign: "right", fontVariantNumeric: "tabular-nums" } as const;

function SplitCell({ split }: { split: Split | undefined }) {
  if (split?.atMs == null) return <TableCell sx={num}>—</TableCell>;
  const title = `segment ${formatElapsed(split.segmentMs) || "—"} · elapsed ${formatElapsed(split.elapsedMs) || "—"}`;
  return (
    <TableCell sx={{ ...num, fontStyle: split.inserted ? "italic" : "normal" }} title={title}>
      {formatClock(split.atMs)}
    </TableCell>
  );
}

// A course race's results: the clock time at each checkpoint and the finish.
// onRowClick: open the racer panel for that row.
export function CourseStandings({ race, checkpoints, controls, onRowClick }: { race: RaceStandings; checkpoints: CheckpointInfo[]; controls?: ReactNode; onRowClick?: (row: Row) => void }) {
  return (
    <Paper component="section" aria-label={race.race.name} sx={{ p: 2, mb: 2 }}>
      <Typography variant="h6" component="h3" gutterBottom>
        {race.race.name} — {STATE_LABEL[race.state] ?? race.state}
      </Typography>
      {controls}
      <Table size="small">
        <TableHead>
          <TableRow>
            <TableCell sx={num}>Place</TableCell>
            <TableCell align="center">Bib</TableCell>
            <TableCell>Name</TableCell>
            <TableCell>Status</TableCell>
            {checkpoints.map((c) => <TableCell key={c.id} sx={num}>{c.name}</TableCell>)}
            <TableCell sx={num}>Finish</TableCell>
            <TableCell sx={num}>Time</TableCell>
            <TableCell sx={num}>Gap</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          {race.rows.map((row) => (
            <TableRow key={row.bib} hover onClick={onRowClick ? () => onRowClick(row) : undefined} sx={onRowClick ? { cursor: "pointer" } : undefined}>
              <TableCell sx={num}>{row.place ?? "–"}</TableCell>
              <TableCell align="center">{row.bib}</TableCell>
              <TableCell>{row.name}</TableCell>
              <TableCell>
                <Chip data-testid="racer-status" size="small" color={STATUS_COLOR[row.status] ?? "default"} label={statusLabel(row.status)} />
              </TableCell>
              {[...checkpoints.map((c) => c.id), null].map((id) => (
                <SplitCell key={id ?? "finish"} split={row.splits.find((s) => s.checkpointId === id)} />
              ))}
              <TableCell sx={num}>{formatElapsed(row.elapsedMs)}</TableCell>
              <TableCell sx={num}>{formatGap(row.gapLapsDown, row.gapMs)}</TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </Paper>
  );
}
