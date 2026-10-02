import { describe, expect, it } from "vitest";
import { eventHref, parseRoute } from "./route";

describe("parseRoute", () => {
  it("defaults to the event list", () => {
    expect(parseRoute("")).toEqual({ view: "events" });
    expect(parseRoute("#/")).toEqual({ view: "events" });
    expect(parseRoute("#/nonsense")).toEqual({ view: "events" });
  });

  it("reads an event and optional start group", () => {
    expect(parseRoute("#/events/e1")).toEqual({ view: "event", eventId: "e1", groupId: null });
    expect(parseRoute("#/events/e1/groups/g2")).toEqual({ view: "event", eventId: "e1", groupId: "g2" });
  });

  it("round-trips through eventHref", () => {
    expect(parseRoute(eventHref("a b", "c/d"))).toEqual({ view: "event", eventId: "a b", groupId: "c/d" });
    expect(eventHref("e1")).toBe("#/events/e1");
  });
});
