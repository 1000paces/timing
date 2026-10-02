import { useQuery } from "@apollo/client/react";
import { useEffect } from "react";
import { EVENTS, type EventsData } from "../queries";
import { isSignedOutError } from "../roles";
import { eventHref } from "../route";

export function Events({ onSignedOut }: { onSignedOut: () => void }) {
  const { data, error, loading } = useQuery<EventsData>(EVENTS, { fetchPolicy: "network-only" });
  useEffect(() => {
    if (isSignedOutError(error)) onSignedOut();
  }, [error, onSignedOut]);

  return (
    <div className="page">
      <h1>Events</h1>
      {loading && <p className="muted">Loading…</p>}
      {error && <p className="error">{error.message}</p>}
      <ul>
        {data?.events.map((event) => (
          <li key={event.id}>
            <a href={eventHref(event.id)}>
              {event.name} — {event.date}
            </a>
          </li>
        ))}
      </ul>
      {data && data.events.length === 0 && <p className="muted">No events yet.</p>}
    </div>
  );
}
