import { useMutation, useQuery } from "@apollo/client/react";
import Alert from "@mui/material/Alert";
import Box from "@mui/material/Box";
import LinearProgress from "@mui/material/LinearProgress";
import List from "@mui/material/List";
import ListItem from "@mui/material/ListItem";
import Paper from "@mui/material/Paper";
import TextField from "@mui/material/TextField";
import Typography from "@mui/material/Typography";
import { useEffect, useRef, useState, type FormEvent } from "react";
import { formatClock } from "../format";
import { CAPTURE_SCREEN, RECORD_CAPTURE, type CaptureRow, type CaptureScreenData, type RecordCaptureResult } from "../queries";
import { isSignedOutError } from "../roles";
import type { Official } from "../session";
import { EventNav } from "./EventNav";

type Props = { eventId: string; official: Official; onSignedOut: () => void };

// Bib + Enter records a crossing at hub time; blank + Enter records one with no
// bib, which an official assigns from the review queue.
export function CaptureScreen({ eventId, official, onSignedOut }: Props) {
  const screen = useQuery<CaptureScreenData>(CAPTURE_SCREEN, { variables: { id: eventId }, fetchPolicy: "cache-and-network" });
  const [recordCapture] = useMutation<RecordCaptureResult>(RECORD_CAPTURE);
  const [bib, setBib] = useState("");
  const [recent, setRecent] = useState<CaptureRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const input = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (isSignedOutError(screen.error)) onSignedOut();
  }, [screen.error, onSignedOut]);

  const event = screen.data?.event;
  useEffect(() => {
    if (event && recent === null) setRecent(event.myCaptures);
  }, [event, recent]);

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
          const capture = result.capture;
          setRecent((list) => [capture, ...(list ?? [])].sort((x, y) => y.capturedAtMs - x.capturedAtMs).slice(0, 20));
          setError(null);
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
          {(recent ?? []).map((c) => (
            <ListItem key={c.id} data-testid="capture" divider>
              <Typography sx={{ fontFamily: "monospace", width: 100 }}>{formatClock(c.capturedAtMs)}</Typography>
              <Typography sx={{ fontWeight: "bold", width: 80 }}>{c.bib ?? "—"}</Typography>
              <Typography color={c.bib && riders.has(c.bib) ? "text.primary" : "warning.main"}>
                {c.bib ? (riders.get(c.bib) ?? "unknown bib") : "no bib"}
              </Typography>
            </ListItem>
          ))}
          {recent?.length === 0 && (
            <ListItem>
              <Typography color="text.secondary">No crossings recorded yet.</Typography>
            </ListItem>
          )}
        </List>
      </Paper>
    </Box>
  );
}
