import { useMutation } from "@apollo/client/react";
import ArrowDownwardIcon from "@mui/icons-material/ArrowDownward";
import ArrowUpwardIcon from "@mui/icons-material/ArrowUpward";
import DeleteIcon from "@mui/icons-material/Delete";
import Alert from "@mui/material/Alert";
import Button from "@mui/material/Button";
import IconButton from "@mui/material/IconButton";
import Paper from "@mui/material/Paper";
import Stack from "@mui/material/Stack";
import TextField from "@mui/material/TextField";
import Typography from "@mui/material/Typography";
import { useState } from "react";
import { formatCutoff, parseCutoff } from "../course";
import { SET_CHECKPOINTS, type EventInfo, type MutationResult } from "../queries";

type Row = { key: string; id: string | null; name: string; distance: string; cutoff: string };

const toRow = (id: string | null, name: string, km: number | null, cutoffAtMs: number | null, zone: string): Row => ({
  key: id ?? crypto.randomUUID(),
  id,
  name,
  distance: km == null ? "" : String(km),
  cutoff: cutoffAtMs == null ? "" : formatCutoff(cutoffAtMs, zone),
});

// The course of a point-to-point / single-loop event: ordered checkpoints, then the finish.
export function CheckpointsEditor({ event, onSaved }: { event: EventInfo; onSaved: () => void }) {
  const zone = event.timezone;
  const [rows, setRows] = useState<Row[]>(() => event.checkpoints.map((c) => toRow(c.id, c.name, c.distanceKm, c.cutoffAtMs, zone)));
  const [finish, setFinish] = useState(() => toRow(null, "Finish", event.finishDistanceKm, event.finishCutoffAtMs, zone));
  const [errors, setErrors] = useState<string[]>([]);
  const [saved, setSaved] = useState(false);
  const [setCheckpoints] = useMutation<{ setCheckpoints: MutationResult }>(SET_CHECKPOINTS);

  // Elapsed cutoffs count from the earliest scheduled race start.
  const startMs = event.races.length ? Math.min(...event.races.map((r) => r.scheduledAtMs)) : null;
  const parse = (text: string) => parseCutoff(text, startMs, zone, event.date);
  const cutoffError = (text: string) => {
    const c = parse(text);
    return c && "error" in c ? c.error : null;
  };
  const hasError = [...rows, finish].some((r) => cutoffError(r.cutoff));

  const update = (key: string, patch: Partial<Row>) => setRows((rs) => rs.map((r) => (r.key === key ? { ...r, ...patch } : r)));
  const move = (i: number, by: number) =>
    setRows((rs) => {
      const next = [...rs];
      [next[i], next[i + by]] = [next[i + by], next[i]];
      return next;
    });
  const atMs = (text: string) => {
    const c = parse(text);
    return c && "atMs" in c ? c.atMs : null;
  };
  const km = (text: string) => (text.trim() === "" ? null : Number(text));

  async function save() {
    setErrors([]);
    setSaved(false);
    try {
      const result = (
        await setCheckpoints({
          variables: {
            eventId: event.id,
            checkpoints: rows.map((r) => ({ id: r.id, name: r.name, distanceKm: km(r.distance), cutoffAtMs: atMs(r.cutoff) })),
            finishDistanceKm: km(finish.distance),
            finishCutoffAtMs: atMs(finish.cutoff),
          },
        })
      ).data?.setCheckpoints;
      const errs = result?.errors ?? [];
      setErrors(errs);
      if (!errs.length) {
        setSaved(true);
        onSaved();
      }
    } catch (e) {
      setErrors([(e as Error).message]);
    }
  }

  const cutoffField = (r: Row, label: string, onChange: (v: string) => void) => {
    const err = cutoffError(r.cutoff);
    const parsed = atMs(r.cutoff);
    return (
      <TextField
        size="small"
        label={label}
        value={r.cutoff}
        onChange={(e) => onChange(e.target.value)}
        error={err != null}
        helperText={err ?? (parsed != null ? formatCutoff(parsed, zone) : " ")}
        placeholder="2:30 pm or +6:30"
        sx={{ width: 170 }}
      />
    );
  };

  return (
    <Paper sx={{ mt: 2, p: 2 }}>
      <Typography variant="h6" component="h2" sx={{ mb: 1 }}>Course</Typography>
      {errors.length > 0 && <Alert severity="error" sx={{ mb: 1 }} onClose={() => setErrors([])}>{errors.join("; ")}</Alert>}
      {saved && <Alert severity="success" sx={{ mb: 1 }} onClose={() => setSaved(false)}>Course saved</Alert>}
      <Stack spacing={1.5}>
        {rows.map((r, i) => (
          <Stack key={r.key} direction="row" spacing={1} data-testid="checkpoint-row" sx={{ alignItems: "flex-start" }}>
            <TextField size="small" label="Name" value={r.name} onChange={(e) => update(r.key, { name: e.target.value })} sx={{ flex: 1 }} />
            <TextField size="small" label="Distance (km)" type="number" value={r.distance} onChange={(e) => update(r.key, { distance: e.target.value })} sx={{ width: 140 }} />
            {cutoffField(r, "Cutoff", (cutoff) => update(r.key, { cutoff }))}
            <IconButton aria-label={`Move ${r.name || "checkpoint"} up`} disabled={i === 0} onClick={() => move(i, -1)}><ArrowUpwardIcon fontSize="small" /></IconButton>
            <IconButton aria-label={`Move ${r.name || "checkpoint"} down`} disabled={i === rows.length - 1} onClick={() => move(i, 1)}><ArrowDownwardIcon fontSize="small" /></IconButton>
            <IconButton aria-label={`Delete ${r.name || "checkpoint"}`} color="error" onClick={() => setRows((rs) => rs.filter((x) => x.key !== r.key))}><DeleteIcon fontSize="small" /></IconButton>
          </Stack>
        ))}
        <Stack direction="row" spacing={1} data-testid="finish-row" sx={{ alignItems: "flex-start" }}>
          <TextField size="small" label="Name" value="Finish" disabled sx={{ flex: 1 }} />
          <TextField size="small" label="Distance (km)" type="number" value={finish.distance} onChange={(e) => setFinish({ ...finish, distance: e.target.value })} sx={{ width: 140 }} />
          {cutoffField(finish, "Cutoff", (cutoff) => setFinish({ ...finish, cutoff }))}
        </Stack>
      </Stack>
      <Stack direction="row" spacing={1} sx={{ mt: 2 }}>
        <Button variant="outlined" onClick={() => setRows((rs) => [...rs, toRow(null, "", null, null, zone)])}>Add checkpoint</Button>
        <Button variant="contained" disabled={hasError} onClick={() => void save()}>Save course</Button>
      </Stack>
    </Paper>
  );
}
