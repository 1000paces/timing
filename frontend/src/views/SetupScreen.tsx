import { useMutation, useQuery } from "@apollo/client/react";
import Alert from "@mui/material/Alert";
import Box from "@mui/material/Box";
import NumbersIcon from "@mui/icons-material/Numbers";
import DeleteIcon from "@mui/icons-material/Delete";
import EditIcon from "@mui/icons-material/Edit";
import Button from "@mui/material/Button";
import Dialog from "@mui/material/Dialog";
import DialogActions from "@mui/material/DialogActions";
import DialogTitle from "@mui/material/DialogTitle";
import IconButton from "@mui/material/IconButton";
import LinearProgress from "@mui/material/LinearProgress";
import Paper from "@mui/material/Paper";
import Stack from "@mui/material/Stack";
import Table from "@mui/material/Table";
import TableBody from "@mui/material/TableBody";
import TableCell from "@mui/material/TableCell";
import TableHead from "@mui/material/TableHead";
import TableRow from "@mui/material/TableRow";
import Tooltip from "@mui/material/Tooltip";
import Typography from "@mui/material/Typography";
import { useEffect, useState } from "react";
import { formatClock, formatScheduled } from "../format";
import {
  ASSIGN_BIBS,
  DELETE_RACE,
  DISCIPLINES,
  EVENT,
  STANDINGS,
  UPDATE_EVENT,
  type AssignBibsResult,
  type DisciplinesData,
  type EventData,
  type EventInput,
  type MutationResult,
  type RaceInfo,
  type StandingsData,
} from "../queries";
import { cohortLapWarnings } from "../races";
import { canAct as roleCanAct, isSignedOutError } from "../roles";
import type { Official } from "../session";
import { CheckpointsEditor } from "./CheckpointsEditor";
import { EventFields } from "./EventFields";
import { EventNav } from "./EventNav";
import { PhonesPanel } from "./PhonesPanel";
import { RaceDialog } from "./RaceDialog";

const GENDER: Record<string, string> = { men: "Men", women: "Women", open: "Open" };

type Props = { eventId: string; official: Official; onSignedOut: () => void };

export function SetupScreen({ eventId, official, onSignedOut }: Props) {
  const event = useQuery<EventData>(EVENT, { variables: { id: eventId }, fetchPolicy: "cache-and-network" });
  const disciplines = useQuery<DisciplinesData>(DISCIPLINES);
  const standings = useQuery<StandingsData>(STANDINGS, { variables: { eventId }, fetchPolicy: "network-only" });
  const [updateEvent] = useMutation<{ updateEvent: MutationResult }>(UPDATE_EVENT);
  const [deleteRace] = useMutation<{ deleteRace: MutationResult }>(DELETE_RACE);
  const [assignBibs] = useMutation<AssignBibsResult>(ASSIGN_BIBS);
  const [details, setDetails] = useState<EventInput | null>(null);
  const [editing, setEditing] = useState<RaceInfo | "new" | null>(null);
  const [deleting, setDeleting] = useState<RaceInfo | null>(null);
  const [message, setMessage] = useState<{ severity: "error" | "success"; text: string } | null>(null);

  useEffect(() => {
    if (isSignedOutError(event.error ?? disciplines.error)) onSignedOut();
  }, [event.error, disciplines.error, onSignedOut]);

  const data = event.data?.event;
  useEffect(() => {
    if (data && !details) {
      setDetails({ name: data.name, date: data.date, location: data.location, discipline: data.discipline, subDiscipline: data.subDiscipline, finishWithLeader: data.finishWithLeader, ageNextYear: data.ageNextYear, timezone: data.timezone, raceFormat: data.raceFormat, bibFrom: data.bibFrom, bibTo: data.bibTo });
    }
  }, [data, details]);

  if (!data || !details || !disciplines.data) {
    return <Box sx={{ p: 3 }}>{event.error ? <Alert severity="error">{event.error.message}</Alert> : <LinearProgress />}</Box>;
  }

  const startsById = new Map((standings.data?.standings.races ?? []).map((r) => [r.race.id, r.startAtMs]));
  const refetch = () => {
    void event.refetch().catch(() => {});
    void standings.refetch().catch(() => {});
  };

  async function saveDetails() {
    setMessage(null);
    try {
      const { data: result } = await updateEvent({ variables: { id: eventId, ...details } });
      const errors = result?.updateEvent.errors ?? [];
      setMessage(errors.length ? { severity: "error", text: errors.join("; ") } : { severity: "success", text: "Event saved" });
      refetch();
    } catch (e) {
      setMessage({ severity: "error", text: (e as Error).message });
    }
  }

  async function confirmDelete(race: RaceInfo) {
    setDeleting(null);
    try {
      const { data: result } = await deleteRace({ variables: { id: race.id } });
      const errors = result?.deleteRace.errors ?? [];
      setMessage(errors.length ? { severity: "error", text: errors.join("; ") } : null);
    } catch (e) {
      setMessage({ severity: "error", text: (e as Error).message });
    }
    refetch();
  }

  async function assignRaceBibs(race: RaceInfo) {
    setMessage(null);
    try {
      const result = (await assignBibs({ variables: { eventId, raceId: race.id } })).data?.assignBibs;
      if (!result) return;
      const n = result.assigned.length;
      const lines = [...result.errors, `${race.name}: ${n === 0 ? "no bibs to assign" : `assigned ${n} bib${n === 1 ? "" : "s"}`}`, ...result.unfilled];
      setMessage({ severity: result.errors.length || result.unfilled.length ? "error" : "success", text: lines.join(" · ") });
    } catch (e) {
      setMessage({ severity: "error", text: (e as Error).message });
    }
  }

  const warnings = cohortLapWarnings(data.races);

  return (
    <Box sx={{ p: 2, maxWidth: 1100 }}>
      <EventNav eventId={eventId} eventName={data.name} current="setup" admin={official.role === "admin"} />
      {message && <Alert severity={message.severity} sx={{ mb: 2 }} onClose={() => setMessage(null)}>{message.text}</Alert>}
      <Stack direction="row" spacing={2} sx={{ alignItems: "start" }}>
        <Paper sx={{ p: 2, width: 340, flexShrink: 0 }}>
          <Typography variant="h6" component="h2">Event</Typography>
          <EventFields value={details} onChange={setDetails} disciplines={disciplines.data.disciplines} bibRange />
          <Button variant="contained" sx={{ mt: 2 }} onClick={saveDetails}>Save event</Button>
        </Paper>
        <Paper sx={{ p: 2, flex: 1 }}>
          <Stack direction="row" sx={{ alignItems: "center", mb: 1 }}>
            <Typography variant="h6" component="h2" sx={{ flex: 1 }}>Races</Typography>
            <Button variant="contained" onClick={() => setEditing("new")}>Add race</Button>
          </Stack>
          {warnings.map((w) => (
            <Alert key={w} severity="warning" sx={{ mb: 1 }}>{w}</Alert>
          ))}
          {data.races.length === 0 && <Typography color="text.secondary">No races yet.</Typography>}
          {data.races.length > 0 && (
            <Table size="small">
              <TableHead>
                <TableRow>
                  <TableCell>Race</TableCell>
                  <TableCell>Scheduled</TableCell>
                  <TableCell>Gender</TableCell>
                  <TableCell>Laps / duration</TableCell>
                  <TableCell align="center">Bib range</TableCell>
                  <TableCell>Finish with leader</TableCell>
                  <TableCell>Started</TableCell>
                  <TableCell align="right">Actions</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {data.races.map((race) => {
                  const started = startsById.get(race.id);
                  return (
                    <TableRow key={race.id} hover>
                      <TableCell>{race.name}</TableCell>
                      <TableCell>{formatScheduled(race.scheduledAtMs)}</TableCell>
                      <TableCell>{GENDER[race.gender] ?? race.gender}</TableCell>
                      <TableCell>
                        {[race.expectedLaps ? `${race.expectedLaps} laps` : null, race.expectedDurationMs ? `${race.expectedDurationMs / 60_000} min` : null]
                          .filter(Boolean)
                          .join(" · ") || "—"}
                      </TableCell>
                      <TableCell align="center">{race.bibFrom != null && race.bibTo != null ? `${race.bibFrom}–${race.bibTo}` : "—"}</TableCell>
                      <TableCell>
                        {race.finishWithLeader ? "On" : "Off"}
                        {race.finishWithLeaderOverride == null && <Typography component="span" variant="caption" color="text.secondary"> (event)</Typography>}
                      </TableCell>
                      <TableCell>{started ? formatClock(started) : "—"}</TableCell>
                      <TableCell align="right" sx={{ whiteSpace: "nowrap" }}>
                        <Tooltip title="Assign bibs">
                          <IconButton size="small" aria-label={`Assign bibs for ${race.name}`} onClick={() => void assignRaceBibs(race)}>
                            <NumbersIcon fontSize="small" />
                          </IconButton>
                        </Tooltip>
                        <IconButton size="small" aria-label={`Edit ${race.name}`} onClick={() => setEditing(race)}>
                          <EditIcon fontSize="small" />
                        </IconButton>
                        <IconButton size="small" color="error" aria-label={`Delete ${race.name}`} onClick={() => setDeleting(race)}>
                          <DeleteIcon fontSize="small" />
                        </IconButton>
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          )}
        </Paper>
      </Stack>

      {data.raceFormat === "course" && <CheckpointsEditor key={JSON.stringify([data.checkpoints, data.finishDistanceKm, data.finishCutoffAtMs, data.timezone])} event={data} onSaved={refetch} />}
      <PhonesPanel eventId={eventId} event={data} />
      {editing && (
        <RaceDialog
          eventId={eventId}
          race={editing === "new" ? null : editing}
          startAtMs={editing === "new" ? null : (startsById.get(editing.id) ?? null)}
          canSetStart={roleCanAct(official.role)}
          onClose={(saved) => {
            setEditing(null);
            if (saved) refetch();
          }}
        />
      )}
      <Dialog open={deleting != null} onClose={() => setDeleting(null)}>
        <DialogTitle>Delete {deleting?.name}?</DialogTitle>
        <DialogActions>
          <Button onClick={() => setDeleting(null)}>Cancel</Button>
          <Button color="error" variant="contained" onClick={() => deleting && confirmDelete(deleting)}>Delete</Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}
