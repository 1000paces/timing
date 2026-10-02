import { useEffect, useState } from "react";

export type Route = { view: "events" } | { view: "event"; eventId: string; groupId: string | null };

export function parseRoute(hash: string): Route {
  const parts = hash.replace(/^#\/?/, "").split("/").filter(Boolean);
  if (parts[0] === "events" && parts[1]) {
    const groupId = parts[2] === "groups" && parts[3] ? decodeURIComponent(parts[3]) : null;
    return { view: "event", eventId: decodeURIComponent(parts[1]), groupId };
  }
  return { view: "events" };
}

export function eventHref(eventId: string, groupId?: string | null): string {
  const base = `#/events/${encodeURIComponent(eventId)}`;
  return groupId ? `${base}/groups/${encodeURIComponent(groupId)}` : base;
}

export function useRoute(): Route {
  const [route, setRoute] = useState(() => parseRoute(window.location.hash));
  useEffect(() => {
    const update = () => setRoute(parseRoute(window.location.hash));
    window.addEventListener("hashchange", update);
    return () => window.removeEventListener("hashchange", update);
  }, []);
  return route;
}
