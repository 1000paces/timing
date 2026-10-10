import { useMutation, useQuery } from "@apollo/client/react";
import CloseIcon from "@mui/icons-material/Close";
import MoreVertIcon from "@mui/icons-material/MoreVert";
import Alert from "@mui/material/Alert";
import Box from "@mui/material/Box";
import Button from "@mui/material/Button";
import Chip from "@mui/material/Chip";
import Dialog from "@mui/material/Dialog";
import DialogActions from "@mui/material/DialogActions";
import DialogContent from "@mui/material/DialogContent";
import DialogTitle from "@mui/material/DialogTitle";
import Drawer from "@mui/material/Drawer";
import IconButton from "@mui/material/IconButton";
import LinearProgress from "@mui/material/LinearProgress";
import List from "@mui/material/List";
import ListItem from "@mui/material/ListItem";
import Menu from "@mui/material/Menu";
import MenuItem from "@mui/material/MenuItem";
import Stack from "@mui/material/Stack";
import Table from "@mui/material/Table";
import TableBody from "@mui/material/TableBody";
import TableCell from "@mui/material/TableCell";
import TableHead from "@mui/material/TableHead";
import TableRow from "@mui/material/TableRow";
import TextField from "@mui/material/TextField";
import Typography from "@mui/material/Typography";
import { useCallback, useState } from "react";
import { formatClock, formatElapsed, formatGap } from "../format";
import {
  FLAG_FINISH,
  INSERT_CROSSING,
  MOVE_CROSSING,
  PULL_RACER,
  RACER,
  REVERT_RULING,
  VOID_CROSSING,
  type CheckpointInfo,
  type FixResults,
  type RacerCrossing,
  type RacerDetail,
  type RacerFix,
} from "../queries";
import { kindLabel, midpoint, positionLabel } from "../racerPanel";
import { STATUS_COLOR, statusLabel } from "../races";
import { useEventChanges } from "../useEventChanges";
import { TimeDialog } from "./TimeDialog";
import { RacerStatusMenu } from "./RacerStatusMenu";

type Props = {
  eventId: string;
  bib: string;
  canAct: boolean; // chief and above: fixing controls
  racerNames: Map<string, string>; // bib → name, for Move to bib
  checkpoints?: CheckpointInfo[]; // a course event's checkpoints, in order (none for laps)
  onClose: () => void;
  onChanged: () => void; // refresh the standings behind the panel
};

type Asking =
  | { kind: "insert"; atMs: number }
  | { kind: "pull"; atMs: number }
  | { kind: "move"; crossing: RacerCrossing }
  | { kind: "undo"; fix: RacerFix }
  | null;

// One racer's race: crossings with what they counted as, lap times and
// positions, and (for chiefs) fixes and undo. Opened from a Results row.
export function RacerPanel({ eventId, bib, canAct, racerNames, checkpoints = [], onClose, onChanged }: Props) {
  const names = new Map(checkpoints.map((c) => [c.id, c.name] as const));
  const [where, setWhere] = useState(""); // checkpoint id to insert a crossing at; "" is the finish
  const racer = useQuery<{ racer: RacerDetail }>(RACER, { variables: { eventId, bib }, fetchPolicy: "cache-and-network" });
  const [voidCrossing] = useMutation<FixResults>(VOID_CROSSING);
  const [moveCrossing] = useMutation<FixResults>(MOVE_CROSSING);
  const [insertCrossing] = useMutation<FixResults>(INSERT_CROSSING);
  const [pullRacer] = useMutation<FixResults>(PULL_RACER);
  const [flagFinish] = useMutation<FixResults>(FLAG_FINISH);
  const [revert] = useMutation<FixResults>(REVERT_RULING);
  const [menu, setMenu] = useState<{ anchor: HTMLElement; crossing: RacerCrossing; index: number } | null>(null);
  const [asking, setAsking] = useState<Asking>(null);
  const [error, setError] = useState<string | null>(null);

  const { refetch } = racer;
  const reload = useCallback(() => {
    refetch().catch(() => {});
  }, [refetch]);
  // Broadcasts already refresh the standings behind the panel; only our own fixes need to.
  useEventChanges(eventId, reload);
  const refresh = useCallback(() => {
    reload();
    onChanged();
  }, [reload, onChanged]);

  async function run(action: () => Promise<{ data?: FixResults | null }>) {
    setError(null);
    try {
      const data = (await action()).data ?? {};
      const result = Object.values(data)[0];
      if (result?.errors.length) setError(result.errors.join("; "));
    } catch (e) {
      setError((e as Error).message);
    }
    refresh();
  }

  const r = racer.data?.racer;
  const counted = r ? r.crossings.filter((c) => c.lap != null) : [];

  function chosen(action: string) {
    if (!menu || !r) return;
    const { crossing, index } = menu;
    setMenu(null);
    if (action === "void") void run(() => voidCrossing({ variables: { eventId, ref: crossing.ref } }));
    if (action === "finish") void run(() => flagFinish({ variables: { eventId, bib, ref: crossing.ref } }));
    if (action === "pull") void run(() => pullRacer({ variables: { eventId, bib, atMs: crossing.atMs } }));
    if (action === "move") setAsking({ kind: "move", crossing });
    if (action === "insert") {
      setWhere(crossing.checkpointId ?? "");
      const before = r.crossings.slice(0, index).filter((c) => c.lap != null).at(-1)?.atMs ?? r.startAtMs ?? crossing.atMs;
      setAsking({ kind: "insert", atMs: midpoint(before, crossing.atMs) });
    }
  }

  return (
    <Drawer anchor="right" open onClose={onClose} slotProps={{ paper: { "data-testid": "racer-panel", sx: { width: { xs: "100%", sm: 520 } } } as object }}>
      <Box sx={{ p: 2 }}>
        <Stack direction="row" sx={{ alignItems: "center", gap: 1 }}>
          <Typography variant="h6" sx={{ flex: 1 }}>
            Bib {bib}{r ? ` · ${r.name}` : ""}
          </Typography>
          {r && canAct && <RacerStatusMenu eventId={eventId} row={{ bib, name: r.name, status: r.status }} label="Racer actions" onChanged={refresh} />}
          <IconButton aria-label="Close" onClick={onClose} edge="end"><CloseIcon /></IconButton>
        </Stack>
        {racer.error && <Alert severity="error">{racer.error.message}</Alert>}
        {!r && !racer.error && <LinearProgress />}
        {error && <Alert severity="error" onClose={() => setError(null)} sx={{ my: 1 }}>{error}</Alert>}
        {r && (
          <>
            <Stack direction="row" sx={{ alignItems: "center", gap: 1, flexWrap: "wrap", mb: 1 }}>
              <Typography color="text.secondary">{r.race.name}</Typography>
              <Chip data-testid="panel-status" size="small" color={STATUS_COLOR[r.status] ?? "default"} label={statusLabel(r.status)} />
              {r.place != null && <Typography color="text.secondary">{positionLabel(r.place)}</Typography>}
            </Stack>
            <Typography data-testid="panel-summary" variant="body2" sx={{ mb: 1 }}>
              {[
                r.startAtMs != null ? `Start ${formatClock(r.startAtMs)}` : "Not started",
                `${r.laps} ${r.laps === 1 ? "lap" : "laps"}`,
                r.elapsedMs != null ? formatElapsed(r.elapsedMs) : null,
                formatGap(r.gapLapsDown, r.gapMs) || null,
                r.pullAtMs != null ? `pulled at ${formatClock(r.pullAtMs)}` : null,
              ].filter(Boolean).join(" · ")}
            </Typography>

            {r.splits.length > 0 && (
              <>
                <Typography variant="subtitle2">Checkpoints</Typography>
                <Table size="small" data-testid="panel-splits" sx={{ mb: 2 }}>
                  <TableHead>
                    <TableRow>
                      <TableCell>Point</TableCell>
                      <TableCell>Crossed</TableCell>
                      <TableCell align="right">Segment</TableCell>
                      <TableCell align="right">Elapsed</TableCell>
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {r.splits.map((s) => (
                      <TableRow key={s.checkpointId ?? "finish"} data-testid="panel-split">
                        <TableCell>
                          {s.checkpointId ? (names.get(s.checkpointId) ?? "Checkpoint") : "Finish"}
                          {s.inserted && <Chip size="small" variant="outlined" label="inserted" sx={{ ml: 1 }} />}
                        </TableCell>
                        <TableCell sx={{ fontFamily: "monospace" }}>{s.atMs != null ? formatClock(s.atMs) : "—"}</TableCell>
                        <TableCell align="right">{s.segmentMs != null ? formatElapsed(s.segmentMs) : "—"}</TableCell>
                        <TableCell align="right">{s.elapsedMs != null ? formatElapsed(s.elapsedMs) : "—"}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </>
            )}

            <Table size="small">
              <TableHead>
                <TableRow>
                  <TableCell>Lap</TableCell>
                  <TableCell>Crossed</TableCell>
                  <TableCell align="right">Lap time</TableCell>
                  <TableCell align="right">Pos</TableCell>
                  <TableCell>Source</TableCell>
                  {canAct && <TableCell />}
                </TableRow>
              </TableHead>
              <TableBody>
                {r.crossings.map((c, i) => {
                  const ignored = c.kind === "SPLIT" ? null : kindLabel(c.kind);
                  return (
                    <TableRow key={c.ref} data-testid="panel-crossing" sx={ignored ? { "& td": { color: "text.disabled" } } : undefined}>
                      <TableCell>{c.kind === "FINISH" ? "Finish" : c.kind === "SPLIT" ? kindLabel(c.kind, c.checkpointId, names) : (c.lap ?? "—")}</TableCell>
                      <TableCell sx={{ fontFamily: "monospace" }}>{formatClock(c.atMs)}</TableCell>
                      <TableCell align="right">{c.lapMs != null ? formatElapsed(c.lapMs) : ""}</TableCell>
                      <TableCell align="right">{c.lap != null && r.lapPositions[c.lap - 1] ? positionLabel(r.lapPositions[c.lap - 1]) : ""}</TableCell>
                      <TableCell>
                        {c.source}
                        {ignored && <Chip size="small" variant="outlined" label={ignored} sx={{ ml: 1 }} />}
                      </TableCell>
                      {canAct && (
                        <TableCell align="right" padding="none">
                          <IconButton size="small" aria-label="Crossing actions" onClick={(e) => setMenu({ anchor: e.currentTarget, crossing: c, index: i })}>
                            <MoreVertIcon fontSize="small" />
                          </IconButton>
                        </TableCell>
                      )}
                    </TableRow>
                  );
                })}
                {r.crossings.length === 0 && (
                  <TableRow><TableCell colSpan={6}><Typography color="text.secondary">No crossings yet.</Typography></TableCell></TableRow>
                )}
              </TableBody>
            </Table>

            {canAct && (
              <Stack direction="row" spacing={1} sx={{ my: 2 }}>
                <Button size="small" variant="outlined"
                  onClick={() => { setWhere(""); setAsking({ kind: "insert", atMs: (counted.at(-1)?.atMs ?? r.startAtMs ?? Date.now()) + (counted.at(-1)?.lapMs ?? 60_000) }); }}>
                  Insert crossing at…
                </Button>
                <Button size="small" variant="outlined" color="warning" onClick={() => setAsking({ kind: "pull", atMs: Date.now() })}>Pull now</Button>
              </Stack>
            )}

            <Typography variant="subtitle2" sx={{ mt: 2 }}>This racer's fixes</Typography>
            {r.rulings.length === 0 && <Typography variant="body2" color="text.secondary">None.</Typography>}
            <List dense disablePadding>
              {r.rulings.map((f) => (
                <ListItem key={f.id} data-testid="panel-fix" disableGutters sx={{ gap: 1 }}>
                  <Box sx={{ flex: 1, textDecoration: f.undone ? "line-through" : "none", color: f.undone ? "text.disabled" : "text.primary" }}>
                    <Typography variant="body2">{f.description}</Typography>
                    <Typography variant="caption" color="text.secondary">
                      {f.officialName ?? "Hub"} · {formatClock(f.createdAtMs)}
                    </Typography>
                  </Box>
                  {f.undone ? (
                    <Typography variant="caption" color="text.secondary">undone by {f.undoneBy ?? "an official"}</Typography>
                  ) : (
                    canAct && <Button size="small" onClick={() => setAsking({ kind: "undo", fix: f })}>Undo</Button>
                  )}
                </ListItem>
              ))}
            </List>
          </>
        )}
      </Box>

      <Menu anchorEl={menu?.anchor} open={menu != null} onClose={() => setMenu(null)}>
        <MenuItem onClick={() => chosen("void")}>Void</MenuItem>
        {menu && !menu.crossing.inserted && <MenuItem onClick={() => chosen("move")}>Move to bib…</MenuItem>}
        <MenuItem onClick={() => chosen("pull")}>Pull here</MenuItem>
        <MenuItem onClick={() => chosen("finish")}>Finish here</MenuItem>
        <MenuItem onClick={() => chosen("insert")}>Insert missed crossing before</MenuItem>
      </Menu>

      {asking?.kind === "insert" || asking?.kind === "pull" ? (
        <TimeDialog title={asking.kind === "insert" ? "Insert crossing" : "Pull racer"} action={asking.kind === "insert" ? "Insert" : "Pull"} atMs={asking.atMs}
          onCancel={() => setAsking(null)}
          onSave={(atMs) => {
            const kind = asking.kind;
            setAsking(null);
            void run(() => (kind === "insert" ? insertCrossing({ variables: { eventId, bib, atMs, checkpointId: where || null } }) : pullRacer({ variables: { eventId, bib, atMs } })));
          }}>
          {asking.kind === "insert" && checkpoints.length > 0 && (
            <TextField select label="Where" value={where} onChange={(e) => setWhere(e.target.value)} fullWidth sx={{ mt: 2 }}>
              <MenuItem value="">Finish</MenuItem>
              {checkpoints.map((c) => <MenuItem key={c.id} value={c.id}>{c.name}</MenuItem>)}
            </TextField>
          )}
        </TimeDialog>
      ) : null}
      {asking?.kind === "move" && (
        <MoveDialog crossing={asking.crossing} racerNames={racerNames} onCancel={() => setAsking(null)}
          onSave={(to) => {
            const ref = asking.crossing.ref;
            setAsking(null);
            void run(() => moveCrossing({ variables: { eventId, captureId: ref, bib: to } }));
          }} />
      )}
      <Dialog open={asking?.kind === "undo"} onClose={() => setAsking(null)}>
        <DialogTitle>Undo {asking?.kind === "undo" ? `"${asking.fix.description}"` : ""}?</DialogTitle>
        <DialogActions>
          <Button onClick={() => setAsking(null)}>Cancel</Button>
          <Button variant="contained" onClick={() => {
            if (asking?.kind !== "undo") return;
            const id = asking.fix.id;
            setAsking(null);
            void run(() => revert({ variables: { id } }));
          }}>Undo</Button>
        </DialogActions>
      </Dialog>
    </Drawer>
  );
}

function MoveDialog({ crossing, racerNames, onCancel, onSave }: { crossing: RacerCrossing; racerNames: Map<string, string>; onCancel: () => void; onSave: (bib: string) => void }) {
  const [bib, setBib] = useState("");
  const who = racerNames.get(bib.trim());
  return (
    <Dialog open onClose={onCancel}>
      <DialogTitle>Move crossing {formatClock(crossing.atMs)} to bib…</DialogTitle>
      <DialogContent>
        <TextField label="Bib" value={bib} onChange={(e) => setBib(e.target.value)} autoFocus sx={{ mt: 1 }}
          helperText={bib.trim() ? (who ?? "Not registered in this event") : " "} error={!!bib.trim() && !who}
          slotProps={{ htmlInput: { inputMode: "numeric", style: { textAlign: "center" } } }} />
      </DialogContent>
      <DialogActions>
        <Button onClick={onCancel}>Cancel</Button>
        <Button variant="contained" disabled={!who} onClick={() => onSave(bib.trim())}>Move</Button>
      </DialogActions>
    </Dialog>
  );
}
