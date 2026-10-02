import Checkbox from "@mui/material/Checkbox";
import FormControlLabel from "@mui/material/FormControlLabel";
import Stack from "@mui/material/Stack";
import TextField from "@mui/material/TextField";
import type { Discipline, EventInput } from "../queries";

// Event details form, shared by "New event" and the Setup screen. Picking a
// discipline pre-fills "finish with leader" from its default.
export function EventFields({ value, onChange, disciplines }: { value: EventInput; onChange: (v: EventInput) => void; disciplines: Discipline[] }) {
  const discipline = disciplines.find((d) => d.id === value.discipline);
  const defaultFor = (d: Discipline | undefined, sub: string | null) =>
    sub ? (d?.subDisciplines.find((s) => s.id === sub)?.finishWithLeader ?? false) : (d?.finishWithLeader ?? false);
  const set = (patch: Partial<EventInput>) => onChange({ ...value, ...patch });

  return (
    <Stack spacing={2} sx={{ pt: 1 }}>
      <TextField label="Name" value={value.name} onChange={(e) => set({ name: e.target.value })} autoFocus />
      <TextField label="Date" type="date" value={value.date} onChange={(e) => set({ date: e.target.value })} slotProps={{ inputLabel: { shrink: true } }} />
      <TextField label="Location" value={value.location ?? ""} onChange={(e) => set({ location: e.target.value || null })} />
      <TextField
        select
        label="Discipline"
        value={value.discipline}
        onChange={(e) => {
          const d = disciplines.find((x) => x.id === e.target.value);
          set({ discipline: e.target.value, subDiscipline: null, finishWithLeader: defaultFor(d, null) });
        }}
        slotProps={{ select: { native: true }, inputLabel: { shrink: true } }}
      >
        {disciplines.map((d) => (
          <option key={d.id} value={d.id}>
            {d.label}
          </option>
        ))}
      </TextField>
      {discipline && discipline.subDisciplines.length > 0 && (
        <TextField
          select
          label="Sub-discipline"
          value={value.subDiscipline ?? ""}
          onChange={(e) => set({ subDiscipline: e.target.value || null, finishWithLeader: defaultFor(discipline, e.target.value || null) })}
          slotProps={{ select: { native: true }, inputLabel: { shrink: true } }}
        >
          <option value="">—</option>
          {discipline.subDisciplines.map((s) => (
            <option key={s.id} value={s.id}>
              {s.label}
            </option>
          ))}
        </TextField>
      )}
      <FormControlLabel
        control={<Checkbox checked={value.finishWithLeader} onChange={(e) => set({ finishWithLeader: e.target.checked })} />}
        label="Finish with leader"
      />
    </Stack>
  );
}
