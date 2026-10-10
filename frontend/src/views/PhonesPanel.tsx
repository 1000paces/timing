import { useMutation, useQuery } from "@apollo/client/react";
import Alert from "@mui/material/Alert";
import Box from "@mui/material/Box";
import Button from "@mui/material/Button";
import Chip from "@mui/material/Chip";
import Dialog from "@mui/material/Dialog";
import DialogActions from "@mui/material/DialogActions";
import DialogContent from "@mui/material/DialogContent";
import DialogTitle from "@mui/material/DialogTitle";
import List from "@mui/material/List";
import ListItem from "@mui/material/ListItem";
import Paper from "@mui/material/Paper";
import Stack from "@mui/material/Stack";
import Typography from "@mui/material/Typography";
import QRCode from "qrcode";
import { useEffect, useState } from "react";
import MenuItem from "@mui/material/MenuItem";
import TextField from "@mui/material/TextField";
import { CREATE_PAIRING_TOKEN, DEVICES, EVENT, REVOKE_DEVICE, SET_DEVICE_CHECKPOINT, type CheckpointInfo, type EventData, type EventInfo, type MutationResult, type PhoneRow } from "../queries";

// "just now", "4 min ago", "2 h ago".
export function ago(ms: number | null, now = Date.now()): string {
  if (ms == null) return "never";
  const seconds = Math.max(0, Math.round((now - ms) / 1000));
  if (seconds < 60) return "just now";
  if (seconds < 3600) return `${Math.floor(seconds / 60)} min ago`;
  return `${Math.floor(seconds / 3600)} h ago`;
}

// Pair phones to this event with a QR code; see when each last synced; revoke.
// On a course event each phone sits at a checkpoint (or the finish). A phone may
// still point at a checkpoint since removed from the course.
function CheckpointSelect({ value, checkpoints, onChange, label = "Location" }: { value: string | null; checkpoints: CheckpointInfo[]; onChange: (id: string | null) => void; label?: string }) {
  const removed = value != null && !checkpoints.some((c) => c.id === value);
  return (
    <TextField select size="small" label={label} value={value ?? ""} onChange={(e) => onChange(e.target.value || null)} sx={{ minWidth: 160 }}
      slotProps={{ select: { displayEmpty: true }, inputLabel: { shrink: true } }}>
      <MenuItem value="">Finish</MenuItem>
      {checkpoints.map((c) => <MenuItem key={c.id} value={c.id}>{c.name}</MenuItem>)}
      {removed && <MenuItem value={value}>Removed checkpoint</MenuItem>}
    </TextField>
  );
}

export function PhonesPanel({ eventId, event: given }: { eventId: string; event?: EventInfo }) {
  // Capture screen doesn't have the event; the cache usually does.
  const fetched = useQuery<EventData>(EVENT, { variables: { id: eventId }, skip: given != null });
  const event = given ?? fetched.data?.event;
  const checkpoints = event?.checkpoints ?? [];
  const isCourse = event?.raceFormat === "course";
  const [pairAt, setPairAt] = useState<string | null>(null);
  const [setDeviceCheckpoint] = useMutation<{ setDeviceCheckpoint: MutationResult }>(SET_DEVICE_CHECKPOINT);
  const devices = useQuery<{ devices: PhoneRow[] }>(DEVICES, { variables: { eventId }, pollInterval: 5000, fetchPolicy: "network-only" });
  const [createToken] = useMutation<{ createPairingToken: MutationResult & { token: string | null; pairingUrl: string | null; expiresAtMs: number | null } }>(CREATE_PAIRING_TOKEN);
  const [revoke] = useMutation<{ revokeDevice: MutationResult }>(REVOKE_DEVICE);
  const [asking, setAsking] = useState(false);
  const [pairing, setPairing] = useState<{ url: string; code: string; qr: string; expiresAtMs: number } | null>(null);
  const [revoking, setRevoking] = useState<PhoneRow | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timer);
  }, []);

  async function pair() {
    setError(null);
    try {
      const result = (await createToken({ variables: { eventId, checkpointId: isCourse ? pairAt : null } })).data?.createPairingToken;
      if (!result?.pairingUrl || !result.token || !result.expiresAtMs) return setError(result?.errors.join("; ") || "Couldn't create a pairing code");
      setPairing({ url: result.pairingUrl, code: result.token, qr: await QRCode.toDataURL(result.pairingUrl, { width: 280, margin: 1 }), expiresAtMs: result.expiresAtMs });
    } catch (e) {
      setError((e as Error).message);
    }
  }

  function startPairing() {
    if (!isCourse) return void pair();
    setPairAt(null);
    setAsking(true);
  }

  async function moveDevice(device: PhoneRow, checkpointId: string | null) {
    try {
      const errors = (await setDeviceCheckpoint({ variables: { deviceId: device.id, checkpointId } })).data?.setDeviceCheckpoint.errors ?? [];
      setError(errors.length ? errors.join("; ") : null);
    } catch (e) {
      setError((e as Error).message);
    }
    void devices.refetch().catch(() => {});
  }

  async function confirmRevoke(device: PhoneRow) {
    setRevoking(null);
    try {
      const errors = (await revoke({ variables: { id: device.id } })).data?.revokeDevice.errors ?? [];
      setError(errors.length ? errors.join("; ") : null);
    } catch (e) {
      setError((e as Error).message);
    }
    void devices.refetch().catch(() => {});
  }

  const phones = devices.data?.devices ?? [];
  const left = pairing ? Math.max(0, Math.round((pairing.expiresAtMs - now) / 1000)) : 0;

  return (
    <Paper sx={{ mt: 2, p: 2 }}>
      <Stack direction="row" sx={{ alignItems: "center", mb: 1 }}>
        <Typography variant="h6" component="h2" sx={{ flex: 1 }}>Phones</Typography>
        <Button variant="outlined" onClick={startPairing}>Pair a phone</Button>
      </Stack>
      {error && <Alert severity="error" sx={{ mb: 1 }} onClose={() => setError(null)}>{error}</Alert>}
      {phones.length === 0 && <Typography color="text.secondary">No phones paired yet.</Typography>}
      <List dense disablePadding>
        {phones.map((d) => (
          <ListItem key={d.id} data-testid="phone" divider sx={{ gap: 1, flexWrap: "wrap" }}>
            <Box sx={{ flex: 1, minWidth: 160 }}>
              <Typography>{d.name}</Typography>
              <Typography variant="caption" color="text.secondary">
                Seen {ago(d.lastSeenAtMs, now)} · Synced {ago(d.lastSyncAtMs, now)}
                {d.clockOffsetMs != null ? ` · Clock ${d.clockOffsetMs > 0 ? "+" : ""}${d.clockOffsetMs} ms` : " · Clock not synced"}
              </Typography>
            </Box>
            {isCourse && !d.revokedAtMs && <CheckpointSelect value={d.checkpointId} checkpoints={checkpoints} onChange={(id) => void moveDevice(d, id)} />}
            {d.syncStoppedAtMs && <Chip size="small" color="error" label="Sync stopped" />}
            {d.revokedAtMs ? (
              <Chip size="small" label="Revoked" />
            ) : (
              <Button size="small" color="error" aria-label={`Revoke ${d.name}`} onClick={() => setRevoking(d)}>Revoke</Button>
            )}
          </ListItem>
        ))}
      </List>

      <Dialog open={asking} onClose={() => setAsking(false)}>
        <DialogTitle>Where will this phone be?</DialogTitle>
        <DialogContent sx={{ pt: 1 }}>
          <CheckpointSelect value={pairAt} checkpoints={checkpoints} onChange={setPairAt} label="Checkpoint" />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setAsking(false)}>Cancel</Button>
          <Button variant="contained" onClick={() => { setAsking(false); void pair(); }}>Create code</Button>
        </DialogActions>
      </Dialog>

      <Dialog open={pairing != null} onClose={() => setPairing(null)}>
        <DialogTitle>Pair a phone</DialogTitle>
        <DialogContent>
          <Stack spacing={1} sx={{ alignItems: "center" }}>
            <Typography variant="body2" sx={{ textAlign: "center" }}>
              <strong>Scan with the phone's camera</strong> (on the hub's Wi-Fi) to open the Capture app — in a browser tab this pairs it too.
            </Typography>
            {pairing && <img src={pairing.qr} alt="Pairing QR code" width={280} height={280} />}
            <Typography variant="body2" sx={{ textAlign: "center" }}>
              <strong>Or type this code in the Capture app</strong> — needed for an iPhone home-screen app:
            </Typography>
            <Typography data-testid="pairing-code" sx={{ fontFamily: "monospace", fontSize: 36, fontWeight: 700, letterSpacing: 4 }}>{pairing?.code}</Typography>
            <Typography variant="body2" color="text.secondary">
              {left > 0 ? `Expires in ${Math.floor(left / 60)}:${String(left % 60).padStart(2, "0")}, and works once.` : "Expired — make a new one."}
            </Typography>
            <Typography data-testid="pairing-link" variant="caption" color="text.secondary" sx={{ wordBreak: "break-all" }}>{pairing?.url}</Typography>
          </Stack>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setPairing(null)}>Done</Button>
        </DialogActions>
      </Dialog>

      <Dialog open={revoking != null} onClose={() => setRevoking(null)}>
        <DialogTitle>Revoke {revoking?.name}?</DialogTitle>
        <DialogContent>
          <Typography variant="body2">It can no longer send crossings. Anything it already sent stays.</Typography>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setRevoking(null)}>Cancel</Button>
          <Button color="error" variant="contained" onClick={() => revoking && void confirmRevoke(revoking)}>Revoke</Button>
        </DialogActions>
      </Dialog>
    </Paper>
  );
}
