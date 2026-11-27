import { useQuery } from "@apollo/client/react";
import Alert from "@mui/material/Alert";
import Autocomplete from "@mui/material/Autocomplete";
import Button from "@mui/material/Button";
import Stack from "@mui/material/Stack";
import TextField from "@mui/material/TextField";
import ToggleButton from "@mui/material/ToggleButton";
import ToggleButtonGroup from "@mui/material/ToggleButtonGroup";
import Box from "@mui/material/Box";
import LinearProgress from "@mui/material/LinearProgress";
import Typography from "@mui/material/Typography";
import { useCallback, useEffect, useState } from "react";
import { EVENT, STANDINGS, type EventData, type StandingsData } from "../queries";
import { unassignedLabels } from "../problems";
import { canAct as roleCanAct, isSignedOutError } from "../roles";
import type { Official } from "../session";
import { useEventChanges } from "../useEventChanges";
import { raceIdsFromSearch, raceIdsToSearch } from "../races";
import { initialSearch, rememberSearch } from "../rememberedSearch";
import { EventNav } from "./EventNav";
import { FilterWithChips } from "./FilterWithChips";
import { RaceControls } from "./RaceControls";
import { ReviewQueue } from "./ReviewQueue";
import { RacerPanel } from "./RacerPanel";
import { Standings } from "./Standings";
import { WaveStandings } from "./WaveStandings";
import { FlagOut } from "./FlagOut";
import { groupWaves } from "../waves";

type Props = { eventId: string; official: Official; onSignedOut: () => void };

export function RaceScreen({ eventId, official, onSignedOut }: Props) {
  const event = useQuery<EventData>(EVENT, { variables: { id: eventId } });
  const standings = useQuery<StandingsData>(STANDINGS, { variables: { eventId }, pollInterval: 5000, fetchPolicy: "network-only" });
  const filterKey = `results:${eventId}`;
  const [raceFilter, setRaceFilter] = useState<string[]>(() => raceIdsFromSearch(initialSearch(filterKey, window.location.search)));
  // Category: a table per race. Wave: a table per scheduled start, in order on the road.
  const [view, setView] = useState<"category" | "wave">(() =>
    new URLSearchParams(initialSearch(filterKey, window.location.search)).get("view") === "wave" ? "wave" : "category");
  // The open racer panel is in the address too (?racer=101), but isn't remembered across tabs.
  const [racer, setRacer] = useState<string | null>(() => new URLSearchParams(window.location.search).get("racer"));
  useEffect(() => {
    const remembered = new URLSearchParams(raceIdsToSearch(raceFilter));
    if (view === "wave") remembered.set("view", "wave");
    rememberSearch(filterKey, remembered.size ? `?${remembered}` : "");
    const params = new URLSearchParams(remembered);
    if (racer) params.set("racer", racer);
    const query = params.toString();
    window.history.replaceState(window.history.state, "", `${window.location.pathname}${query ? `?${query}` : ""}`);
  }, [filterKey, raceFilter, racer, view]);

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
  const report = standings.data?.standings;
  // Races in the event's order (scheduled start, then name).
  const byId = new Map((report?.races ?? []).map((r) => [r.race.id, r]));
  const races = event.data.event.races.flatMap((r) => byId.get(r.id) ?? []);
  const allRaces = event.data.event.races.map((r) => ({ id: r.id, name: r.name }));
  const shown = raceFilter.length ? races.filter((r) => raceFilter.includes(r.race.id)) : races;
  const canAct = roleCanAct(official.role);
  const scheduledById = new Map(event.data.event.races.map((r) => [r.id, r.scheduledAtMs]));

  return (
    <Box sx={{ display: "grid", gridTemplateColumns: "minmax(0, 1fr) 380px", gap: 2, p: 2, alignItems: "start" }}>
      <Box component="main">
        <EventNav eventId={eventId} eventName={event.data.event.name} current="race" admin={official.role === "admin"} />
        {standings.error && <Alert severity="error" sx={{ mb: 2 }}>{standings.error.message}</Alert>}
        {report?.stale && <Alert severity="warning" sx={{ mb: 2 }}>Standings are out of date: {report.error}</Alert>}
        {!report && <LinearProgress />}
        {report && races.length === 0 && <Typography color="text.secondary">This event has no races yet.</Typography>}
        <Stack direction="row" spacing={2} sx={{ alignItems: "flex-start", mb: 2 }}>
          <FilterWithChips chips={raceFilter.flatMap((id) => allRaces.filter((r) => r.id === id).map((r) => ({ key: r.id, label: r.name })))}
            onDelete={(id) => setRaceFilter(raceFilter.filter((x) => x !== id))}>
            <Autocomplete multiple size="small" disableCloseOnSelect options={allRaces} getOptionLabel={(r) => r.name}
              isOptionEqualToValue={(a, b) => a.id === b.id} value={allRaces.filter((r) => raceFilter.includes(r.id))}
              onChange={(_, picked) => setRaceFilter(picked.map((r) => r.id))} renderValue={() => null} sx={{ width: 260 }}
              renderInput={(params) => <TextField {...params} label="Race" placeholder={raceFilter.length ? "Add a race" : "All races"} />} />
          </FilterWithChips>
          {raceFilter.length > 0 && (
            <Stack sx={{ justifyContent: "center", minHeight: 40 }}>
              <Button size="small" onClick={() => setRaceFilter([])}>Clear filters</Button>
            </Stack>
          )}
          <Box sx={{ flex: 1 }} />
          <ToggleButtonGroup size="small" exclusive value={view} onChange={(_, v) => v && setView(v)} aria-label="Group results by">
            <ToggleButton value="category">Category</ToggleButton>
            <ToggleButton value="wave">Wave</ToggleButton>
          </ToggleButtonGroup>
        </Stack>
        {view === "wave" && groupWaves(shown.map((r) => ({ ...r, scheduledAtMs: scheduledById.get(r.race.id) ?? null }))).map((wave) => (
          <WaveStandings key={wave.scheduledAtMs ?? "none"} wave={wave} onRowClick={(row) => setRacer(row.bib)}
            controls={wave.startedRaceId && <FlagOut raceId={wave.startedRaceId} flagOutAtMs={wave.flagOutAtMs} leaderBib={wave.flagOutLeaderBib} canAct={canAct} onChanged={refresh} />} />
        ))}
        {view === "category" && shown.map((race) => (
          <Standings
            key={race.race.id}
            race={race}
            controls={<RaceControls raceId={race.race.id} startAtMs={race.startAtMs} lapCount={race.lapCount} flagOutAtMs={race.flagOutAtMs} flagOutLeaderBib={race.flagOutLeaderBib} canAct={canAct} onChanged={refresh} />}
            onRowClick={(row) => setRacer(row.bib)}
          />
        ))}
      </Box>
      <ReviewQueue eventId={eventId} suggestions={report?.suggestions ?? []} labels={unassignedLabels(report)} canAct={canAct} onChanged={refresh}
        raceNames={new Map(races.map((r) => [r.race.id, r.race.name]))}
        racerNames={new Map(races.flatMap((r) => r.rows.map((row) => [row.bib, row.name] as const)))} />
      {racer && (
        <RacerPanel key={racer} eventId={eventId} bib={racer} canAct={canAct} onClose={() => setRacer(null)} onChanged={refresh}
          racerNames={new Map(races.flatMap((r) => r.rows.map((row) => [row.bib, row.name] as const)))} />
      )}
    </Box>
  );
}
