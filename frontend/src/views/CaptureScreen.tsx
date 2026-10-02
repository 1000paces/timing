import { useMutation, useQuery } from "@apollo/client/react";
import WarningAmberIcon from "@mui/icons-material/WarningAmber";
import Alert from "@mui/material/Alert";
import Box from "@mui/material/Box";
import LinearProgress from "@mui/material/LinearProgress";
import List from "@mui/material/List";
import ListItem from "@mui/material/ListItem";
import Paper from "@mui/material/Paper";
import TextField from "@mui/material/TextField";
import Tooltip from "@mui/material/Tooltip";
import Typography from "@mui/material/Typography";
import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import { formatClock, formatElapsed } from "../format";
import { CAPTURE_SCREEN, RECORD_CAPTURE, type CaptureRow, type CaptureScreenData, type LapFlag, type RecordCaptureResult } from "../queries";
import { isSignedOutError } from "../roles";
import type { Official } from "../session";
import { useEventChanges } from "../useEventChanges";
import { EventNav } from "./EventNav";

type Props = { eventId: string; official: Official; onSignedOut: () => void };

// Bib + Enter records a crossing at hub time; blank + Enter records one with no
// bib, which an official assigns from the review queue.
export function CaptureScreen({ eventId, official, onSignedOut }: Props) {
  const screen = useQuery<CaptureScreenData>(CAPTURE_SCREEN, { variables: { id: eventId }, fetchPolicy: "cache-and-network" });
  const [recordCapture] = useMutation<RecordCaptureResult>(RECORD_CAPTURE);
  const [bib, setBib] = useState("");
  const [error, setError] = useState<string | null>(null);
  const input = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (isSignedOutError(screen.error)) onSignedOut();
  }, [screen.error, onSignedOut]);

  // Laps change when any device captures or a race starts, so follow the event.
  const { refetch } = screen;
  const refresh = useCallback(() => {
    refetch().catch(() => {});
  }, [refetch]);
  useEventChanges(eventId, refresh);

  const event = screen.data?.event;

  if (!event) {
    return <Box sx={{ p: 3 }}>{screen.error ? <Alert severity="error">{screen.error.message}</Alert> : <LinearProgress />}</Box>;
  }

  const raceNames = new Map(event.races.map((r) => [r.id, r.name]));
  const riders = new Map(event.registrations.map((r) => [r.bib, `${r.rider.firstName} ${r.rider.lastName} · ${raceNames.get(r.raceId) ?? ""}`]));

  // Each Enter is sent at once (no waiting on the previous one), so fast typing
  // doesn't delay the next crossing's hub time.
  function submit(e: FormEvent) {
    e.preventDefault();
    const typed = bib.trim();
    setBib("");
    input.current?.focus();
    recordCapture({ variables: { eventId, bib: typed || null } })
      .then(({ data }) => {
        const result = data?.recordCapture;
        if (result?.capture) {
          setError(null);
          refresh();
        } else throw new Error(result?.errors.join("; ") || "Couldn't record the crossing");
      })
      .catch((err: Error) => {
        setError(`${typed ? `Bib ${typed}` : "Crossing"} not recorded: ${err.message}`);
        setBib((current) => current || typed);
      });
  }

  return (
    <Box sx={{ p: 2, maxWidth: 640 }}>
      <EventNav eventId={eventId} eventName={event.name} current="capture" admin={official.role === "admin"} />
      <form onSubmit={submit}>
        <TextField
          label="Bib"
          value={bib}
          onChange={(e) => setBib(e.target.value)}
          inputRef={input}
          autoFocus
          fullWidth
          autoComplete="off"
          helperText="Enter records the crossing now; leave blank for a rider whose bib you missed"
          slotProps={{ htmlInput: { inputMode: "numeric", style: { fontSize: 40 } } }}
        />
      </form>
      {error && <Alert severity="error" sx={{ mt: 2 }} onClose={() => setError(null)}>{error}</Alert>}
      <Paper sx={{ mt: 2 }}>
        <List dense>
          {event.myCaptures.map((c) => (
            <ListItem key={c.id} data-testid="capture" divider>
              <Typography sx={{ fontFamily: "monospace", width: 100 }}>{formatClock(c.capturedAtMs)}</Typography>
              <Typography sx={{ fontWeight: "bold", width: 80 }}>{c.bib ?? "—"}</Typography>
              <Typography sx={{ width: 70 }}>{c.lap != null ? `Lap ${c.lap}` : ""}</Typography>
              <Typography sx={{ flex: 1 }} color={c.bib && riders.has(c.bib) ? "text.primary" : "warning.main"}>
                {c.bib ? (riders.get(c.bib) ?? "unknown bib") : "no bib"}
              </Typography>
              <LapWarning capture={c} />
            </ListItem>
          ))}
          {event.myCaptures.length === 0 && (
            <ListItem>
              <Typography color="text.secondary">No crossings recorded yet.</Typography>
            </ListItem>
          )}
        </List>
      </Paper>
    </Box>
  );
}

const FLAG: Record<LapFlag, { label: string; hint: string }> = {
  missed: { label: "Missed lap?", hint: "About double the typical lap: a crossing may not have been recorded" },
  long: { label: "Long lap", hint: "Much longer than the typical lap: a mechanical, or a missed crossing?" },
  short: { label: "Short lap", hint: "Much shorter than the typical lap: a double tap or wrong bib?" },
};

function LapWarning({ capture }: { capture: CaptureRow }) {
  if (!capture.lapFlag || capture.lapMs == null || capture.typicalLapMs == null) return null;
  const { label, hint } = FLAG[capture.lapFlag];
  return (
    <Tooltip title={hint}>
      <Typography data-testid="lap-warning" color="warning.main" sx={{ display: "flex", alignItems: "center", gap: 0.5, whiteSpace: "nowrap" }}>
        <WarningAmberIcon fontSize="small" />
        {label} {formatElapsed(capture.lapMs)} (typical {formatElapsed(capture.typicalLapMs)})
      </Typography>
    </Tooltip>
  );
}
