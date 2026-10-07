import Paper from "@mui/material/Paper";
import Table from "@mui/material/Table";
import TableBody from "@mui/material/TableBody";
import TableCell from "@mui/material/TableCell";
import TableHead from "@mui/material/TableHead";
import TableRow from "@mui/material/TableRow";
import Typography from "@mui/material/Typography";
import { formatElapsed, formatGap } from "../format";
import type { ReactNode } from "react";
import type { RaceStandings, Row } from "../queries";
import Chip from "@mui/material/Chip";
import { STATUS_COLOR, statusLabel } from "../races";

const STATE_LABEL: Record<string, string> = { NOT_STARTED: "not started", IN_PROGRESS: "in progress", FINISH_OPEN: "finish open" };
const num = { textAlign: "right", fontVariantNumeric: "tabular-nums" } as const;

// rowActions: per-racer actions (chief and above), shown in an Actions column.
export function Standings({ race, controls, rowActions }: { race: RaceStandings; controls?: ReactNode; rowActions?: (row: Row) => ReactNode }) {
  return (
    <Paper component="section" aria-label={race.race.name} sx={{ p: 2, mb: 2 }}>
      <Typography variant="h6" component="h3" gutterBottom>
        {race.race.name} — {STATE_LABEL[race.state] ?? race.state} — {race.lapCount ? `${race.lapCount} laps` : "lap count not set"}
      </Typography>
      {controls}
      <Table size="small">
        <TableHead>
          <TableRow>
            <TableCell sx={num}>Place</TableCell>
            <TableCell align="center">Bib</TableCell>
            <TableCell>Name</TableCell>
            <TableCell>Status</TableCell>
            <TableCell sx={num}>Laps</TableCell>
            <TableCell sx={num}>Time</TableCell>
            <TableCell sx={num}>Gap</TableCell>
            {rowActions && <TableCell align="right">Actions</TableCell>}
          </TableRow>
        </TableHead>
        <TableBody>
          {race.rows.map((row) => (
            <TableRow key={row.bib} hover>
              <TableCell sx={num}>{row.place ?? "–"}</TableCell>
              <TableCell align="center">{row.bib}</TableCell>
              <TableCell>{row.name}</TableCell>
              <TableCell>
                <Chip data-testid="racer-status" size="small" color={STATUS_COLOR[row.status] ?? "default"} label={statusLabel(row.status)} />
              </TableCell>
              <TableCell sx={num}>{row.laps}</TableCell>
              <TableCell sx={num}>{formatElapsed(row.elapsedMs)}</TableCell>
              <TableCell sx={num}>{formatGap(row.gapLapsDown, row.gapMs)}</TableCell>
              {rowActions && <TableCell align="right">{rowActions(row)}</TableCell>}
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </Paper>
  );
}
