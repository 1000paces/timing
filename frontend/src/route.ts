import { useEffect, useState, type MouseEvent } from "react";

// Real paths under /console/; the hub serves the console page for any of them.
export type Route =
  | { view: "events" }
  | { view: "setup"; eventId: string }
  | { view: "registration"; eventId: string }
  | { view: "problems"; eventId: string }
  | { view: "starts"; eventId: string }
  | { view: "capture"; eventId: string }
  | { view: "race"; eventId: string };

const BASE = "/console";
const CHANGE = "console:navigate";

export function parseRoute(pathname: string): Route {
  const parts = pathname.replace(/^\/console\/?/, "").split("/").filter(Boolean).map(decodeURIComponent);
  if (parts[0] === "event" && parts[1]) {
    if (parts[2] === "starts") return { view: "starts", eventId: parts[1] };
    if (parts[2] === "setup") return { view: "setup", eventId: parts[1] };
    if (parts[2] === "registration") return { view: "registration", eventId: parts[1] };
    if (parts[2] === "problems") return { view: "problems", eventId: parts[1] };
    if (parts[2] === "capture") return { view: "capture", eventId: parts[1] };
    return { view: "race", eventId: parts[1] };
  }
  return { view: "events" };
}

export const eventsHref = () => `${BASE}/`;
export const setupHref = (eventId: string) => `${BASE}/event/${encodeURIComponent(eventId)}/setup`;
export const registrationHref = (eventId: string) => `${BASE}/event/${encodeURIComponent(eventId)}/registration`;
export const problemsHref = (eventId: string) => `${BASE}/event/${encodeURIComponent(eventId)}/problems`;
export const captureHref = (eventId: string) => `${BASE}/event/${encodeURIComponent(eventId)}/capture`;
export const startsHref = (eventId: string) => `${BASE}/event/${encodeURIComponent(eventId)}/starts`;
export const raceHref = (eventId: string) => `${BASE}/event/${encodeURIComponent(eventId)}`;

export function navigate(href: string): void {
  window.history.pushState(null, "", href);
  window.dispatchEvent(new Event(CHANGE));
}

// Click handler for in-app links: plain left clicks navigate without a reload;
// modified clicks (new tab, etc.) keep the browser's behaviour.
export function linkTo(href: string) {
  return {
    href,
    onClick(event: MouseEvent) {
      if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      navigate(href);
    },
  };
}

export function useRoute(): Route {
  const [route, setRoute] = useState(() => parseRoute(window.location.pathname));
  useEffect(() => {
    const update = () => setRoute(parseRoute(window.location.pathname));
    window.addEventListener("popstate", update);
    window.addEventListener(CHANGE, update);
    return () => {
      window.removeEventListener("popstate", update);
      window.removeEventListener(CHANGE, update);
    };
  }, []);
  return route;
}
