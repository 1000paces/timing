import { useQuery } from "@apollo/client/react";
import Alert from "@mui/material/Alert";
import Box from "@mui/material/Box";
import LinearProgress from "@mui/material/LinearProgress";
import Tab from "@mui/material/Tab";
import Tabs from "@mui/material/Tabs";
import Typography from "@mui/material/Typography";
import { useCallback, useEffect } from "react";
import { EVENT, STANDINGS, type EventData, type StandingsData } from "../queries";
import { canAct as roleCanAct, isSignedOutError } from "../roles";
import { linkTo, raceHref } from "../route";
import type { Official } from "../session";
import { useEventChanges } from "../useEventChanges";
import { EventNav } from "./EventNav";
import { GroupControls } from "./GroupControls";
import { ReviewQueue } from "./ReviewQueue";
import { Standings } from "./Standings";

type Props = { eventId: string; groupId: string | null; official: Official; onSignedOut: () => void };

export function RaceScreen({ eventId, groupId, official, onSignedOut }: Props) {
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

  const groups = event.data?.event.startGroups ?? [];
  const group = groups.find((g) => g.id === groupId) ?? groups[0];
  if (!event.data) {
    return <Box sx={{ p: 3 }}>{event.error ? <Alert severity="error">{event.error.message}</Alert> : <LinearProgress />}</Box>;
  }
  if (!group) return <Typography sx={{ p: 3 }} color="text.secondary">This event has no start groups.</Typography>;

  const raceIds = new Set(group.races.map((r) => r.id));
  const report = standings.data?.standings;
  const races = report?.races.filter((r) => raceIds.has(r.race.id)) ?? [];
  const starts = races.map((r) => r.startAtMs).filter((ms): ms is number => ms != null);
  // null = not known until standings have loaded.
  const started = !report ? null : starts.length > 0;
  const canAct = roleCanAct(official.role);

  return (
    <Box sx={{ display: "grid", gridTemplateColumns: "1fr 380px", gap: 2, p: 2, alignItems: "start" }}>
      <Box component="main">
        <EventNav eventId={eventId} eventName={event.data.event.name} current="race" />
        {groups.length > 1 && (
          <Tabs value={group.id} sx={{ mb: 2 }}>
            {groups.map((g) => (
              <Tab key={g.id} value={g.id} label={g.name} component="a" {...linkTo(raceHref(eventId, g.id))} />
            ))}
          </Tabs>
        )}
        {standings.error && <Alert severity="error" sx={{ mb: 2 }}>{standings.error.message}</Alert>}
        {report?.stale && <Alert severity="warning" sx={{ mb: 2 }}>Standings are out of date: {report.error}</Alert>}
        <GroupControls
          key={group.id}
          groupId={group.id}
          started={started}
          startedAtMs={starts.length ? Math.min(...starts) : null}
          lapCount={races[0]?.lapCount ?? null}
          canAct={canAct}
          onChanged={refresh}
        />
        {races.map((race) => (
          <Standings key={race.race.id} race={race} />
        ))}
      </Box>
      <ReviewQueue eventId={eventId} suggestions={report?.suggestions ?? []} canAct={canAct} onChanged={refresh} />
    </Box>
  );
}
