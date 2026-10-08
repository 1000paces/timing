import { useMutation, useQuery } from "@apollo/client/react";
import Alert from "@mui/material/Alert";
import Box from "@mui/material/Box";
import Button from "@mui/material/Button";
import Checkbox from "@mui/material/Checkbox";
import Dialog from "@mui/material/Dialog";
import DialogActions from "@mui/material/DialogActions";
import DialogContent from "@mui/material/DialogContent";
import DialogContentText from "@mui/material/DialogContentText";
import DialogTitle from "@mui/material/DialogTitle";
import LinearProgress from "@mui/material/LinearProgress";
import Paper from "@mui/material/Paper";
import Stack from "@mui/material/Stack";
import Table from "@mui/material/Table";
import TableBody from "@mui/material/TableBody";
import TableCell from "@mui/material/TableCell";
import TableHead from "@mui/material/TableHead";
import TableRow from "@mui/material/TableRow";
import TableSortLabel from "@mui/material/TableSortLabel";
import Typography from "@mui/material/Typography";
import { useCallback, useEffect, useRef, useState } from "react";
import { formatClock, formatScheduled } from "../format";
import {
  EVENT,
  START_RACES,
  STANDINGS,
  UNSTART_RACE,
  type EventData,
  type StandingsData,
  type StartRacesResult,
  type UnstartRaceResult,
} from "../queries";
import { sortRaces, startSortFromSearch, startSortToSearch, type StartRow, type StartSort } from "../races";
import { initialSearch, showSearch } from "../rememberedSearch";
import { canAct as roleCanAct, isSignedOutError } from "../roles";
import type { Official } from "../session";
import { useEventChanges } from "../useEventChanges";
import { EventNav } from "./EventNav";

type Row = StartRow;

type Props = { eventId: string; official: Official; onSignedOut: () => void };

export function StartScreen({ eventId, official, onSignedOut }: Props) {
  const event = useQuery<EventData>(EVENT, { variables: { id: eventId } });
  const standings = useQuery<StandingsData>(STANDINGS, { variables: { eventId }, pollInterval: 5000, fetchPolicy: "network-only" });
  const [startRaces] = useMutation<StartRacesResult>(START_RACES);
  const [unstartRace] = useMutation<UnstartRaceResult>(UNSTART_RACE);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [starting, setStarting] = useState(false);
  const startingRef = useRef(false); // a double-click's second event must see it at once
  const [confirm, setConfirm] = useState<Row | null>(null);
  const [error, setError] = useState<string | null>(null);
  const sortKey = `starts:${eventId}`;
  const [sort, setSort] = useState<StartSort>(() => startSortFromSearch(initialSearch(sortKey, window.location.search)));
  useEffect(() => showSearch(sortKey, startSortToSearch(sort)), [sortKey, sort]);

  const refresh = useCallback(() => {
    standings.refetch().catch(() => {});
  }, [standings]);
  useEventChanges(eventId, refresh);

  const firstError = event.error ?? standings.error;
  useEffect(() => {
    if (isSignedOutError(firstError)) onSignedOut();
  }, [firstError, onSignedOut]);

  if (!event.data) {
    return <Box sx={{ p: 3 }}>{event.error ? <Alert severity="error">{event.error.message}</Alert> : <LinearProgress />}</Box>;
  }

  const startsById = new Map((standings.data?.standings.races ?? []).map((r) => [r.race.id, r.startAtMs]));
  const loaded = Boolean(standings.data);
  const rows = sortRaces(
    event.data.event.races.map((r) => ({ id: r.id, name: r.name, scheduledAtMs: r.scheduledAtMs, startAtMs: startsById.get(r.id) ?? null })),
    sort,
  );
  // A header click sorts by that column; clicking the sorted column reverses it.
  const sortable = (key: StartSort["key"], label: string) => (
    <TableCell sortDirection={sort.key === key ? sort.dir : false}>
      <TableSortLabel active={sort.key === key} direction={sort.key === key ? sort.dir : "asc"}
        onClick={() => setSort(sort.key === key ? { key, dir: sort.dir === "asc" ? "desc" : "asc" } : { key, dir: "asc" })}>
        {label}
      </TableSortLabel>
    </TableCell>
  );
  const canAct = roleCanAct(official.role);

  function toggle(id: string) {
    setSelected((current) => {
      const next = new Set(current);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  async function start() {
    if (startingRef.current || selected.size === 0) return;
    startingRef.current = true;
    setStarting(true);
    setError(null);
    try {
      const { data } = await startRaces({ variables: { raceIds: [...selected] } });
      const errors = data?.startRaces.errors ?? [];
      if (errors.length) setError(errors.join("; "));
      else setSelected(new Set());
    } catch (e) {
      setError((e as Error).message);
    } finally {
      startingRef.current = false;
      setStarting(false);
      refresh();
    }
  }

  async function unstart(row: Row) {
    setConfirm(null);
    setError(null);
    try {
      const { data } = await unstartRace({ variables: { raceId: row.id } });
      const errors = data?.unstartRace.errors ?? [];
      if (errors.length) setError(errors.join("; "));
    } catch (e) {
      setError((e as Error).message);
    } finally {
      refresh();
    }
  }

  return (
    <Box sx={{ p: 2, maxWidth: 1000 }}>
      <EventNav eventId={eventId} eventName={event.data.event.name} current="starts" admin={official.role === "admin"} />
      <Paper sx={{ p: 2 }}>
        <Stack direction="row" sx={{ alignItems: "center", mb: 1 }}>
          <Typography variant="h6" component="h2" sx={{ flex: 1 }}>
            Starts
          </Typography>
          {canAct && (
            <Button variant="contained" color="success" size="large" onClick={start} disabled={starting || selected.size === 0}>
              Start
            </Button>
          )}
        </Stack>
        {!loaded && <LinearProgress sx={{ mb: 1 }} />}
        {standings.error && <Alert severity="error" sx={{ mb: 1 }}>{standings.error.message}</Alert>}
        {error && <Alert severity="error" sx={{ mb: 1 }}>{error}</Alert>}
        <Table size="small">
          <TableHead>
            <TableRow>
              {canAct && <TableCell padding="checkbox" />}
              {sortable("race", "Race")}
              {sortable("scheduled", "Scheduled")}
              {sortable("status", "Status")}
              {canAct && <TableCell align="right">Actions</TableCell>}
            </TableRow>
          </TableHead>
          <TableBody>
            {rows.map((row) => {
              const started = row.startAtMs != null;
              return (
                <TableRow key={row.id} hover={!started} selected={selected.has(row.id)}>
                  {canAct && (
                    <TableCell padding="checkbox">
                      <Checkbox
                        checked={selected.has(row.id)}
                        disabled={started || !loaded || starting}
                        onChange={() => toggle(row.id)}
                        slotProps={{ input: { "aria-label": `Select ${row.name}` } }}
                      />
                    </TableCell>
                  )}
                  <TableCell>{row.name}</TableCell>
                  <TableCell>{row.scheduledAtMs != null ? formatScheduled(row.scheduledAtMs) : "—"}</TableCell>
                  <TableCell>{started ? `Started ${formatClock(row.startAtMs!)}` : loaded ? "Not started" : "…"}</TableCell>
                  {canAct && (
                    <TableCell align="right">
                      {started && (
                        <Button color="error" variant="outlined" size="small" onClick={() => setConfirm(row)}>
                          Unstart
                        </Button>
                      )}
                    </TableCell>
                  )}
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      </Paper>

      <Dialog open={confirm != null} onClose={() => setConfirm(null)}>
        <DialogTitle>Unstart {confirm?.name}?</DialogTitle>
        <DialogContent>
          <DialogContentText>
            Its start at {confirm?.startAtMs != null ? formatClock(confirm.startAtMs) : "—"} is removed and its racers show as
            not started until you start it again.
          </DialogContentText>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setConfirm(null)}>Cancel</Button>
          <Button color="error" variant="contained" onClick={() => confirm && unstart(confirm)}>
            Unstart
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}
