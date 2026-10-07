import { useQuery } from "@apollo/client/react";
import Alert from "@mui/material/Alert";
import Autocomplete from "@mui/material/Autocomplete";
import Button from "@mui/material/Button";
import Stack from "@mui/material/Stack";
import TextField from "@mui/material/TextField";
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
import { EventNav } from "./EventNav";
import { FilterWithChips } from "./FilterWithChips";
import { RaceControls } from "./RaceControls";
import { ReviewQueue } from "./ReviewQueue";
import { RacerStatusMenu } from "./RacerStatusMenu";
import { Standings } from "./Standings";

type Props = { eventId: string; official: Official; onSignedOut: () => void };

export function RaceScreen({ eventId, official, onSignedOut }: Props) {
  const event = useQuery<EventData>(EVENT, { variables: { id: eventId } });
  const standings = useQuery<StandingsData>(STANDINGS, { variables: { eventId }, pollInterval: 5000, fetchPolicy: "network-only" });
  const [raceFilter, setRaceFilter] = useState<string[]>(() => raceIdsFromSearch(window.location.search));
  useEffect(() => {
    window.history.replaceState(window.history.state, "", `${window.location.pathname}${raceIdsToSearch(raceFilter)}`);
  }, [raceFilter]);

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

  return (
    <Box sx={{ display: "grid", gridTemplateColumns: "1fr 380px", gap: 2, p: 2, alignItems: "start" }}>
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
        </Stack>
        {shown.map((race) => (
          <Standings
            key={race.race.id}
            race={race}
            controls={<RaceControls raceId={race.race.id} startAtMs={race.startAtMs} lapCount={race.lapCount} canAct={canAct} onChanged={refresh} />}
            rowActions={canAct ? (row) => <RacerStatusMenu eventId={eventId} row={row} onChanged={refresh} /> : undefined}
          />
        ))}
      </Box>
      <ReviewQueue eventId={eventId} suggestions={report?.suggestions ?? []} labels={unassignedLabels(report)} canAct={canAct} onChanged={refresh}
        raceNames={new Map(races.map((r) => [r.race.id, r.race.name]))}
        racerNames={new Map(races.flatMap((r) => r.rows.map((row) => [row.bib, row.name] as const)))} />
    </Box>
  );
}
