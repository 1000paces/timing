import { useApolloClient, useMutation } from "@apollo/client/react";
import SportsScoreIcon from "@mui/icons-material/SportsScore";
import Alert from "@mui/material/Alert";
import Box from "@mui/material/Box";
import Button from "@mui/material/Button";
import Dialog from "@mui/material/Dialog";
import DialogActions from "@mui/material/DialogActions";
import DialogContent from "@mui/material/DialogContent";
import DialogTitle from "@mui/material/DialogTitle";
import { useState } from "react";
import { formatClock, formatScheduled } from "../format";
import { CURRENT_WAVE, FLAG_OUT, REVERT_RULING, type CurrentWave, type FixResults, type MutationResult } from "../queries";

const waveName = (wave: CurrentWave) => `${wave.scheduledAtMs != null ? formatScheduled(wave.scheduledAtMs) : "unscheduled"} wave`;

type Flagged = { rulingId: string; atMs: number; wave: CurrentWave };

// Flag out from the line: the hub picks the wave on course (the latest started
// whose flag isn't out), the timer confirms it, and the flag is stamped with the
// hub's time when Flag out was first pressed, not when it was confirmed.
export function CaptureFlagOut({ eventId, chief }: { eventId: string; chief: boolean }) {
  const client = useApolloClient();
  const [flagOut] = useMutation<{ flagOut: MutationResult & { ruling: { id: string; payload: { at_ms: number } } | null } }>(FLAG_OUT);
  const [revert] = useMutation<FixResults>(REVERT_RULING);
  const [asking, setAsking] = useState<CurrentWave | null>(null);
  const [flagged, setFlagged] = useState<Flagged | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  async function ask() {
    setMessage(null);
    try {
      const { data } = await client.query<{ currentWave: CurrentWave | null }>({ query: CURRENT_WAVE, variables: { eventId }, fetchPolicy: "network-only" });
      if (data?.currentWave) setAsking(data.currentWave);
      else setMessage("No wave on course to flag: every started wave already has its flag.");
    } catch (e) {
      setMessage((e as Error).message);
    }
  }

  async function confirm(wave: CurrentWave) {
    setAsking(null);
    try {
      const { data } = await flagOut({ variables: { raceId: wave.races[0].id, atMs: wave.asOfMs } });
      const result = data?.flagOut;
      if (result?.ruling) setFlagged({ rulingId: result.ruling.id, atMs: result.ruling.payload.at_ms, wave });
      else setMessage(result?.errors.join("; ") ?? "The flag wasn't recorded");
    } catch (e) {
      setMessage((e as Error).message);
    }
  }

  async function undo(f: Flagged) {
    try {
      const errors = (await revert({ variables: { id: f.rulingId } })).data?.revertRuling?.errors ?? [];
      if (errors.length) setMessage(errors.join("; "));
      else setFlagged(null);
    } catch (e) {
      setMessage((e as Error).message);
    }
  }

  return (
    <>
      <Button variant="contained" color="warning" startIcon={<SportsScoreIcon />} onClick={() => void ask()} sx={{ whiteSpace: "nowrap" }}>
        Flag out
      </Button>
      <Dialog open={asking != null} onClose={() => setAsking(null)}>
        <DialogTitle>Flag out the {asking && waveName(asking)}?</DialogTitle>
        <DialogContent>
          {asking?.races.map((r) => r.name).join(" · ")}
          {asking && <Box sx={{ mt: 1, color: "text.secondary" }}>Recorded at {formatClock(asking.asOfMs)}, when you pressed Flag out.</Box>}
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setAsking(null)}>Cancel</Button>
          <Button variant="contained" color="warning" onClick={() => asking && void confirm(asking)}>Flag out</Button>
        </DialogActions>
      </Dialog>
      {(flagged || message) && (
        <Alert data-testid="flag-out-banner" severity={flagged ? "warning" : "info"} icon={flagged ? <SportsScoreIcon /> : undefined}
          sx={{ flex: 1 }} onClose={() => { setFlagged(null); setMessage(null); }}
          action={flagged && chief ? <Button color="inherit" size="small" onClick={() => void undo(flagged)}>Undo</Button> : undefined}>
          {flagged ? `Flag out at ${formatClock(flagged.atMs)}: ${waveName(flagged.wave)}` : message}
        </Alert>
      )}
    </>
  );
}
