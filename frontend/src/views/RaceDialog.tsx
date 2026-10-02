import { useMutation } from "@apollo/client/react";
import Alert from "@mui/material/Alert";
import Button from "@mui/material/Button";
import Dialog from "@mui/material/Dialog";
import DialogActions from "@mui/material/DialogActions";
import DialogContent from "@mui/material/DialogContent";
import DialogTitle from "@mui/material/DialogTitle";
import Stack from "@mui/material/Stack";
import TextField from "@mui/material/TextField";
import { useState } from "react";
import { fromLocalInput, toLocalInput } from "../format";
import { CREATE_RACE, SET_RACE_START, UPDATE_RACE, type MutationResult, type RaceInfo } from "../queries";
import { defaultRaceName } from "../races";

type Props = {
  eventId: string;
  race: RaceInfo | null; // null = new race
  startAtMs: number | null;
  canSetStart: boolean;
  onClose: (saved: boolean) => void;
};

const blank = (s: string) => (s.trim() ? s.trim() : null);
const num = (s: string) => (s.trim() ? Number(s) : null);

export function RaceDialog({ eventId, race, startAtMs, canSetStart, onClose }: Props) {
  const [createRace] = useMutation<{ createRace: MutationResult }>(CREATE_RACE);
  const [updateRace] = useMutation<{ updateRace: MutationResult }>(UPDATE_RACE);
  const [setRaceStart] = useMutation<{ setRaceStart: MutationResult }>(SET_RACE_START);
  const [category, setCategory] = useState(race?.category ?? "");
  const [ageGroup, setAgeGroup] = useState(race?.ageGroup ?? "");
  const [ageMin, setAgeMin] = useState(race?.ageMin?.toString() ?? "");
  const [ageMax, setAgeMax] = useState(race?.ageMax?.toString() ?? "");
  const [gender, setGender] = useState(race?.gender ?? "men");
  const [name, setName] = useState(race?.nameOverride ?? "");
  const [scheduled, setScheduled] = useState(toLocalInput(race?.scheduledAtMs));
  const [minutes, setMinutes] = useState(race?.expectedDurationMs ? String(race.expectedDurationMs / 60_000) : "");
  const [laps, setLaps] = useState(race?.expectedLaps?.toString() ?? "");
  const [fwl, setFwl] = useState(race?.finishWithLeaderOverride == null ? "inherit" : race.finishWithLeaderOverride ? "on" : "off");
  const [start, setStart] = useState(toLocalInput(startAtMs));
  const [errors, setErrors] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);

  async function save() {
    setBusy(true);
    setErrors([]);
    const fields = {
      category: blank(category),
      ageGroup: blank(ageGroup),
      ageMin: num(ageMin),
      ageMax: num(ageMax),
      gender,
      nameOverride: blank(name),
      scheduledAtMs: fromLocalInput(scheduled),
      expectedDurationMs: minutes.trim() ? Math.round(Number(minutes) * 60_000) : null,
      expectedLaps: num(laps),
      finishWithLeader: fwl === "inherit" ? null : fwl === "on",
    };
    try {
      if (fields.scheduledAtMs == null) throw new Error("Scheduled start is required");
      const result = race
        ? (await updateRace({ variables: { id: race.id, ...fields } })).data?.updateRace
        : (await createRace({ variables: { eventId, ...fields } })).data?.createRace;
      const problems = result?.errors ?? [];
      const startMs = fromLocalInput(start);
      if (!problems.length && race && canSetStart && startMs != null && startMs !== startAtMs) {
        problems.push(...((await setRaceStart({ variables: { raceId: race.id, atMs: startMs } })).data?.setRaceStart.errors ?? []));
      }
      if (problems.length) setErrors(problems);
      else onClose(true);
    } catch (e) {
      setErrors([(e as Error).message]);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open onClose={() => onClose(false)} maxWidth="sm" fullWidth>
      <DialogTitle>{race ? `Edit ${race.name}` : "Add race"}</DialogTitle>
      <DialogContent>
        <Stack spacing={2} sx={{ pt: 1 }}>
          <Stack direction="row" spacing={2}>
            <TextField label="Category" value={category} onChange={(e) => setCategory(e.target.value)} fullWidth />
            <TextField label="Age group" value={ageGroup} onChange={(e) => setAgeGroup(e.target.value)} fullWidth />
          </Stack>
          <Stack direction="row" spacing={2}>
            <TextField label="Minimum age" type="number" value={ageMin} onChange={(e) => setAgeMin(e.target.value)} fullWidth />
            <TextField label="Maximum age" type="number" value={ageMax} onChange={(e) => setAgeMax(e.target.value)} fullWidth />
            <TextField select label="Gender" value={gender} onChange={(e) => setGender(e.target.value)} fullWidth
              slotProps={{ select: { native: true }, inputLabel: { shrink: true } }}>
              <option value="men">Men</option>
              <option value="women">Women</option>
              <option value="open">Open</option>
            </TextField>
          </Stack>
          <TextField label="Name" value={name} onChange={(e) => setName(e.target.value)} placeholder={defaultRaceName(blank(category), blank(ageGroup), gender)}
            helperText="Leave blank to use the default name" slotProps={{ inputLabel: { shrink: true } }} />
          <TextField label="Scheduled start" type="datetime-local" value={scheduled} onChange={(e) => setScheduled(e.target.value)}
            slotProps={{ inputLabel: { shrink: true } }} />
          <Stack direction="row" spacing={2}>
            <TextField label="Expected duration (minutes)" type="number" value={minutes} onChange={(e) => setMinutes(e.target.value)} fullWidth />
            <TextField label="Expected laps" type="number" value={laps} onChange={(e) => setLaps(e.target.value)} fullWidth />
            <TextField select label="Finish with leader" value={fwl} onChange={(e) => setFwl(e.target.value)} fullWidth
              slotProps={{ select: { native: true }, inputLabel: { shrink: true } }}>
              <option value="inherit">Inherit from event</option>
              <option value="on">On</option>
              <option value="off">Off</option>
            </TextField>
          </Stack>
          {race && canSetStart && (
            <TextField label="Start time" type="datetime-local" value={start} onChange={(e) => setStart(e.target.value)}
              helperText="Set by the Start screen; enter it here only to correct it" slotProps={{ inputLabel: { shrink: true } }} />
          )}
          {errors.map((e) => (
            <Alert key={e} severity="error">{e}</Alert>
          ))}
        </Stack>
      </DialogContent>
      <DialogActions>
        <Button onClick={() => onClose(false)}>Cancel</Button>
        <Button variant="contained" onClick={save} disabled={busy}>
          Save
        </Button>
      </DialogActions>
    </Dialog>
  );
}
