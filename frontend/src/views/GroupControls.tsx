import { useMutation } from "@apollo/client/react";
import Alert from "@mui/material/Alert";
import Button from "@mui/material/Button";
import Paper from "@mui/material/Paper";
import Stack from "@mui/material/Stack";
import TextField from "@mui/material/TextField";
import Typography from "@mui/material/Typography";
import { useRef, useState, type FormEvent } from "react";
import { formatClock } from "../format";
import { FIRE_START, SET_LAP_COUNT, type MutationResult } from "../queries";

type Props = {
  groupId: string;
  started: boolean | null; // null while not yet known
  startedAtMs: number | null;
  lapCount: number | null;
  canAct: boolean;
  onChanged: () => void;
};

export function GroupControls({ groupId, started, startedAtMs, lapCount, canAct, onChanged }: Props) {
  const [fireStart] = useMutation<{ fireStart: MutationResult }>(FIRE_START);
  const [setLapCount] = useMutation<{ setLapCount: MutationResult }>(SET_LAP_COUNT);
  const [firing, setFiring] = useState(false);
  const firingRef = useRef(false); // a ref, so a double-click's second event sees it immediately
  const [laps, setLaps] = useState("");
  const [error, setError] = useState<string | null>(null);

  async function go() {
    if (firingRef.current) return; // one GO per click burst (Review Focus 1)
    firingRef.current = true;
    setFiring(true);
    setError(null);
    try {
      const { data } = await fireStart({ variables: { startGroupId: groupId } });
      const errors = data?.fireStart.errors ?? [];
      if (errors.length) {
        setError(errors.join("; "));
        firingRef.current = false;
        setFiring(false);
      }
    } catch (e) {
      setError((e as Error).message);
      firingRef.current = false;
      setFiring(false);
    }
    onChanged();
  }

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
        ) : canAct ? (
          <Button variant="contained" color="success" size="large" onClick={go} disabled={firing} sx={{ px: 5, fontSize: 20, fontWeight: 700 }}>
            GO
          </Button>
        ) : (
          <Typography color="text.secondary">Not started</Typography>
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
