import { useMutation, useQuery } from "@apollo/client/react";
import DeleteIcon from "@mui/icons-material/Delete";
import EditIcon from "@mui/icons-material/Edit";
import WarningAmberIcon from "@mui/icons-material/WarningAmber";
import Alert from "@mui/material/Alert";
import Autocomplete from "@mui/material/Autocomplete";
import Box from "@mui/material/Box";
import ButtonBase from "@mui/material/ButtonBase";
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
import TableSortLabel from "@mui/material/TableSortLabel";
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
  DEFAULT_SORT,
  NO_FILTER,
  countRegistrations,
  statLabels,
  filterFromSearch,
  filterRegistrations,
  filterToSearch,
  sortFromSearch,
  sortRegistrations,
  sortToSearch,
  type RegistrationFilter,
  type RegistrationRow,
  type RegistrationSort,
  type SortKey,
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
  const [sort, setSort] = useState<RegistrationSort>(() => sortFromSearch(window.location.search));
  // Filters and sort live in the address; replace (not push) so typing in
  // Search doesn't fill the Back button's history.
  useEffect(() => {
    const params = new URLSearchParams(filterToSearch(filter));
    if (sort.key !== DEFAULT_SORT.key || sort.dir !== DEFAULT_SORT.dir) sortToSearch(sort).forEach(([k, v]) => params.set(k, v));
    const query = params.toString();
    window.history.replaceState(window.history.state, "", `${window.location.pathname}${query ? `?${query}` : ""}`);
  }, [filter, sort]);
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
  const rows = sortRegistrations(filterRegistrations(event.registrations, { ...filter, terms: [...filter.terms, typing] }), sort);
  // A header click sorts by that column; clicking the sorted column reverses it.
  const header = (key: SortKey, label: string, align?: "center") => (
    <TableCell align={align} sortDirection={sort.key === key ? sort.dir : false}>
      <TableSortLabel active={sort.key === key} direction={sort.key === key ? sort.dir : "asc"}
        onClick={() => setSort(sort.key === key ? { key, dir: sort.dir === "asc" ? "desc" : "asc" } : { key, dir: "asc" })}>
        {label}
      </TableSortLabel>
    </TableCell>
  );
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
      <Stack direction="row" spacing={2} sx={{ alignItems: "center", mb: 2 }}>
        <StatTiles counts={countRegistrations(rows)} total={event.registrations.length} filter={filter} onFilter={setFilterPart} />
        <Box sx={{ flex: 1 }} />
        {canAct && <Button variant="contained" onClick={() => setEditing("new")}>Add racer</Button>}
        {admin && <Button variant="outlined" onClick={() => setImporting(true)}>Import</Button>}
        {canAct && <Button variant="outlined" onClick={onAssignBibs}>Assign bibs</Button>}
      </Stack>
      <Stack direction="row" spacing={2} sx={{ alignItems: "flex-start", flexWrap: "wrap", rowGap: 1, mb: 2 }}>
        <FilterWithChips chips={filter.terms.map((t) => ({ key: t, label: t }))}
          onDelete={(term) => setFilterPart({ terms: filter.terms.filter((t) => t !== term) })}>
        <Autocomplete
          multiple
          freeSolo
          size="small"
          options={[] as string[]}
          value={filter.terms}
          onChange={(_, terms) => setFilterPart({ terms: terms.map((t) => t.trim()).filter(Boolean) })}
          inputValue={typing}
          onInputChange={(_, text) => setTyping(text)}
          renderValue={() => null}
          sx={{ width: 260 }}
          renderInput={(params) => (
            <TextField {...params} label="Search" placeholder="Name, bib, team, license — Enter adds" />
          )}
        />
        </FilterWithChips>
        <FilterWithChips chips={filter.raceIds.flatMap((id) => (racesById.has(id) ? [{ key: id, label: racesById.get(id)!.name }] : []))}
          onDelete={(id) => setFilterPart({ raceIds: filter.raceIds.filter((r) => r !== id) })}>
        <Autocomplete
          multiple
          size="small"
          options={event.races}
          getOptionLabel={(r) => r.name}
          isOptionEqualToValue={(a, b) => a.id === b.id}
          value={filter.raceIds.flatMap((id) => racesById.get(id) ?? [])}
          onChange={(_, races) => setFilterPart({ raceIds: races.map((r) => r.id) })}
          renderValue={() => null}
          disableCloseOnSelect
          sx={{ width: 260 }}
          renderInput={(params) => <TextField {...params} label="Race" placeholder={filter.raceIds.length ? "Add a race" : "All races"} />}
        />
        </FilterWithChips>
        {/* Same height as the inputs, so these line up with them even when chips sit under the inputs. */}
        <Stack direction="row" spacing={2} sx={{ alignItems: "center", minHeight: 40 }}>
        <FormControlLabel control={<Checkbox checked={filter.needsBib} onChange={(e) => setFilterPart({ needsBib: e.target.checked })} />} label="Needs bib" />
        <FormControlLabel control={<Checkbox checked={filter.notCheckedIn} onChange={(e) => setFilterPart({ notCheckedIn: e.target.checked })} />} label="Not checked in" />
        {filtering && <Button size="small" onClick={() => { setFilter(NO_FILTER); setTyping(""); }}>Clear filters</Button>}
        </Stack>

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
              {header("bib", "Bib", "center")}
              {header("name", "Name")}
              {header("gender", "Gender")}
              {header("age", "Age")}
              {header("team", "Team")}
              {header("race", "Race")}
              {header("checkedIn", "Checked in")}
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

// A filter control with its chosen values as chips underneath, so the control
// keeps its size however many values are picked.
function FilterWithChips({ chips, onDelete, children }: {
  chips: { key: string; label: string }[];
  onDelete: (key: string) => void;
  children: React.ReactNode;
}) {
  return (
    <Stack spacing={0.5}>
      {children}
      {chips.length > 0 && (
        <Stack direction="row" sx={{ flexWrap: "wrap", gap: 0.5, maxWidth: 260 }}>
          {chips.map((c) => <Chip key={c.key} size="small" label={c.label} onDelete={() => onDelete(c.key)} />)}
        </Stack>
      )}
    </Stack>
  );
}

// Racers shown, check-in progress, and racers still needing a bib. The last two
// are shortcuts to their filters; "need a bib" turns amber while it's above 0.
function StatTiles({ counts, total, filter, onFilter }: {
  counts: { registered: number; checkedIn: number; needsBib: number };
  total: number;
  filter: RegistrationFilter;
  onFilter: (part: Partial<RegistrationFilter>) => void;
}) {
  const labels = statLabels(counts, total);
  const filtered = counts.registered !== total;
  return (
    <Stack direction="row" spacing={1.5} sx={{ alignItems: "stretch" }}>
      <Tile testId="stat-racers" label={labels.racers} value={counts.registered} detail={filtered ? `of ${total}` : undefined} caption="racers" />
      <Tile testId="stat-checked-in" label={labels.checkedIn} value={counts.checkedIn} detail={`/ ${counts.registered}`} caption="checked in"
        progress={labels.checkedInPercent} active={filter.notCheckedIn} onClick={() => onFilter({ notCheckedIn: !filter.notCheckedIn })}
        hint="Show racers not checked in" />
      <Tile testId="stat-needs-bib" label={labels.needsBib} value={counts.needsBib} caption={counts.needsBib === 1 ? "needs a bib" : "need a bib"}
        warning={counts.needsBib > 0} active={filter.needsBib} onClick={() => onFilter({ needsBib: !filter.needsBib })}
        hint="Show racers without a bib" />
    </Stack>
  );
}

function Tile({ testId, label, value, detail, caption, progress, warning, active, onClick, hint }: {
  testId: string;
  label: string;
  value: number;
  detail?: string;
  caption: string;
  progress?: number;
  warning?: boolean;
  active?: boolean;
  onClick?: () => void;
  hint?: string;
}) {
  const accent = warning ? "warning.main" : active ? "primary.main" : "divider";
  const body = (
    <Box sx={{ px: 1.5, py: 0.75, minWidth: 110, height: "100%", boxSizing: "border-box", textAlign: "left", border: 1, borderColor: accent, borderRadius: 1,
      bgcolor: active ? "action.selected" : "background.paper" }}>
      <Typography component="div" sx={{ lineHeight: 1.1 }}>
        <Box component="span" sx={{ fontSize: 26, fontWeight: 600, color: warning ? "warning.main" : "text.primary" }}>{value}</Box>
        {detail && <Box component="span" sx={{ ml: 0.5, fontSize: 14, color: "text.secondary" }}>{detail}</Box>}
      </Typography>
      <Typography variant="caption" color="text.secondary">{caption}</Typography>
      {progress != null && <LinearProgress variant="determinate" value={progress} sx={{ mt: 0.5, height: 4, borderRadius: 2 }} />}
    </Box>
  );
  if (!onClick) return <Box data-testid={testId} role="group" aria-label={label} sx={{ display: "flex" }}>{body}</Box>;
  return (
    <Tooltip title={hint ?? ""}>
      <ButtonBase data-testid={testId} aria-label={label} aria-pressed={active} onClick={onClick} sx={{ borderRadius: 1, alignItems: "stretch" }}>
        {body}
      </ButtonBase>
    </Tooltip>
  );
}
