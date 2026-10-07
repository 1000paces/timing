import { useQuery } from "@apollo/client/react";
import Alert from "@mui/material/Alert";
import Autocomplete from "@mui/material/Autocomplete";
import Box from "@mui/material/Box";
import Button from "@mui/material/Button";
import Chip from "@mui/material/Chip";
import LinearProgress from "@mui/material/LinearProgress";
import List from "@mui/material/List";
import Paper from "@mui/material/Paper";
import Stack from "@mui/material/Stack";
import TextField from "@mui/material/TextField";
import Typography from "@mui/material/Typography";
import { useCallback, useEffect, useState } from "react";
import {
  NO_PROBLEM_FILTER,
  PROBLEM_TYPE,
  PROBLEM_TYPES,
  filterProblems,
  problemFilterFromSearch,
  problemFilterToSearch,
  problemType,
  typeCounts,
  unassignedLabels,
  type Problem,
  type ProblemFilter,
} from "../problems";
import { EVENT, STANDINGS, type EventData, type StandingsData } from "../queries";
import { canAct as roleCanAct, isSignedOutError } from "../roles";
import type { Official } from "../session";
import { useEventChanges } from "../useEventChanges";
import { EventNav } from "./EventNav";
import { FilterWithChips } from "./FilterWithChips";
import { IssueCount, SuggestionItem } from "./ReviewQueue";

type Props = { eventId: string; official: Official; onSignedOut: () => void };
const NO_RACE = { id: "none", name: "No race" };

// The review queue as a full page, filterable by type, race and bib/racer.
export function ProblemsScreen({ eventId, official, onSignedOut }: Props) {
  const event = useQuery<EventData>(EVENT, { variables: { id: eventId } });
  const standings = useQuery<StandingsData>(STANDINGS, { variables: { eventId }, pollInterval: 5000, fetchPolicy: "network-only" });
  const [filter, setFilter] = useState<ProblemFilter>(() => problemFilterFromSearch(window.location.search));
  const [typing, setTyping] = useState("");
  const setPart = (part: Partial<ProblemFilter>) => setFilter((current) => ({ ...current, ...part }));
  useEffect(() => {
    window.history.replaceState(window.history.state, "", `${window.location.pathname}${problemFilterToSearch(filter)}`);
  }, [filter]);

  const { refetch } = standings;
  const refresh = useCallback(() => {
    refetch().catch(() => {});
  }, [refetch]);
  useEventChanges(eventId, refresh);
  const firstError = event.error ?? standings.error;
  useEffect(() => {
    if (isSignedOutError(firstError)) onSignedOut();
  }, [firstError, onSignedOut]);

  if (!event.data) {
    return <Box sx={{ p: 3 }}>{event.error ? <Alert severity="error">{event.error.message}</Alert> : <LinearProgress />}</Box>;
  }
  const report = standings.data?.standings;
  const races = [...event.data.event.races.map((r) => ({ id: r.id, name: r.name })), NO_RACE];
  const raceName = new Map(races.map((r) => [r.id, r.name]));
  const names = new Map((report?.races ?? []).flatMap((r) => r.rows.map((row) => [row.bib, row.name] as const)));
  const labels = unassignedLabels(report);
  const problems: Problem[] = (report?.suggestions ?? []).map((s) => ({
    suggestion: s,
    type: problemType(s),
    raceId: s.raceId,
    name: s.bib ? (names.get(s.bib) ?? null) : null,
  }));
  const shown = filterProblems(problems, { ...filter, terms: [...filter.terms, typing] });
  const counts = typeCounts(problems);
  const canAct = roleCanAct(official.role);
  const filtering = filter.types.length > 0 || filter.raceIds.length > 0 || filter.terms.length > 0 || typing.trim() !== "";
  const typeOptions = PROBLEM_TYPES.map((t) => t.id);

  return (
    <Box sx={{ p: 2, maxWidth: 1000 }}>
      <EventNav eventId={eventId} eventName={event.data.event.name} current="problems" admin={official.role === "admin"} />
      <Stack direction="row" spacing={1} sx={{ alignItems: "center", mb: 2 }}>
        <Typography variant="h5" component="h2">Problems</Typography>
        {report && <IssueCount shown={shown.length} total={problems.length} />}
      </Stack>
      <Stack direction="row" spacing={2} sx={{ alignItems: "flex-start", flexWrap: "wrap", rowGap: 1, mb: 2 }}>
        <FilterWithChips chips={filter.types.map((t) => ({ key: t, label: PROBLEM_TYPE[t as keyof typeof PROBLEM_TYPE]?.label ?? t }))}
          onDelete={(t) => setPart({ types: filter.types.filter((x) => x !== t) })}>
          <Autocomplete multiple size="small" disableCloseOnSelect options={typeOptions} value={filter.types as typeof typeOptions}
            getOptionLabel={(id) => `${PROBLEM_TYPE[id].label} (${counts[id] ?? 0})`}
            onChange={(_, types) => setPart({ types })} renderValue={() => null} sx={{ width: 260 }}
            renderInput={(params) => <TextField {...params} label="Type" placeholder={filter.types.length ? "Add a type" : "All types"} />} />
        </FilterWithChips>
        <FilterWithChips chips={filter.raceIds.map((id) => ({ key: id, label: raceName.get(id) ?? id }))}
          onDelete={(id) => setPart({ raceIds: filter.raceIds.filter((x) => x !== id) })}>
          <Autocomplete multiple size="small" disableCloseOnSelect options={races} getOptionLabel={(r) => r.name}
            isOptionEqualToValue={(a, b) => a.id === b.id} value={races.filter((r) => filter.raceIds.includes(r.id))}
            onChange={(_, picked) => setPart({ raceIds: picked.map((r) => r.id) })} renderValue={() => null} sx={{ width: 260 }}
            renderInput={(params) => <TextField {...params} label="Race" placeholder={filter.raceIds.length ? "Add a race" : "All races"} />} />
        </FilterWithChips>
        <FilterWithChips chips={filter.terms.map((t) => ({ key: t, label: t }))} onDelete={(t) => setPart({ terms: filter.terms.filter((x) => x !== t) })}>
          <Autocomplete multiple freeSolo size="small" options={[] as string[]} value={filter.terms}
            onChange={(_, terms) => setPart({ terms: terms.map((t) => t.trim()).filter(Boolean) })}
            inputValue={typing} onInputChange={(_, text) => setTyping(text)} renderValue={() => null} sx={{ width: 220 }}
            renderInput={(params) => <TextField {...params} label="Search" placeholder="Bib or racer — Enter adds" />} />
        </FilterWithChips>
        {filtering && (
          <Stack sx={{ justifyContent: "center", minHeight: 40 }}>
            <Button size="small" onClick={() => { setFilter(NO_PROBLEM_FILTER); setTyping(""); }}>Clear filters</Button>
          </Stack>
        )}
      </Stack>
      {standings.error && <Alert severity="error" sx={{ mb: 2 }}>{standings.error.message}</Alert>}
      {report?.stale && <Alert severity="warning" sx={{ mb: 2 }}>Standings are out of date: {report.error}</Alert>}
      {!report && <LinearProgress />}
      <Paper sx={{ px: 2 }}>
        {report && shown.length === 0 && (
          <Typography color="text.secondary" sx={{ py: 2 }}>{problems.length ? "No problems match." : "No problems. Nothing to review."}</Typography>
        )}
        <List disablePadding>
          {shown.map((p) => {
            const type = PROBLEM_TYPE[p.type];
            const meta = (
              <Stack direction="row" spacing={1} sx={{ alignItems: "center", mb: 0.5 }}>
                <Chip data-testid="problem-type" size="small" color={type.color} label={type.label} />
                <Typography variant="body2" color="text.secondary">
                  {[raceName.get(p.raceId ?? "none"), p.suggestion.bib && `Bib ${p.suggestion.bib}${p.name ? ` · ${p.name}` : ""}`].filter(Boolean).join(" · ")}
                </Typography>
              </Stack>
            );
            return (
              <SuggestionItem key={p.suggestion.key} eventId={eventId} suggestion={p.suggestion} label={labels.get(p.suggestion.key)}
                meta={meta} canAct={canAct} onChanged={refresh} />
            );
          })}
        </List>
      </Paper>
    </Box>
  );
}
