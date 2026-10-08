import Chip from "@mui/material/Chip";
import Paper from "@mui/material/Paper";
import Table from "@mui/material/Table";
import TableBody from "@mui/material/TableBody";
import TableCell from "@mui/material/TableCell";
import TableHead from "@mui/material/TableHead";
import TableRow from "@mui/material/TableRow";
import Typography from "@mui/material/Typography";
import { formatElapsed, formatScheduled } from "../format";
import { STATUS_COLOR, statusLabel } from "../races";
import type { ReactNode } from "react";
import type { Wave, WaveRow } from "../waves";

const num = { textAlign: "right", fontVariantNumeric: "tabular-nums" } as const;

// One wave's racers in order on the road, with their category and place in it.
export function WaveStandings({ wave, controls, onRowClick }: { wave: Wave; controls?: ReactNode; onRowClick?: (row: WaveRow) => void }) {
  const title = wave.scheduledAtMs != null ? `Wave ${formatScheduled(wave.scheduledAtMs)}` : "Not scheduled";
  return (
    <Paper component="section" aria-label={title} sx={{ p: 2, mb: 2 }}>
      <Typography variant="h6" component="h3">{title}</Typography>
      <Typography variant="body2" color="text.secondary" gutterBottom>{wave.raceNames.join(" · ")}</Typography>
      {controls}
      <Table size="small">
        <TableHead>
          <TableRow>
            <TableCell sx={num}>Pos</TableCell>
            <TableCell align="center">Bib</TableCell>
            <TableCell>Name</TableCell>
            <TableCell>Category</TableCell>
            <TableCell sx={num}>Cat place</TableCell>
            <TableCell>Status</TableCell>
            <TableCell sx={num}>Laps</TableCell>
            <TableCell sx={num}>Time</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          {wave.rows.map((row) => (
            <TableRow key={row.bib} hover onClick={onRowClick ? () => onRowClick(row) : undefined} sx={onRowClick ? { cursor: "pointer" } : undefined}>
              <TableCell sx={num}>{row.position ?? "–"}</TableCell>
              <TableCell align="center">{row.bib}</TableCell>
              <TableCell>{row.name}</TableCell>
              <TableCell>{row.raceName}</TableCell>
              <TableCell sx={num}>{row.place ?? "–"}</TableCell>
              <TableCell>
                <Chip data-testid="racer-status" size="small" color={STATUS_COLOR[row.status] ?? "default"} label={statusLabel(row.status)} />
              </TableCell>
              <TableCell sx={num}>{row.laps}</TableCell>
              <TableCell sx={num}>{formatElapsed(row.elapsedMs)}</TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </Paper>
  );
}
