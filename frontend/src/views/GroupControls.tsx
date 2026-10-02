import { useMutation } from "@apollo/client/react";
import Alert from "@mui/material/Alert";
import Button from "@mui/material/Button";
import Paper from "@mui/material/Paper";
import Stack from "@mui/material/Stack";
import TextField from "@mui/material/TextField";
import Typography from "@mui/material/Typography";
import { useState, type FormEvent } from "react";
import { formatClock } from "../format";
import { SET_LAP_COUNT, type MutationResult } from "../queries";

type Props = {
  groupId: string;
  started: boolean | null; // null while not yet known
  startedAtMs: number | null;
  lapCount: number | null;
  canAct: boolean;
  onChanged: () => void;
};

export function GroupControls({ groupId, started, startedAtMs, lapCount, canAct, onChanged }: Props) {
  const [setLapCount] = useMutation<{ setLapCount: MutationResult }>(SET_LAP_COUNT);
  const [laps, setLaps] = useState("");
  const [error, setError] = useState<string | null>(null);

  async function submitLaps(event: FormEvent) {
    event.preventDefault();
    setError(null);
    try {
      const { data } = await setLapCount({ variables: { startGroupId: groupId, laps: Number(laps) } });
      const errors = data?.setLapCount.errors ?? [];
      if (errors.length) setError(errors.join("; "));
      else setLaps("");
    } catch (e) {
      setError((e as Error).message);
    }
    onChanged();
  }

  return (
    <Paper sx={{ p: 2, mb: 2 }}>
      <Stack direction="row" spacing={3} sx={{ alignItems: "center", flexWrap: "wrap" }}>
        {started ? (
          <Typography variant="h6">Started at {startedAtMs ? formatClock(startedAtMs) : "—"}</Typography>
        ) : started === null ? (
          <Typography color="text.secondary">Checking start…</Typography>
        ) : (
          <Typography color="text.secondary">Not started — start races on the Start tab</Typography>
        )}
        <Typography>Lap count: {lapCount ?? "not set"}</Typography>
        {canAct && (
          <Stack component="form" direction="row" spacing={1} onSubmit={submitLaps} sx={{ alignItems: "center" }}>
            <TextField
              label="Laps"
              type="number"
              size="small"
              value={laps}
              onChange={(e) => setLaps(e.target.value)}
              slotProps={{ htmlInput: { min: 1 } }}
              sx={{ width: 96 }}
            />
            <Button type="submit" variant="outlined" disabled={!laps}>
              Set laps
            </Button>
          </Stack>
        )}
      </Stack>
      {error && <Alert severity="error" sx={{ mt: 2 }}>{error}</Alert>}
    </Paper>
  );
}
