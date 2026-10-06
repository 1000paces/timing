import { describe, expect, it } from "vitest";
import { countsLabel, filterFromSearch, filterRegistrations, filterToSearch, type RegistrationRow } from "./registration";

const row = (over: Partial<RegistrationRow>): RegistrationRow => ({
  id: "r",
  bib: null,
  age: null,
  source: "import",
  checkedInAtMs: null,
  eligibilityWarnings: [],
  race: { id: "cat3", name: "Cat 3 Men" },
  racer: { firstName: "Ann", lastName: "Lee", gender: "F", team: null, licenseNumber: null, birthDate: null, city: null, state: null },
  ...over,
});

describe("filterRegistrations", () => {
  const ann = row({ id: "1", bib: "101", racer: { ...row({}).racer, team: "Velo" } });
  const bob = row({ id: "2", checkedInAtMs: 5, race: { id: "masters", name: "Masters" }, racer: { ...row({}).racer, firstName: "Bob", lastName: "Ray", licenseNumber: "L77" } });
  const all = [ann, bob];
  const none = { search: "", raceId: null, needsBib: false, notCheckedIn: false };

  it("searches name, bib, team and license, ignoring case", () => {
    expect(filterRegistrations(all, { ...none, search: "ray" })).toEqual([bob]);
    expect(filterRegistrations(all, { ...none, search: "101" })).toEqual([ann]);
    expect(filterRegistrations(all, { ...none, search: "velo" })).toEqual([ann]);
    expect(filterRegistrations(all, { ...none, search: "l77" })).toEqual([bob]);
    expect(filterRegistrations(all, { ...none, search: "ann lee" })).toEqual([ann]);
  });

  it("filters by race, missing bib and not checked in", () => {
    expect(filterRegistrations(all, { ...none, raceId: "masters" })).toEqual([bob]);
    expect(filterRegistrations(all, { ...none, needsBib: true })).toEqual([bob]);
    expect(filterRegistrations(all, { ...none, notCheckedIn: true })).toEqual([ann]);
  });
});

describe("countsLabel", () => {
  it("summarises registration counts", () => {
    expect(countsLabel({ registered: 168, checkedIn: 142, needsBib: 6 })).toBe("168 registered · 142 checked in · 6 need a bib");
    expect(countsLabel({ registered: 1, checkedIn: 0, needsBib: 1 })).toBe("1 registered · 0 checked in · 1 needs a bib");
  });
});

describe("filters in the page address", () => {
  it("round-trips through the query string", () => {
    const filter = { search: "lee ann", raceId: "r-1", needsBib: true, notCheckedIn: false };
    const search = filterToSearch(filter);
    expect(search).toBe("?q=lee+ann&race=r-1&needsBib=1");
    expect(filterFromSearch(search)).toEqual(filter);
  });

  it("defaults to no filters", () => {
    expect(filterFromSearch("")).toEqual({ search: "", raceId: null, needsBib: false, notCheckedIn: false });
    expect(filterToSearch({ search: "  ", raceId: null, needsBib: false, notCheckedIn: false })).toBe("");
  });
});
