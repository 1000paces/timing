import { useQuery } from "@apollo/client/react";
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
  if (!event.data) return <p className="page muted">{event.error ? event.error.message : "Loading…"}</p>;
  if (!group) return <p className="page muted">This event has no start groups.</p>;

  const raceIds = new Set(group.races.map((r) => r.id));
  const report = standings.data?.standings;
  const races = report?.races.filter((r) => raceIds.has(r.race.id)) ?? [];
  const started = races.some((r) => r.state !== "NOT_STARTED");
  const start = rulings.data?.rulings.find(
    (r) => r.kind === "set_group_start" && !r.reverted && r.payload.start_group_id === group.id,
  );
  const canAct = roleCanAct(official.role);

  return (
    <div className="race-screen">
      <main>
        <h1>{event.data.event.name}</h1>
        <nav className="groups">
          {groups.map((g) => (
            <a key={g.id} href={eventHref(eventId, g.id)} className={g.id === group.id ? "current" : ""}>
              {g.name}
            </a>
          ))}
        </nav>
        {(standings.error || rulings.error) && <p className="error">{(standings.error ?? rulings.error)!.message}</p>}
        {report?.stale && <p className="warning">Standings are out of date: {report.error}</p>}
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
      </main>
      <ReviewQueue eventId={eventId} suggestions={report?.suggestions ?? []} canAct={canAct} onChanged={refresh} />
    </div>
  );
}
