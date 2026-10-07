import { useQuery } from "@apollo/client/react";
import Alert from "@mui/material/Alert";
import Box from "@mui/material/Box";
import LinearProgress from "@mui/material/LinearProgress";
import Typography from "@mui/material/Typography";
import { useCallback, useEffect } from "react";
import { EVENT, STANDINGS, type EventData, type StandingsData } from "../queries";
import { unassignedLabels } from "../problems";
import { canAct as roleCanAct, isSignedOutError } from "../roles";
import type { Official } from "../session";
import { useEventChanges } from "../useEventChanges";
import { EventNav } from "./EventNav";
import { RaceControls } from "./RaceControls";
import { ReviewQueue } from "./ReviewQueue";
import { RacerStatusMenu } from "./RacerStatusMenu";
import { Standings } from "./Standings";

type Props = { eventId: string; official: Official; onSignedOut: () => void };

export function RaceScreen({ eventId, official, onSignedOut }: Props) {
  const event = useQuery<EventData>(EVENT, { variables: { id: eventId } });
  const standings = useQuery<StandingsData>(STANDINGS, { variables: { eventId }, pollInterval: 5000, fetchPolicy: "network-only" });

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
  const canAct = roleCanAct(official.role);

  return (
    <Box sx={{ display: "grid", gridTemplateColumns: "1fr 380px", gap: 2, p: 2, alignItems: "start" }}>
      <Box component="main">
        <EventNav eventId={eventId} eventName={event.data.event.name} current="race" admin={official.role === "admin"} />
        {standings.error && <Alert severity="error" sx={{ mb: 2 }}>{standings.error.message}</Alert>}
        {report?.stale && <Alert severity="warning" sx={{ mb: 2 }}>Standings are out of date: {report.error}</Alert>}
        {!report && <LinearProgress />}
        {report && races.length === 0 && <Typography color="text.secondary">This event has no races yet.</Typography>}
        {races.map((race) => (
          <Standings
            key={race.race.id}
            race={race}
            controls={<RaceControls raceId={race.race.id} startAtMs={race.startAtMs} lapCount={race.lapCount} canAct={canAct} onChanged={refresh} />}
            rowActions={canAct ? (row) => <RacerStatusMenu eventId={eventId} row={row} onChanged={refresh} /> : undefined}
          />
        ))}
      </Box>
      <ReviewQueue eventId={eventId} suggestions={report?.suggestions ?? []} labels={unassignedLabels(report)} canAct={canAct} onChanged={refresh} />
    </Box>
  );
}
