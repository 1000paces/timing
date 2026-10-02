import Paper from "@mui/material/Paper";
import Table from "@mui/material/Table";
import TableBody from "@mui/material/TableBody";
import TableCell from "@mui/material/TableCell";
import TableHead from "@mui/material/TableHead";
import TableRow from "@mui/material/TableRow";
import Typography from "@mui/material/Typography";
import { formatElapsed, formatGap } from "../format";
import type { RaceStandings } from "../queries";

const STATE_LABEL: Record<string, string> = { NOT_STARTED: "not started", IN_PROGRESS: "in progress", FINISH_OPEN: "finish open" };
const num = { textAlign: "right", fontVariantNumeric: "tabular-nums" } as const;

export function Standings({ race }: { race: RaceStandings }) {
  return (
    <Paper component="section" aria-label={race.race.name} sx={{ p: 2, mb: 2 }}>
      <Typography variant="h6" component="h3" gutterBottom>
        {race.race.name} — {STATE_LABEL[race.state] ?? race.state} — {race.lapCount ? `${race.lapCount} laps` : "lap count not set"}
      </Typography>
      <Table size="small">
        <TableHead>
          <TableRow>
            <TableCell sx={num}>#</TableCell>
            <TableCell>Bib</TableCell>
            <TableCell>Name</TableCell>
            <TableCell>Status</TableCell>
            <TableCell sx={num}>Laps</TableCell>
            <TableCell sx={num}>Time</TableCell>
            <TableCell sx={num}>Gap</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          {race.rows.map((row) => (
            <TableRow key={row.bib} hover>
              <TableCell sx={num}>{row.place ?? "–"}</TableCell>
              <TableCell>{row.bib}</TableCell>
              <TableCell>{row.name}</TableCell>
              <TableCell data-testid="rider-status">{row.status.toLowerCase()}</TableCell>
              <TableCell sx={num}>{row.laps}</TableCell>
              <TableCell sx={num}>{formatElapsed(row.elapsedMs)}</TableCell>
              <TableCell sx={num}>{formatGap(row.gapLapsDown, row.gapMs)}</TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </Paper>
  );
}
