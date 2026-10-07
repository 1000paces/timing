import CloseIcon from "@mui/icons-material/Close";
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
import useMediaQuery from "@mui/material/useMediaQuery";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { formatClock, formatElapsed } from "../../src/format";
import { hubApi } from "./api";
import { openCaptureDb, type CaptureDb, type Pairing } from "./db";
import { Keypad } from "./Keypad";
import { allEntries, appendBibAssignment, appendCapture, appendVoid, canUnpair, startNewPairing, type Entry } from "./log";
import { captureRows, type Row } from "./rows";
import { checkStorage, storageWarning, type StorageHealth } from "./storageHealth";
import { createSync, type Sync, type SyncState } from "./sync";
import { SyncPill } from "./SyncPill";

const FLAG = { missed: "Missed lap?", long: "Long lap", short: "Short lap" } as const;
const PAGE = 20;
const DISMISSED = "timing:storage-warning-dismissed";

// The tap time: the phone's high-resolution clock at the Enter press.
const tapTime = () => performance.timeOrigin + performance.now();

export function App() {
  const [db, setDb] = useState<CaptureDb | null>(null);
  const [pairing, setPairing] = useState<Pairing | null | undefined>(undefined);
  const [health, setHealth] = useState<StorageHealth | null>(null);
  const [dismissed, setDismissed] = useState(() => {
    try {
      return localStorage.getItem(DISMISSED) === "1";
    } catch {
      return false;
    }
  });
  useEffect(() => {
    void checkStorage().then(setHealth);
    void openCaptureDb().then(async (opened) => {
      setDb(opened);
      setPairing((await opened.get("pairing", "pairing")) ?? null);
    });
  }, []);
  const warning = health ? storageWarning(health) : null;
  function dismiss() {
    setDismissed(true);
    try {
      localStorage.setItem(DISMISSED, "1");
    } catch {
      // not remembered; fine
    }
  }

  if (warning === "insecure") {
    // Nothing can be kept safely: don't offer capture at all.
    return (
      <Alert severity="error" square>
        This page isn't secure, so the phone can't save crossings. Install the hub certificate from <a href="/onboarding">/onboarding</a>, then open the app from the hub's https:// address.
      </Alert>
    );
  }
  if (!db || pairing === undefined) return <LinearProgress />;
  const token = new URLSearchParams(window.location.search).get("pair");
  return (
    <Box sx={{ height: "100dvh", display: "flex", flexDirection: "column" }}>
      {warning === "not-permanent" && !dismissed && (
        <Alert severity="info" square onClose={dismiss}>
          This browser hasn't promised to keep the phone's crossings permanently (they're saved, and safe on the hub once synced). Add the app to your home screen to make them permanent.
        </Alert>
      )}
      {token || !pairing ? (
        <PairScreen db={db} token={token ?? ""} paired={pairing} onPaired={setPairing} onCancel={() => {
          window.history.replaceState(null, "", window.location.pathname);
          setPairing(pairing ? { ...pairing } : null);
        }} />
      ) : (
        <CaptureScreen db={db} pairing={pairing} health={health} onUnpaired={() => setPairing(null)} />
      )}
    </Box>
  );
}

// Download the phone's whole log as JSON (a last-resort backup).
async function exportLog(db: CaptureDb) {
  const pairing = await db.get("pairing", "pairing");
  const body = { pairing: pairing ? { deviceId: pairing.deviceId, eventId: pairing.eventId, name: pairing.name } : null, entries: await allEntries(db), archive: await db.getAll("archive") };
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([JSON.stringify(body, null, 2)], { type: "application/json" }));
  a.download = `capture-log-${(pairing?.name ?? "phone").replace(/\W+/g, "-")}-${new Date().toISOString().slice(0, 19)}.json`;
  a.click();
  URL.revokeObjectURL(a.href);
}

function PairScreen({ db, token, paired, onPaired, onCancel }: {
  db: CaptureDb;
  token: string;
  paired: Pairing | null;
  onPaired: (p: Pairing) => void;
  onCancel: () => void;
}) {
  const [code, setCode] = useState(token);
  const [name, setName] = useState(paired?.name ?? "");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [unsentCount, setUnsentCount] = useState(0);
  const [confirmed, setConfirmed] = useState(false);
  useEffect(() => {
    void (async () => {
      const entries = await allEntries(db);
      const ack = ((await db.get("state", "ackSeq")) as number | undefined) ?? 0;
      setUnsentCount(Math.max(0, (entries.at(-1)?.device_seq ?? 0) - ack));
    })();
  }, [db]);

  async function pair() {
    setBusy(true);
    setError(null);
    try {
      const result = await hubApi(() => null).pair(code, name.trim() || "Phone");
      const next = { deviceId: result.device_id, credential: result.credential, eventId: result.event_id, name: name.trim() || "Phone" };
      await startNewPairing(db, next); // the old log is archived on the phone, never deleted
      window.history.replaceState(null, "", window.location.pathname);
      onPaired(next);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  const blocked = unsentCount > 0 && !confirmed;
  return (
    <Box sx={{ p: 3, overflowY: "auto" }}>
      <Typography variant="h5" gutterBottom>Pair this phone</Typography>
      <Stack spacing={2}>
        {unsentCount > 0 && (
          <Alert severity="warning">
            {unsentCount} crossing{unsentCount === 1 ? "" : "s"} on this phone haven't reached the hub. Export the log and give it to an official before pairing again.
            The old log stays on this phone either way.
            <Stack direction="row" spacing={1} sx={{ mt: 1 }}>
              <Button size="small" variant="outlined" onClick={() => void exportLog(db)}>Export log</Button>
              <Button size="small" onClick={() => setConfirmed(true)}>Pair anyway</Button>
            </Stack>
          </Alert>
        )}
        <Typography variant="body2" color="text.secondary">
          On the console: Capture (or Event) → Phones → Pair a phone. Scan the QR code, or type the code shown under it.
        </Typography>
        <TextField label="Pairing code" value={code} onChange={(e) => setCode(e.target.value.toUpperCase())} placeholder="K7Q-4MX"
          autoFocus={!token} slotProps={{ htmlInput: { autoCapitalize: "characters", autoCorrect: "off", spellCheck: false, style: { letterSpacing: 4, fontSize: 24 } } }} />
        <TextField label="Phone name" value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Finish line phone 2" autoFocus={!!token} />
        {error && <Alert severity="error">{error}</Alert>}
        <Button variant="contained" size="large" disabled={busy || blocked || !code.trim()} onClick={() => void pair()}>Pair</Button>
        {paired && <Button onClick={onCancel}>Back to capture</Button>}
      </Stack>
    </Box>
  );
}

function CaptureScreen({ db, pairing, health, onUnpaired }: { db: CaptureDb; pairing: Pairing; health: StorageHealth | null; onUnpaired: () => void }) {
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
  const short = useMediaQuery("(orientation: landscape) and (max-height: 500px)"); // a phone in landscape
  const landscape = useMediaQuery("(orientation: landscape)");

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

  const rows = useMemo(() => captureRows(entries, state?.roster ?? null, state?.status ?? null, state?.ackSeq ?? 0), [entries, state?.roster, state?.status, state?.ackSeq]);
  const visible = onlyBib ? rows.filter((r) => r.bib === onlyBib) : rows;
  const racerFor = useMemo(() => {
    const roster = state?.roster;
    const races = new Map((roster?.event.races ?? []).map((r) => [r.id, r.name]));
    const racers = new Map((roster?.racers ?? []).map((r) => [r.bib, { name: r.name, race: races.get(r.race_id) ?? null }]));
    return (bib: string) => racers.get(bib) ?? null;
  }, [state?.roster]);
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

  async function unpair() {
    setMenu(null);
    if (!canUnpair(lastSeq, (await db.get("state", "ackSeq")) as number ?? 0)) return setError("Can't unpair: some crossings haven't reached the hub yet.");
    await db.clear("pairing");
    onUnpaired();
  }

  return (
    // A fixed-height frame: the top bar and keypad stay put; only the log scrolls.
    // Portrait stacks keypad over log; landscape puts them side by side.
    <Box sx={{ flex: 1, minHeight: 0, display: "flex", flexDirection: "column", bgcolor: flash ? "success.dark" : "background.default", transition: "background-color 150ms" }}>
      <AppBar position="static" color="default" elevation={1}>
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
        <MenuItem disabled>
          Storage: secure {health?.secure ? "✓" : "✗"} · permanent {health?.persisted ? "✓" : "✗"} · offline app {health?.offlineApp ? "✓" : "✗"}
        </MenuItem>
        <MenuItem onClick={() => { setMenu(null); void exportLog(db); }}>Export log</MenuItem>
        <MenuItem onClick={() => void unpair()}>Unpair</MenuItem>
      </Menu>

      {state?.stopped && <Alert severity="error" square>Sync stopped — export the log (menu) and see an official.</Alert>}
      {state?.revoked && (
        <Alert severity="error" square>This phone was revoked on the hub, so new crossings can't be sent. Export the log (menu), give it to an official, and pair again.</Alert>
      )}
      {error && <Alert severity="error" square onClose={() => setError(null)}>{error}</Alert>}

      <Box sx={{
        flex: 1,
        minHeight: 0,
        display: "grid",
        gridTemplateRows: "auto minmax(0, 1fr)",
        "@media (orientation: landscape)": { gridTemplateRows: "minmax(0, 1fr)", gridTemplateColumns: "minmax(260px, 40%) minmax(0, 1fr)" },
      }}>
      <Box sx={{ p: short ? 1 : 2, overflowY: "auto", ...(landscape && { display: "flex", flexDirection: "column", minHeight: 0 }) }}>
        <Typography data-testid="bib-display" sx={{ fontSize: short ? 36 : 56, fontWeight: 700, textAlign: "center", lineHeight: 1.2, minHeight: short ? 44 : 68, letterSpacing: 4 }}>
          {bib || <Box component="span" sx={{ color: "text.disabled", fontSize: 24, letterSpacing: 0 }}>Bib (or Enter for no bib)</Box>}
        </Typography>
        <Box sx={landscape ? { flex: 1, minHeight: 0 } : undefined}>
          <Keypad compact={short} fill={landscape} onDigit={(d) => setBib((b) => (b + d).slice(0, 6))} onBack={() => setBib((b) => b.slice(0, -1))} onEnter={enter} />
        </Box>
      </Box>
      <Box data-testid="crossing-log" sx={{ overflowY: "auto", minHeight: 0, borderTop: 1, borderColor: "divider",
        "@media (orientation: landscape)": { borderTop: 0, borderLeft: 1, borderColor: "divider" } }}>

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
      </Box>
      </Box>

      {editing && <BibSheet row={editing} racerFor={racerFor} rosterLoaded={state?.roster != null} onCancel={() => setEditing(null)} onSave={(v) => void correct(editing, v)} />}
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

type RacerLookup = (bib: string) => { name: string; race: string | null } | null;

// Correct a crossing's bib with the same keypad: a big number, who that bib is,
// and Save where Enter sits on the main screen.
function BibSheet({ row, racerFor, rosterLoaded, onCancel, onSave }: {
  row: Row;
  racerFor: RacerLookup;
  rosterLoaded: boolean;
  onCancel: () => void;
  onSave: (bib: string) => void;
}) {
  const [value, setValue] = useState(row.bib ?? "");
  // The current bib shows dimmed; the first digit typed replaces it (Backspace edits it).
  const [touched, setTouched] = useState(false);
  const digit = (d: string) => {
    setValue((v) => (touched ? v + d : d).slice(0, 6));
    setTouched(true);
  };
  const back = () => {
    setValue((v) => v.slice(0, -1));
    setTouched(true);
  };
  // A phone in landscape: full screen, number on the left, keypad on the right.
  const wide = useMediaQuery("(orientation: landscape) and (max-height: 500px)");
  const typed = value.trim();
  const racer = typed ? racerFor(typed) : null;
  const save = () => typed && onSave(typed);
  const number = (
    <Box sx={{ textAlign: "center" }}>
      <Typography data-testid="sheet-bib" color={touched ? "text.primary" : "text.disabled"}
        sx={{ fontSize: wide ? 96 : 72, fontWeight: 700, lineHeight: 1, letterSpacing: 4 }}>{value || "—"}</Typography>
      <Typography data-testid="sheet-racer" sx={{ mt: 1, minHeight: 24 }} color={typed && !racer && rosterLoaded ? "error.main" : "text.secondary"} noWrap>
        {!typed ? "Type the bib" : racer ? [racer.name, racer.race].filter(Boolean).join(" · ") : rosterLoaded ? "Unknown bib" : "No roster yet"}
      </Typography>
      {row.bib && row.bib !== typed && <Typography variant="caption" color="text.secondary">was {row.bib}</Typography>}
    </Box>
  );
  const keypad = (
    <Keypad compact={wide} enterLabel="Save" onEnter={save}
      onDigit={digit} onBack={back} />
  );
  const header = (
    <Stack direction="row" sx={{ alignItems: "center" }}>
      <Typography id="correct-bib-title" variant="h6" sx={{ flex: 1 }}>Correct bib</Typography>
      <IconButton aria-label="Cancel" onClick={onCancel} edge="end"><CloseIcon /></IconButton>
    </Stack>
  );
  if (wide) {
    return (
      <Dialog open onClose={onCancel} fullScreen aria-labelledby="correct-bib-title">
        <Box sx={{ height: "100%", display: "grid", gridTemplateColumns: "minmax(0, 2fr) minmax(0, 3fr)", gap: 2, p: 2, boxSizing: "border-box" }}>
          <Stack sx={{ minHeight: 0 }}>
            {header}
            <Box sx={{ flex: 1, display: "flex", alignItems: "center", justifyContent: "center" }}>{number}</Box>
          </Stack>
          <Box sx={{ alignSelf: "center" }}>{keypad}</Box>
        </Box>
      </Dialog>
    );
  }
  return (
    <Dialog open onClose={onCancel} fullWidth aria-labelledby="correct-bib-title">
      <Box sx={{ p: 2 }}>
        {header}
        <Box sx={{ my: 2 }}>{number}</Box>
        {keypad}
      </Box>
    </Dialog>
  );
}
