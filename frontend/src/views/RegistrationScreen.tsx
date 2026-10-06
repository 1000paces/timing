import { useMutation, useQuery } from "@apollo/client/react";
import DeleteIcon from "@mui/icons-material/Delete";
import EditIcon from "@mui/icons-material/Edit";
import WarningAmberIcon from "@mui/icons-material/WarningAmber";
import Alert from "@mui/material/Alert";
import Autocomplete from "@mui/material/Autocomplete";
import Box from "@mui/material/Box";
import Button from "@mui/material/Button";
import Checkbox from "@mui/material/Checkbox";
import Chip from "@mui/material/Chip";
import Dialog from "@mui/material/Dialog";
import DialogActions from "@mui/material/DialogActions";
import DialogTitle from "@mui/material/DialogTitle";
import FormControlLabel from "@mui/material/FormControlLabel";
import IconButton from "@mui/material/IconButton";
import LinearProgress from "@mui/material/LinearProgress";
import Paper from "@mui/material/Paper";
import Stack from "@mui/material/Stack";
import Table from "@mui/material/Table";
import TableBody from "@mui/material/TableBody";
import TableCell from "@mui/material/TableCell";
import TableHead from "@mui/material/TableHead";
import TableRow from "@mui/material/TableRow";
import TextField from "@mui/material/TextField";
import Tooltip from "@mui/material/Tooltip";
import Typography from "@mui/material/Typography";
import { useCallback, useEffect, useState } from "react";
import {
  ASSIGN_BIBS,
  REGISTRATION_SCREEN,
  REMOVE_REGISTRATION,
  SET_CHECKED_IN,
  UPDATE_BIB,
  type AssignBibsResult,
  type RegistrationResult,
  type RegistrationScreenData,
} from "../queries";
import {
  NO_FILTER,
  countRegistrations,
  countsLabel,
  filterFromSearch,
  filterRegistrations,
  filterToSearch,
  type RegistrationFilter,
  type RegistrationRow,
} from "../registration";
import { canAct as roleCanAct, isSignedOutError } from "../roles";
import type { Official } from "../session";
import { useEventChanges } from "../useEventChanges";
import { EventNav } from "./EventNav";
import { ImportDialog } from "./ImportDialog";
import { RacerDialog } from "./RacerDialog";

type Props = { eventId: string; official: Official; onSignedOut: () => void };
type Notice = { severity: "success" | "info" | "error"; lines: string[] };

export function RegistrationScreen({ eventId, official, onSignedOut }: Props) {
  const screen = useQuery<RegistrationScreenData>(REGISTRATION_SCREEN, { variables: { id: eventId }, fetchPolicy: "cache-and-network" });
  const [assignBibs] = useMutation<AssignBibsResult>(ASSIGN_BIBS);
  const [removeRegistration] = useMutation<{ removeRegistration: { errors: string[] } }>(REMOVE_REGISTRATION);
  const [filter, setFilter] = useState<RegistrationFilter>(() => filterFromSearch(window.location.search));
  const setFilterPart = (part: Partial<RegistrationFilter>) => setFilter((current) => ({ ...current, ...part }));
  const [typing, setTyping] = useState(""); // search text not yet added as a chip; filters as you type
  // Replace (not push) so typing in Search doesn't fill the Back button's history.
  useEffect(() => {
    window.history.replaceState(window.history.state, "", `${window.location.pathname}${filterToSearch(filter)}`);
  }, [filter]);
  const [editing, setEditing] = useState<RegistrationRow | "new" | null>(null);
  const [importing, setImporting] = useState(false);
  const [removing, setRemoving] = useState<RegistrationRow | null>(null);
  const [notice, setNotice] = useState<Notice | null>(null);
  const canAct = roleCanAct(official.role);
  const admin = official.role === "admin";

  useEffect(() => {
    if (isSignedOutError(screen.error)) onSignedOut();
  }, [screen.error, onSignedOut]);
  const { refetch } = screen;
  const refresh = useCallback(() => refetch().catch(() => {}), [refetch]);
  useEventChanges(eventId, refresh);

  const event = screen.data?.event;
  if (!event) {
    return <Box sx={{ p: 3 }}>{screen.error ? <Alert severity="error">{screen.error.message}</Alert> : <LinearProgress />}</Box>;
  }
  const rows = filterRegistrations(event.registrations, { ...filter, terms: [...filter.terms, typing] });
  const filtering = filter.terms.length > 0 || filter.raceIds.length > 0 || filter.needsBib || filter.notCheckedIn || typing.trim() !== "";
  const racesById = new Map(event.races.map((r) => [r.id, r]));

  async function onAssignBibs() {
    try {
      const result = (await assignBibs({ variables: { eventId } })).data?.assignBibs;
      if (!result) return;
      const n = result.assigned.length;
      setNotice({
        severity: result.errors.length ? "error" : result.unfilled.length ? "info" : "success",
        lines: [...result.errors, n === 0 ? "No bibs to assign" : `Assigned ${n} bib${n === 1 ? "" : "s"}`, ...result.unfilled],
      });
    } catch (e) {
      setNotice({ severity: "error", lines: [(e as Error).message] });
    }
    void refresh();
  }

  async function onRemove(reg: RegistrationRow) {
    setRemoving(null);
    try {
      const errors = (await removeRegistration({ variables: { id: reg.id } })).data?.removeRegistration.errors ?? [];
      setNotice(errors.length ? { severity: "error", lines: errors } : null);
    } catch (e) {
      setNotice({ severity: "error", lines: [(e as Error).message] });
    }
    void refresh();
  }

  return (
    <Box sx={{ p: 2 }}>
      <EventNav eventId={eventId} eventName={event.name} current="registration" admin={admin} />
      <Stack direction="row" spacing={2} sx={{ alignItems: "center", flexWrap: "wrap", rowGap: 1, mb: 2 }}>
        <Autocomplete
          multiple
          freeSolo
          size="small"
          options={[] as string[]}
          value={filter.terms}
          onChange={(_, terms) => setFilterPart({ terms: terms.map((t) => t.trim()).filter(Boolean) })}
          inputValue={typing}
          onInputChange={(_, text) => setTyping(text)}
          sx={{ minWidth: 240 }}
          renderInput={(params) => (
            <TextField {...params} label="Search" placeholder={filter.terms.length ? "" : "Name, bib, team, license — Enter adds"} />
          )}
        />
        <Autocomplete
          multiple
          size="small"
          options={event.races}
          getOptionLabel={(r) => r.name}
          isOptionEqualToValue={(a, b) => a.id === b.id}
          value={filter.raceIds.flatMap((id) => racesById.get(id) ?? [])}
          onChange={(_, races) => setFilterPart({ raceIds: races.map((r) => r.id) })}
          sx={{ minWidth: 240 }}
          renderInput={(params) => <TextField {...params} label="Race" placeholder={filter.raceIds.length ? "" : "All races"} />}
        />
        <FormControlLabel control={<Checkbox checked={filter.needsBib} onChange={(e) => setFilterPart({ needsBib: e.target.checked })} />} label="Needs bib" />
        <FormControlLabel control={<Checkbox checked={filter.notCheckedIn} onChange={(e) => setFilterPart({ notCheckedIn: e.target.checked })} />} label="Not checked in" />
        {filtering && <Button size="small" onClick={() => { setFilter(NO_FILTER); setTyping(""); }}>Clear filters</Button>}
        <Typography data-testid="registration-counts" color="text.secondary" sx={{ flex: 1 }}>
          {countsLabel(countRegistrations(rows), event.registrations.length)}
        </Typography>
        {canAct && <Button variant="contained" onClick={() => setEditing("new")}>Add racer</Button>}
        {admin && <Button variant="outlined" onClick={() => setImporting(true)}>Import</Button>}
        {canAct && <Button variant="outlined" onClick={onAssignBibs}>Assign bibs</Button>}
      </Stack>
      {notice && (
        <Alert severity={notice.severity} sx={{ mb: 2 }} onClose={() => setNotice(null)}>
          {notice.lines.map((l) => <div key={l}>{l}</div>)}
        </Alert>
      )}
      <Paper>
        <Table size="small">
          <TableHead>
            <TableRow>
              <TableCell align="center">Bib</TableCell>
              <TableCell>Name</TableCell>
              <TableCell>Gender</TableCell>
              <TableCell>Age</TableCell>
              <TableCell>Team</TableCell>
              <TableCell>Race</TableCell>
              <TableCell>Checked in</TableCell>
              <TableCell />
            </TableRow>
          </TableHead>
          <TableBody>
            {rows.map((reg) => (
              <RegistrationLine key={reg.id} reg={reg} canAct={canAct} onEdit={() => setEditing(reg)} onRemove={() => setRemoving(reg)} onChanged={refresh} />
            ))}
            {rows.length === 0 && (
              <TableRow>
                <TableCell colSpan={8}>
                  <Typography color="text.secondary">{event.registrations.length ? "No racers match." : "No racers registered yet."}</Typography>
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </Paper>
      {editing && (
        <RacerDialog races={event.races} registration={editing === "new" ? null : editing}
          onClose={(saved) => { setEditing(null); if (saved) void refresh(); }} />
      )}
      {importing && (
        <ImportDialog eventId={eventId} races={event.races} refetchRaces={refresh}
          onClose={(changed) => { setImporting(false); if (changed) void refresh(); }} />
      )}
      <Dialog open={removing != null} onClose={() => setRemoving(null)}>
        <DialogTitle>Remove {removing?.racer.firstName} {removing?.racer.lastName} from {removing?.race.name}?</DialogTitle>
        <DialogActions>
          <Button onClick={() => setRemoving(null)}>Cancel</Button>
          <Button color="error" variant="contained" onClick={() => removing && onRemove(removing)}>Remove</Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}

function RegistrationLine({ reg, canAct, onEdit, onRemove, onChanged }: {
  reg: RegistrationRow;
  canAct: boolean;
  onEdit: () => void;
  onRemove: () => void;
  onChanged: () => void;
}) {
  const [setCheckedIn] = useMutation(SET_CHECKED_IN);
  const name = `${reg.racer.firstName} ${reg.racer.lastName}`;
  // Ticks at once; the refetch afterwards confirms it (or puts it back if the save failed).
  const [checked, setChecked] = useState(reg.checkedInAtMs != null);
  useEffect(() => setChecked(reg.checkedInAtMs != null), [reg.checkedInAtMs]);
  function toggle(next: boolean) {
    setChecked(next);
    setCheckedIn({ variables: { id: reg.id, checkedIn: next } })
      .catch(() => setChecked(!next))
      .finally(onChanged);
  }
  return (
    <TableRow data-testid="registration" hover>
      <TableCell align="center" sx={{ whiteSpace: "nowrap" }}>
        <Stack direction="row" spacing={1} sx={{ alignItems: "center", justifyContent: "center" }}>
          {canAct ? <BibField reg={reg} name={name} onChanged={onChanged} /> : reg.bib}
          {!reg.bib && <Chip size="small" color="warning" label="needs bib" />}
        </Stack>
      </TableCell>
      <TableCell>
        {name}
        {reg.eligibilityWarnings.length > 0 && (
          <Tooltip title={reg.eligibilityWarnings.join("; ")}>
            <WarningAmberIcon fontSize="small" color="warning" sx={{ ml: 1, verticalAlign: "middle" }} aria-label={`Warnings for ${name}`} />
          </Tooltip>
        )}
      </TableCell>
      <TableCell>{reg.racer.gender}</TableCell>
      <TableCell>{reg.age ?? ""}</TableCell>
      <TableCell>{reg.racer.team ?? ""}</TableCell>
      <TableCell>{reg.race.name}</TableCell>
      <TableCell>
        <Checkbox checked={checked} disabled={!canAct} slotProps={{ input: { "aria-label": `Checked in ${name}` } }}
          onChange={(e) => toggle(e.target.checked)} />
      </TableCell>
      <TableCell align="right" sx={{ whiteSpace: "nowrap" }}>
        {canAct && (
          <>
            <IconButton size="small" aria-label={`Edit ${name}`} onClick={onEdit}>
              <EditIcon fontSize="small" />
            </IconButton>
            <IconButton size="small" color="error" aria-label={`Remove ${name}`} onClick={onRemove}>
              <DeleteIcon fontSize="small" />
            </IconButton>
          </>
        )}
      </TableCell>
    </TableRow>
  );
}

// Type a bib and press Enter; a taken bib shows the hub's error under the field.
// Leaving the field (or Escape) without Enter puts the saved bib back.
function BibField({ reg, name, onChanged }: { reg: RegistrationRow; name: string; onChanged: () => void }) {
  const [updateBib] = useMutation<{ updateRegistration: RegistrationResult }>(UPDATE_BIB);
  const [value, setValue] = useState(reg.bib ?? "");
  const [error, setError] = useState<string | null>(null);
  useEffect(() => setValue(reg.bib ?? ""), [reg.bib]);

  async function save() {
    const bib = value.trim() || null;
    if (bib === reg.bib) return;
    try {
      const errors = (await updateBib({ variables: { id: reg.id, bib } })).data?.updateRegistration.errors ?? [];
      setError(errors.length ? errors.join("; ") : null);
    } catch (e) {
      setError((e as Error).message);
    }
    onChanged();
  }

  return (
    <TextField size="small" value={value} onChange={(e) => setValue(e.target.value)} error={error != null} helperText={error}
      onKeyDown={(e) => {
        if (e.key === "Enter") void save();
        if (e.key === "Escape") setValue(reg.bib ?? "");
      }}
      onBlur={() => setValue(reg.bib ?? "")}
      slotProps={{ htmlInput: { "aria-label": `Bib for ${name}`, inputMode: "numeric", style: { textAlign: "center" } } }} sx={{ width: 90 }} />
  );
}
