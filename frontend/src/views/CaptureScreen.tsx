import { useMutation, useQuery } from "@apollo/client/react";
import DeleteIcon from "@mui/icons-material/Delete";
import FilterAltIcon from "@mui/icons-material/FilterAlt";
import WarningAmberIcon from "@mui/icons-material/WarningAmber";
import Alert from "@mui/material/Alert";
import Box from "@mui/material/Box";
import Button from "@mui/material/Button";
import ButtonBase from "@mui/material/ButtonBase";
import Chip from "@mui/material/Chip";
import Dialog from "@mui/material/Dialog";
import DialogActions from "@mui/material/DialogActions";
import DialogTitle from "@mui/material/DialogTitle";
import IconButton from "@mui/material/IconButton";
import LinearProgress from "@mui/material/LinearProgress";
import List from "@mui/material/List";
import ListItem from "@mui/material/ListItem";
import Paper from "@mui/material/Paper";
import Stack from "@mui/material/Stack";
import TextField from "@mui/material/TextField";
import Tooltip from "@mui/material/Tooltip";
import Typography from "@mui/material/Typography";
import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import { formatClock, formatElapsed } from "../format";
import { CAPTURE_SCREEN, CORRECT_CAPTURE_BIB, DELETE_CAPTURE, RECORD_CAPTURE, type CaptureRow, type CaptureScreenData, type LapFlag, type RecordCaptureResult } from "../queries";
import { canAct as roleCanAct, isSignedOutError } from "../roles";
import type { Official } from "../session";
import { initialSearch, showSearch } from "../rememberedSearch";
import { useEventChanges } from "../useEventChanges";
import { EventNav } from "./EventNav";
import { PhonesPanel } from "./PhonesPanel";

type Props = { eventId: string; official: Official; onSignedOut: () => void };

// Bib + Enter records a crossing at hub time; blank + Enter records one with no
// bib, which an official assigns from the review queue.
export function CaptureScreen({ eventId, official, onSignedOut }: Props) {
  const screen = useQuery<CaptureScreenData>(CAPTURE_SCREEN, { variables: { id: eventId }, fetchPolicy: "cache-and-network" });
  const [recordCapture] = useMutation<RecordCaptureResult>(RECORD_CAPTURE);
  const [deleteCapture] = useMutation<{ deleteCapture: { errors: string[] } }>(DELETE_CAPTURE);
  const [deleting, setDeleting] = useState<CaptureRow | null>(null);
  const [onlyBib, setOnlyBib] = useState<string | null>(null);
  const deviceKey = `capture-device:${eventId}`;
  const [device, setDevice] = useState(() => new URLSearchParams(initialSearch(deviceKey, window.location.search)).get("device") ?? "all");
  useEffect(() => showSearch(deviceKey, device === "all" ? "" : `?device=${encodeURIComponent(device)}`), [deviceKey, device]);
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
  const racers = new Map(event.registrations.map((r) => [r.bib, { name: `${r.racer.firstName} ${r.racer.lastName}`, race: raceNames.get(r.raceId) ?? "" }]));

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

  function confirmDelete(capture: CaptureRow) {
    setDeleting(null);
    input.current?.focus();
    deleteCapture({ variables: { captureId: capture.id } })
      .then(({ data }) => {
        const errors = data?.deleteCapture.errors ?? [];
        setError(errors.length ? errors.join("; ") : null);
      })
      .catch((err: Error) => setError(err.message))
      .finally(refresh);
  }

  const chief = roleCanAct(official.role);
  const deviceNames = [...new Set(event.captures.filter((c) => !c.mine).map((c) => c.deviceName))].sort();
  const shown = event.captures.filter((c) =>
    (device === "all" || (device === "mine" ? c.mine : c.deviceName === device)) && (!onlyBib || c.bib === onlyBib));

  return (
    <Box sx={{ p: 2, maxWidth: 720 }}>
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
          helperText="Type the bib and press Enter as the racer crosses. Missed the number? Press Enter with the box empty."
          slotProps={{ htmlInput: { inputMode: "numeric", style: { fontSize: 40, textAlign: "center" } } }}
        />
      </form>
      {error && <Alert severity="error" sx={{ mt: 2 }} onClose={() => setError(null)}>{error}</Alert>}
      <Stack direction="row" spacing={2} sx={{ mt: 2, alignItems: "center" }}>
        <TextField select size="small" label="Device" value={device} onChange={(e) => setDevice(e.target.value)} sx={{ minWidth: 200 }}
          slotProps={{ select: { native: true }, inputLabel: { shrink: true } }}>
          <option value="all">All devices</option>
          <option value="mine">Mine (this console)</option>
          {deviceNames.map((n) => <option key={n} value={n}>{n}</option>)}
        </TextField>
      </Stack>
      {onlyBib && <Chip label={`Bib ${onlyBib}`} color="primary" size="small" onDelete={() => setOnlyBib(null)} sx={{ mt: 2 }} />}
      <Paper sx={{ mt: 2 }}>
        <List dense>
          {shown.map((c) => (
            <ListItem key={c.id} data-testid="capture" divider>
              <IconButton size="small" aria-label="Show only this bib" disabled={!c.bib} onClick={() => setOnlyBib(c.bib)} sx={{ mr: 1 }}>
                <FilterAltIcon fontSize="small" />
              </IconButton>
              <Typography sx={{ fontFamily: "monospace", width: 100 }}>{formatClock(c.atMs)}</Typography>
              <Box sx={{ width: 110, textAlign: "center" }}>
                <CaptureBib capture={c} chief={chief} onChanged={refresh} />
                {c.enteredBib !== c.bib && (
                  <Typography variant="caption" color="text.secondary" sx={{ display: "block", lineHeight: 1.1 }}>
                    entered: {c.enteredBib ?? "no bib"}
                  </Typography>
                )}
              </Box>
              <Typography sx={{ width: 60 }}>{c.lap != null ? `Lap ${c.lap}` : ""}</Typography>
              <Box sx={{ flex: 1, minWidth: 0 }}>
                {c.bib && racers.has(c.bib) && (
                  <>
                    <Typography noWrap>{racers.get(c.bib)!.name}</Typography>
                    <Typography variant="caption" color="text.secondary" noWrap sx={{ display: "block" }}>{racers.get(c.bib)!.race}</Typography>
                  </>
                )}
              </Box>
              <Stack direction="row" spacing={0.5} sx={{ flexShrink: 0 }}>
                {!c.mine && <Chip data-testid="device" size="small" variant="outlined" label={c.deviceName} />}
                {(!c.bib || !racers.has(c.bib)) && (
                  <Chip data-testid="bib-problem" size="small" color="error" label={c.bib ? "Unknown bib" : "No bib"} />
                )}
                <LapWarning capture={c} />
              </Stack>
              <IconButton aria-label="Delete capture" color="error" size="small" sx={{ ml: 1, visibility: c.mine || chief ? "visible" : "hidden" }}
                disabled={!(c.mine || chief)} onClick={() => setDeleting(c)}>
                <DeleteIcon fontSize="small" />
              </IconButton>
            </ListItem>
          ))}
          {shown.length === 0 && (
            <ListItem>
              <Typography color="text.secondary">No crossings recorded yet.</Typography>
            </ListItem>
          )}
        </List>
      </Paper>
      {roleCanAct(official.role) && <PhonesPanel eventId={eventId} />}
      <Dialog open={deleting != null} onClose={() => setDeleting(null)}>
        <DialogTitle>
          Delete {deleting?.bib ? `bib ${deleting.bib}` : "the no-bib crossing"} at {deleting ? formatClock(deleting.capturedAtMs) : ""}?
        </DialogTitle>
        <DialogActions>
          <Button onClick={() => setDeleting(null)}>Cancel</Button>
          <Button color="error" variant="contained" onClick={() => deleting && confirmDelete(deleting)}>
            Delete
          </Button>
        </DialogActions>
      </Dialog>
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
  const lap = formatElapsed(capture.lapMs);
  const typical = formatElapsed(capture.typicalLapMs);
  return (
    <Tooltip title={`Typical lap ${typical}. ${hint}`}>
      <Chip data-testid="lap-warning" size="small" color="warning" icon={<WarningAmberIcon />} label={`${label} ${lap}`}
        aria-label={`${label} ${lap}, typical ${typical}`} />
    </Tooltip>
  );
}

// The crossing's bib; click it to correct or add one: Enter or Tab saves,
// Escape cancels. Locked when an official assigned the bib in the review queue.
// chief: chiefs and admins may correct any device's crossing (an official ruling).
function CaptureBib({ capture, chief, onChanged }: { capture: CaptureRow; chief: boolean; onChanged: () => void }) {
  const [correct] = useMutation<{ correctCaptureBib: { errors: string[] } }>(CORRECT_CAPTURE_BIB);
  const [editing, setEditing] = useState(false);
  const [value, setValue] = useState("");
  const [error, setError] = useState<string | null>(null);
  const saving = useRef(false);
  const allowed = capture.mine || chief;
  const locked = !allowed || (capture.bibSource === "RULING" && !chief);

  function open() {
    setValue(capture.bib ?? "");
    setError(null);
    setEditing(true);
  }

  async function save() {
    if (saving.current) return;
    if (value.trim() === (capture.bib ?? "")) return setEditing(false);
    saving.current = true;
    try {
      const errors = (await correct({ variables: { captureId: capture.id, bib: value } })).data?.correctCaptureBib.errors ?? [];
      if (errors.length) setError(errors.join("; "));
      else {
        setEditing(false);
        onChanged();
      }
    } catch (e) {
      setError((e as Error).message);
    } finally {
      saving.current = false;
    }
  }

  if (editing) {
    return (
      <TextField size="small" autoFocus value={value} onChange={(e) => setValue(e.target.value)} error={error != null} helperText={error}
        onKeyDown={(e) => {
          if (e.key === "Enter") void save();
          if (e.key === "Escape") setEditing(false);
        }}
        onBlur={() => void save()}
        slotProps={{ htmlInput: { "aria-label": "Bib for crossing", inputMode: "numeric", style: { textAlign: "center", fontWeight: "bold" } } }}
        sx={{ width: 100 }} />
    );
  }
  return (
    <Tooltip title={!allowed ? `Recorded on ${capture.deviceName}` : locked ? "An official assigned this bib; change it in the review queue" : capture.bib ? "Click to correct the bib" : "Click to add a bib"}>
      <span>
        <ButtonBase aria-label="Edit bib" disabled={locked} onClick={open}
          sx={{ px: 1, borderRadius: 1, minWidth: 48, "&:hover": { bgcolor: "action.hover" } }}>
          <Typography sx={{ fontWeight: "bold" }}>{capture.bib ?? "—"}</Typography>
        </ButtonBase>
      </span>
    </Tooltip>
  );
}
