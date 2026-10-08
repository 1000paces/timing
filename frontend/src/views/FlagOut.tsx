import { useMutation } from "@apollo/client/react";
import Alert from "@mui/material/Alert";
import Button from "@mui/material/Button";
import Stack from "@mui/material/Stack";
import Chip from "@mui/material/Chip";
import SportsScoreIcon from "@mui/icons-material/SportsScore";
import { useState } from "react";
import { formatClock } from "../format";
import { FLAG_OUT, type MutationResult } from "../queries";
import { TimeDialog } from "./TimeDialog";

type Props = { raceId: string; flagOutAtMs: number | null; canAct: boolean; onChanged: () => void };

// The finish flag for a race's wave: chiefs press it as the flag comes out (or
// give the time afterwards). Undo is in History.
export function FlagOut({ raceId, flagOutAtMs, canAct, onChanged }: Props) {
  const [flagOut] = useMutation<{ flagOut: MutationResult }>(FLAG_OUT);
  const [asking, setAsking] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save(atMs?: number) {
    setAsking(false);
    setError(null);
    try {
      const { data } = await flagOut({ variables: { raceId, atMs } });
      const errors = data?.flagOut.errors ?? [];
      if (errors.length) setError(errors.join("; "));
    } catch (e) {
      setError((e as Error).message);
    }
    onChanged();
  }

  if (flagOutAtMs != null) {
    return <Chip data-testid="flag-out" icon={<SportsScoreIcon />} color="warning" size="small" label={`Flag out at ${formatClock(flagOutAtMs)}`} />;
  }
  if (!canAct) return null;
  return (
    <Stack direction="row" spacing={1} sx={{ alignItems: "center" }}>
      <Button size="small" variant="contained" startIcon={<SportsScoreIcon />} onClick={() => void save()} sx={{ whiteSpace: "nowrap" }}>Flag out</Button>
      <Button size="small" onClick={() => setAsking(true)} sx={{ whiteSpace: "nowrap" }}>Flag out at…</Button>
      {asking && <TimeDialog title="Flag out" action="Flag out" atMs={Date.now()} onCancel={() => setAsking(false)} onSave={(atMs) => void save(atMs)} />}
      {error && <Alert severity="error">{error}</Alert>}
    </Stack>
  );
}
