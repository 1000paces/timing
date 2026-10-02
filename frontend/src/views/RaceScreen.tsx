import { useQuery } from "@apollo/client/react";
import Alert from "@mui/material/Alert";
import Box from "@mui/material/Box";
import LinearProgress from "@mui/material/LinearProgress";
import Tab from "@mui/material/Tab";
import Tabs from "@mui/material/Tabs";
import Typography from "@mui/material/Typography";
import { useCallback, useEffect } from "react";
import { EVENT, RULINGS, STANDINGS, type EventData, type RulingsData, type StandingsData } from "../queries";
import { canAct as roleCanAct, isSignedOutError } from "../roles";
import { eventHref } from "../route";
import type { Official } from "../session";
import { useEventChanges } from "../useEventChanges";
import { GroupControls } from "./GroupControls";
import { ReviewQueue } from "./ReviewQueue";
import { Standings } from "./Standings";

type Props = { eventId: string; groupId: string | null; official: Official; onSignedOut: () => void };

export function RaceScreen({ eventId, groupId, official, onSignedOut }: Props) {
  const event = useQuery<EventData>(EVENT, { variables: { id: eventId } });
  const standings = useQuery<StandingsData>(STANDINGS, { variables: { eventId }, pollInterval: 5000, fetchPolicy: "network-only" });
  const rulings = useQuery<RulingsData>(RULINGS, { variables: { eventId }, pollInterval: 5000, fetchPolicy: "network-only" });

  const refresh = useCallback(() => {
    void standings.refetch();
    void rulings.refetch();
  }, [standings, rulings]);
  useEventChanges(eventId, refresh);

  const firstError = event.error ?? standings.error ?? rulings.error;
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
  const start = rulings.data?.rulings.find(
    (r) => r.kind === "set_group_start" && !r.reverted && r.payload.start_group_id === group.id,
  );
  // null = not known yet: never offer GO until both standings and rulings have loaded.
  const started = start != null || races.some((r) => r.state !== "NOT_STARTED") ? true : report && rulings.data ? false : null;
  const canAct = roleCanAct(official.role);

  return (
    <Box sx={{ display: "grid", gridTemplateColumns: "1fr 380px", gap: 2, p: 2, alignItems: "start" }}>
      <Box component="main">
        <Typography variant="h4" component="h1" gutterBottom>
          {event.data.event.name}
        </Typography>
        <Tabs value={group.id} sx={{ mb: 2 }}>
          {groups.map((g) => (
            <Tab key={g.id} value={g.id} label={g.name} component="a" href={eventHref(eventId, g.id)} />
          ))}
        </Tabs>
        {(standings.error || rulings.error) && (
          <Alert severity="error" sx={{ mb: 2 }}>{(standings.error ?? rulings.error)!.message}</Alert>
        )}
        {report?.stale && <Alert severity="warning" sx={{ mb: 2 }}>Standings are out of date: {report.error}</Alert>}
        <GroupControls
          key={group.id}
          groupId={group.id}
          started={started}
          startedAtMs={typeof start?.payload.at_ms === "number" ? start.payload.at_ms : null}
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
