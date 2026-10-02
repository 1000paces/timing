import { useMutation } from "@apollo/client/react";
import Alert from "@mui/material/Alert";
import Button from "@mui/material/Button";
import Stack from "@mui/material/Stack";
import TextField from "@mui/material/TextField";
import Typography from "@mui/material/Typography";
import { useState, type FormEvent } from "react";
import { formatClock } from "../format";
import { SET_LAP_COUNT, type MutationResult } from "../queries";

type Props = { raceId: string; startAtMs: number | null; lapCount: number | null; canAct: boolean; onChanged: () => void };

// A race's start status and lap count. Setting laps applies to every race that
// finishes with this one.
export function RaceControls({ raceId, startAtMs, lapCount, canAct, onChanged }: Props) {
  const [setLapCount] = useMutation<{ setLapCount: MutationResult }>(SET_LAP_COUNT);
  const [laps, setLaps] = useState("");
  const [error, setError] = useState<string | null>(null);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setError(null);
    try {
      const { data } = await setLapCount({ variables: { raceId, laps: Number(laps) } });
      const errors = data?.setLapCount.errors ?? [];
      if (errors.length) setError(errors.join("; "));
      else setLaps("");
    } catch (e) {
      setError((e as Error).message);
    }
    onChanged();
  }

  return (
    <Stack direction="row" spacing={3} sx={{ alignItems: "center", flexWrap: "wrap", mb: 1 }}>
      <Typography color={startAtMs ? "text.primary" : "text.secondary"}>
        {startAtMs ? `Started at ${formatClock(startAtMs)}` : "Not started — start it on the Start tab"}
      </Typography>
      <Typography>Lap count: {lapCount ?? "not set"}</Typography>
      {canAct && (
        <Stack component="form" direction="row" spacing={1} onSubmit={submit} sx={{ alignItems: "center" }}>
          <TextField label="Laps" type="number" size="small" value={laps} onChange={(e) => setLaps(e.target.value)}
            slotProps={{ htmlInput: { min: 1 } }} sx={{ width: 96 }} />
          <Button type="submit" variant="outlined" size="small" disabled={!laps}>
            Set laps
          </Button>
        </Stack>
      )}
      {error && <Alert severity="error">{error}</Alert>}
    </Stack>
  );
}
