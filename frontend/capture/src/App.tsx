import DeleteIcon from "@mui/icons-material/Delete";
import FilterAltIcon from "@mui/icons-material/FilterAlt";
import MoreVertIcon from "@mui/icons-material/MoreVert";
import WarningAmberIcon from "@mui/icons-material/WarningAmber";
import Alert from "@mui/material/Alert";
import AppBar from "@mui/material/AppBar";
import Box from "@mui/material/Box";
import Button from "@mui/material/Button";
import ButtonBase from "@mui/material/ButtonBase";
import Chip from "@mui/material/Chip";
import Dialog from "@mui/material/Dialog";
import DialogActions from "@mui/material/DialogActions";
import DialogContent from "@mui/material/DialogContent";
import DialogTitle from "@mui/material/DialogTitle";
import IconButton from "@mui/material/IconButton";
import LinearProgress from "@mui/material/LinearProgress";
import List from "@mui/material/List";
import ListItem from "@mui/material/ListItem";
import Menu from "@mui/material/Menu";
import MenuItem from "@mui/material/MenuItem";
import Stack from "@mui/material/Stack";
import TextField from "@mui/material/TextField";
import Toolbar from "@mui/material/Toolbar";
import Typography from "@mui/material/Typography";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { formatClock, formatElapsed } from "../../src/format";
import { hubApi } from "./api";
import { openCaptureDb, type CaptureDb, type Pairing } from "./db";
import { Keypad } from "./Keypad";
import { allEntries, appendBibAssignment, appendCapture, appendVoid, canUnpair, type Entry } from "./log";
import { captureRows, type Row } from "./rows";
import { createSync, type Sync, type SyncState } from "./sync";
import { SyncPill } from "./SyncPill";

const FLAG = { missed: "Missed lap?", long: "Long lap", short: "Short lap" } as const;
const PAGE = 20;

// The tap time: the phone's high-resolution clock at the Enter press.
const tapTime = () => performance.timeOrigin + performance.now();

export function App() {
  const [db, setDb] = useState<CaptureDb | null>(null);
  const [pairing, setPairing] = useState<Pairing | null | undefined>(undefined);
  const [persisted, setPersisted] = useState(true);
  useEffect(() => {
    void openCaptureDb().then(async (opened) => {
      setDb(opened);
      setPairing((await opened.get("pairing", "pairing")) ?? null);
    });
    void navigator.storage?.persist?.().then(setPersisted).catch(() => setPersisted(false));
  }, []);

  if (!db || pairing === undefined) return <LinearProgress />;
  const token = new URLSearchParams(window.location.search).get("pair");
  return (
    <>
      {!persisted && (
        <Alert severity="warning" square>
          This browser may clear the phone's saved crossings. Install the hub certificate from <a href="/onboarding">/onboarding</a> and add the app to your home screen.
        </Alert>
      )}
      {token ? (
        <PairScreen db={db} token={token} paired={pairing} onPaired={setPairing} />
      ) : pairing ? (
        <CaptureScreen db={db} pairing={pairing} onUnpaired={() => setPairing(null)} />
      ) : (
        <Box sx={{ p: 3 }}>
          <Typography variant="h5" gutterBottom>Timing Capture</Typography>
          <Typography>Scan the pairing code on the console's Capture tab (Phones → Pair a phone).</Typography>
        </Box>
      )}
    </>
  );
}

function PairScreen({ db, token, paired, onPaired }: { db: CaptureDb; token: string; paired: Pairing | null; onPaired: (p: Pairing) => void }) {
  const [name, setName] = useState(paired?.name ?? "");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function pair() {
    setBusy(true);
    setError(null);
    try {
      const entries = await allEntries(db);
      const ack = ((await db.get("state", "ackSeq")) as number | undefined) ?? 0;
      if (!canUnpair(entries.at(-1)?.device_seq ?? 0, ack)) throw new Error("This phone has crossings the hub hasn't received yet. Sync (or export) them before pairing again.");
      const result = await hubApi(() => null).pair(token, name.trim() || "Phone");
      const next = { deviceId: result.device_id, credential: result.credential, eventId: result.event_id, name: name.trim() || "Phone" };
      const tx = db.transaction(["pairing", "entries", "state"], "readwrite");
      await tx.objectStore("entries").clear(); // all acknowledged by the hub (checked above)
      await tx.objectStore("state").clear();
      await tx.objectStore("pairing").put(next, "pairing");
      await tx.done;
      window.history.replaceState(null, "", window.location.pathname);
      onPaired(next);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Box sx={{ p: 3 }}>
      <Typography variant="h5" gutterBottom>Pair this phone</Typography>
      <Stack spacing={2}>
        <TextField label="Phone name" value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Finish line phone 2" autoFocus />
        {error && <Alert severity="error">{error}</Alert>}
        <Button variant="contained" size="large" disabled={busy} onClick={() => void pair()}>Pair</Button>
      </Stack>
    </Box>
  );
}

function CaptureScreen({ db, pairing, onUnpaired }: { db: CaptureDb; pairing: Pairing; onUnpaired: () => void }) {
  const syncRef = useRef<Sync | null>(null);
  const [state, setState] = useState<SyncState | null>(null);
  const [entries, setEntries] = useState<Entry[]>([]);
  const [bib, setBib] = useState("");
  const [flash, setFlash] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [shown, setShown] = useState(PAGE);
  const [onlyBib, setOnlyBib] = useState<string | null>(null);
  const [editing, setEditing] = useState<Row | null>(null);
  const [deleting, setDeleting] = useState<Row | null>(null);
  const [menu, setMenu] = useState<HTMLElement | null>(null);

  const reload = useCallback(async () => setEntries(await allEntries(db)), [db]);

  useEffect(() => {
    const sync = createSync({
      db,
      api: hubApi(() => ({ deviceId: pairing.deviceId, credential: pairing.credential, offsetMs: syncRef.current?.state().offsetMs ?? null })),
    });
    syncRef.current = sync;
    const unsubscribe = sync.subscribe(setState);
    void sync.start().then(() => setState(sync.state()));
    void reload();
    const online = () => {
      sync.online();
      void sync.kick();
    };
    window.addEventListener("online", online);
    return () => {
      unsubscribe();
      sync.stop();
      window.removeEventListener("online", online);
    };
  }, [db, pairing, reload]);

  // Every tap is written to the phone first; only then do we confirm it.
  const record = useCallback(async (atMs: number, typed: string) => {
    const sync = syncRef.current;
    try {
      await appendCapture(db, { atMs, offsetMs: sync?.state().offsetMs ?? null, bib: typed });
      setBib("");
      setError(null);
      setFlash(true);
      setTimeout(() => setFlash(false), 150);
      navigator.vibrate?.(30);
      await reload();
      void sync?.kick();
    } catch (e) {
      setError(`Not recorded: ${(e as Error).message}`);
    }
  }, [db, reload]);

  const enter = useCallback(() => void record(tapTime(), bib), [record, bib]);

  // A hardware keyboard works too.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (editing || deleting || (e.target instanceof HTMLInputElement)) return;
      if (/^[0-9]$/.test(e.key)) setBib((b) => (b + e.key).slice(0, 6));
      else if (e.key === "Backspace") setBib((b) => b.slice(0, -1));
      else if (e.key === "Enter") {
        e.preventDefault();
        void record(tapTime(), bib);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [record, bib, editing, deleting]);

  const rows = useMemo(() => captureRows(entries, state?.roster ?? null, state?.status ?? null), [entries, state?.roster, state?.status]);
  const visible = onlyBib ? rows.filter((r) => r.bib === onlyBib) : rows;
  const offset = state?.offsetMs ?? 0;
  const lastSeq = entries.at(-1)?.device_seq ?? 0;

  async function correct(row: Row, value: string) {
    setEditing(null);
    if (!value.trim() || value.trim() === row.bib) return;
    await appendBibAssignment(db, row.id, value);
    await reload();
    void syncRef.current?.kick();
  }

  async function remove(row: Row) {
    setDeleting(null);
    await appendVoid(db, row.id);
    await reload();
    void syncRef.current?.kick();
  }

  function exportLog() {
    const blob = new Blob([JSON.stringify({ pairing: { deviceId: pairing.deviceId, eventId: pairing.eventId, name: pairing.name }, entries }, null, 2)], { type: "application/json" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `capture-log-${pairing.name.replace(/\W+/g, "-")}-${new Date().toISOString().slice(0, 19)}.json`;
    a.click();
    URL.revokeObjectURL(a.href);
  }

  async function unpair() {
    setMenu(null);
    if (!canUnpair(lastSeq, (await db.get("state", "ackSeq")) as number ?? 0)) return setError("Can't unpair: some crossings haven't reached the hub yet.");
    await db.clear("pairing");
    onUnpaired();
  }

  return (
    <Box sx={{ pb: 2, bgcolor: flash ? "success.dark" : "background.default", transition: "background-color 150ms", minHeight: "100vh" }}>
      <AppBar position="sticky" color="default" elevation={1}>
        <Toolbar variant="dense" sx={{ gap: 1 }}>
          <Typography noWrap sx={{ flex: 1, fontWeight: 600 }}>{state?.roster?.event.name ?? "Capture"}</Typography>
          {state && <SyncPill state={state} />}
          <IconButton aria-label="Menu" edge="end" onClick={(e) => setMenu(e.currentTarget)}><MoreVertIcon /></IconButton>
        </Toolbar>
      </AppBar>
      <Menu anchorEl={menu} open={menu != null} onClose={() => setMenu(null)}>
        <MenuItem disabled>{pairing.name}</MenuItem>
        <MenuItem disabled>Last sync: {state?.lastSyncAtMs ? formatClock(state.lastSyncAtMs) : "never"}</MenuItem>
        <MenuItem disabled>Clock: {state?.clockSynced ? `${offset > 0 ? "+" : ""}${offset} ms` : "not synced"}</MenuItem>
        <MenuItem onClick={() => { setMenu(null); exportLog(); }}>Export log</MenuItem>
        <MenuItem onClick={() => void unpair()}>Unpair</MenuItem>
      </Menu>

      {state?.stopped && <Alert severity="error" square>Sync stopped — export the log (menu) and see an official.</Alert>}
      {error && <Alert severity="error" square onClose={() => setError(null)}>{error}</Alert>}

      <Box sx={{ p: 2 }}>
        <Typography data-testid="bib-display" sx={{ fontSize: 56, fontWeight: 700, textAlign: "center", lineHeight: 1.2, minHeight: 68, letterSpacing: 4 }}>
          {bib || <Box component="span" sx={{ color: "text.disabled", fontSize: 24, letterSpacing: 0 }}>bib (blank = no bib)</Box>}
        </Typography>
        <Keypad onDigit={(d) => setBib((b) => (b + d).slice(0, 6))} onBack={() => setBib((b) => b.slice(0, -1))} onEnter={enter} />
      </Box>

      {onlyBib && (
        <Box sx={{ px: 2 }}>
          <Chip label={`Bib ${onlyBib}`} onDelete={() => setOnlyBib(null)} color="primary" size="small" />
        </Box>
      )}
      <List dense>
        {visible.slice(0, shown).map((row) => (
          <ListItem key={row.id} data-testid="crossing" divider sx={{ gap: 1, px: 1 }}>
            <IconButton size="small" aria-label="Show only this bib" disabled={!row.bib} onClick={() => setOnlyBib(row.bib)}>
              <FilterAltIcon fontSize="small" />
            </IconButton>
            <Typography sx={{ fontFamily: "monospace", width: 72, flexShrink: 0 }}>{formatClock(row.atMs + offset)}</Typography>
            <Box sx={{ width: 64, flexShrink: 0, textAlign: "center" }}>
              <ButtonBase aria-label="Edit bib" disabled={row.locked} onClick={() => setEditing(row)} sx={{ borderRadius: 1, px: 0.5 }}>
                <Typography sx={{ fontWeight: 700 }}>{row.bib ?? "—"}</Typography>
              </ButtonBase>
              {row.enteredNote && <Typography variant="caption" color="text.secondary" sx={{ display: "block", lineHeight: 1.1 }}>{row.enteredNote}</Typography>}
            </Box>
            <Box sx={{ flex: 1, minWidth: 0 }}>
              {row.name && <Typography noWrap>{row.name}</Typography>}
              {row.race && <Typography variant="caption" color="text.secondary" noWrap sx={{ display: "block" }}>{row.race}</Typography>}
              <Stack direction="row" spacing={0.5} sx={{ mt: 0.25, flexWrap: "wrap" }}>
                {row.chips.map((c) => <Chip key={c} size="small" color="error" label={c} />)}
                <Chip size="small" variant="outlined" label={row.lap != null ? `Lap ${row.lap}` : "Lap —"} />
                {row.lapFlag && row.lapMs != null && (
                  <Chip size="small" color="warning" icon={<WarningAmberIcon />} label={`${FLAG[row.lapFlag]} ${formatElapsed(row.lapMs)}`} />
                )}
              </Stack>
            </Box>
            <IconButton size="small" color="error" aria-label="Delete crossing" onClick={() => setDeleting(row)}>
              <DeleteIcon fontSize="small" />
            </IconButton>
          </ListItem>
        ))}
        {visible.length === 0 && (
          <ListItem><Typography color="text.secondary">No crossings yet.</Typography></ListItem>
        )}
      </List>
      {visible.length > shown && <Button fullWidth onClick={() => setShown(shown + PAGE)}>Show more</Button>}

      {editing && <BibSheet row={editing} onCancel={() => setEditing(null)} onSave={(v) => void correct(editing, v)} />}
      <Dialog open={deleting != null} onClose={() => setDeleting(null)}>
        <DialogTitle>Delete {deleting?.bib ? `bib ${deleting.bib}` : "the no-bib crossing"} at {deleting ? formatClock(deleting.atMs + offset) : ""}?</DialogTitle>
        <DialogActions>
          <Button onClick={() => setDeleting(null)}>Cancel</Button>
          <Button color="error" variant="contained" onClick={() => deleting && void remove(deleting)}>Delete</Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}

function BibSheet({ row, onCancel, onSave }: { row: Row; onCancel: () => void; onSave: (bib: string) => void }) {
  const [value, setValue] = useState(row.bib ?? "");
  return (
    <Dialog open onClose={onCancel} fullWidth>
      <DialogTitle>Correct bib</DialogTitle>
      <DialogContent>
        <Typography sx={{ fontSize: 40, fontWeight: 700, textAlign: "center", minHeight: 52 }}>{value || "—"}</Typography>
        <Keypad onDigit={(d) => setValue((v) => (v + d).slice(0, 6))} onBack={() => setValue((v) => v.slice(0, -1))} />
      </DialogContent>
      <DialogActions>
        <Button onClick={onCancel}>Cancel</Button>
        <Button variant="contained" disabled={!value.trim()} onClick={() => onSave(value)}>Save</Button>
      </DialogActions>
    </Dialog>
  );
}
