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
import { REGISTER_RACER, UPDATE_REGISTRATION, type RegistrationResult } from "../queries";
import type { RegistrationRow } from "../registration";

type Props = {
  races: { id: string; name: string }[];
  registration: RegistrationRow | null; // null = walk-up
  onClose: (saved: boolean) => void;
};

const blank = (s: string) => (s.trim() ? s.trim() : null);

// Add a walk-up (registered and checked in at once; bib optional) or edit a
// registration and its racer, including moving them to another race.
export function RacerDialog({ races, registration, onClose }: Props) {
  const [registerRacer] = useMutation<{ registerRacer: RegistrationResult }>(REGISTER_RACER);
  const [updateRegistration] = useMutation<{ updateRegistration: RegistrationResult }>(UPDATE_REGISTRATION);
  const racer = registration?.racer;
  const [form, setForm] = useState({
    firstName: racer?.firstName ?? "",
    lastName: racer?.lastName ?? "",
    gender: racer?.gender ?? "M",
    raceId: registration?.race.id ?? races[0]?.id ?? "",
    bib: registration?.bib ?? "",
    age: registration?.age?.toString() ?? "",
    birthDate: racer?.birthDate ?? "",
    team: racer?.team ?? "",
    licenseNumber: racer?.licenseNumber ?? "",
    city: racer?.city ?? "",
    state: racer?.state ?? "",
  });
  const [errors, setErrors] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const field = (key: keyof typeof form, label: string, props: object = {}) => (
    <TextField label={label} value={form[key]} onChange={(e) => setForm({ ...form, [key]: e.target.value })} fullWidth {...props} />
  );

  async function save() {
    setBusy(true);
    setErrors([]);
    const racerInput = {
      firstName: form.firstName.trim(),
      lastName: form.lastName.trim(),
      gender: form.gender,
      birthDate: blank(form.birthDate),
      team: blank(form.team),
      licenseNumber: blank(form.licenseNumber),
      city: blank(form.city),
      state: blank(form.state),
    };
    const variables = { raceId: form.raceId, bib: blank(form.bib), age: form.age.trim() ? Number(form.age) : null, racer: racerInput };
    try {
      const result = registration
        ? (await updateRegistration({ variables: { id: registration.id, ...variables } })).data?.updateRegistration
        : (await registerRacer({ variables })).data?.registerRacer;
      if (result?.errors.length) setErrors(result.errors);
      else onClose(true);
    } catch (e) {
      setErrors([(e as Error).message]);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open onClose={() => onClose(false)} maxWidth="sm" fullWidth>
      <DialogTitle>{registration ? `Edit ${racer?.firstName} ${racer?.lastName}` : "Add racer"}</DialogTitle>
      <DialogContent>
        <Stack spacing={2} sx={{ pt: 1 }}>
          <Stack direction="row" spacing={2}>
            {field("firstName", "First name", { autoFocus: true })}
            {field("lastName", "Last name")}
          </Stack>
          <Stack direction="row" spacing={2}>
            {field("gender", "Gender", { select: true, slotProps: { select: { native: true }, inputLabel: { shrink: true } }, children: [
              <option key="M" value="M">M</option>, <option key="F" value="F">F</option>, <option key="X" value="X">X</option>,
            ] })}
            {field("raceId", "Race", { select: true, slotProps: { select: { native: true }, inputLabel: { shrink: true } },
              children: races.map((r) => <option key={r.id} value={r.id}>{r.name}</option>) })}
          </Stack>
          <Stack direction="row" spacing={2}>
            {field("bib", "Bib", { helperText: "Optional; give one out later", slotProps: { htmlInput: { style: { textAlign: "center" } } } })}
            {field("age", "Age", { type: "number" })}
            {field("birthDate", "Birth date", { type: "date", slotProps: { inputLabel: { shrink: true } } })}
          </Stack>
          <Stack direction="row" spacing={2}>
            {field("team", "Team")}
            {field("licenseNumber", "License")}
          </Stack>
          <Stack direction="row" spacing={2}>
            {field("city", "City")}
            {field("state", "State")}
          </Stack>
          {errors.map((e) => (
            <Alert key={e} severity="error">{e}</Alert>
          ))}
        </Stack>
      </DialogContent>
      <DialogActions>
        <Button onClick={() => onClose(false)}>Cancel</Button>
        <Button variant="contained" onClick={save} disabled={busy}>Save</Button>
      </DialogActions>
    </Dialog>
  );
}
