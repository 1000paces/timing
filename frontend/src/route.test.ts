import { describe, expect, it } from "vitest";
import { eventsHref, parseRoute, raceHref, startsHref } from "./route";

const ID = "01a0fd27-794b-7839-a46f-5c115e45f703";

describe("parseRoute", () => {
  it("defaults to the event list", () => {
    expect(parseRoute("/console/")).toEqual({ view: "events" });
    expect(parseRoute("/console")).toEqual({ view: "events" });
    expect(parseRoute("/console/nonsense")).toEqual({ view: "events" });
  });

  it("reads the start screen", () => {
    expect(parseRoute(`/console/event/${ID}/starts`)).toEqual({ view: "starts", eventId: ID });
  });

  it("reads the race screen with an optional start group", () => {
    expect(parseRoute(`/console/event/${ID}`)).toEqual({ view: "race", eventId: ID });
  });

  it("round-trips through the href builders", () => {
    expect(eventsHref()).toBe("/console/");
    expect(startsHref(ID)).toBe(`/console/event/${ID}/starts`);
    expect(parseRoute(raceHref("a b"))).toEqual({ view: "race", eventId: "a b" });
    expect(raceHref(ID)).toBe(`/console/event/${ID}`);
  });
});

describe("setup route", () => {
  it("reads and builds the setup screen address", async () => {
    const { setupHref } = await import("./route");
    expect(parseRoute(`/console/event/${ID}/setup`)).toEqual({ view: "setup", eventId: ID });
    expect(setupHref(ID)).toBe(`/console/event/${ID}/setup`);
  });
});
