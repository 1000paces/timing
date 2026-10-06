import { describe, expect, it } from "vitest";
import { countRegistrations, statLabels, filterFromSearch, sortFromSearch, sortRegistrations, sortToSearch, filterRegistrations, filterToSearch, type RegistrationRow } from "./registration";

const row = (over: Partial<RegistrationRow>): RegistrationRow => ({
  id: "r",
  bib: null,
  age: null,
  racingAge: null,
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
  const none = { terms: [], raceIds: [], needsBib: false, notCheckedIn: false };

  it("searches name, bib, team and license, ignoring case", () => {
    expect(filterRegistrations(all, { ...none, terms: ["ray"] })).toEqual([bob]);
    expect(filterRegistrations(all, { ...none, terms: ["101"] })).toEqual([ann]);
    expect(filterRegistrations(all, { ...none, terms: ["velo"] })).toEqual([ann]);
    expect(filterRegistrations(all, { ...none, terms: ["l77"] })).toEqual([bob]);
    expect(filterRegistrations(all, { ...none, terms: ["ann lee"] })).toEqual([ann]);
  });

  it("several search terms match any of them; blank terms are ignored", () => {
    expect(filterRegistrations(all, { ...none, terms: ["ray", "101"] })).toEqual([ann, bob]);
    expect(filterRegistrations(all, { ...none, terms: ["ray", "nobody"] })).toEqual([bob]);
    expect(filterRegistrations(all, { ...none, terms: ["  "] })).toEqual(all);
  });

  it("filters by any of several races, missing bib and not checked in", () => {
    expect(filterRegistrations(all, { ...none, raceIds: ["masters"] })).toEqual([bob]);
    expect(filterRegistrations(all, { ...none, raceIds: ["masters", "cat3"] })).toEqual(all);
    expect(filterRegistrations(all, { ...none, needsBib: true })).toEqual([bob]);
    expect(filterRegistrations(all, { ...none, notCheckedIn: true })).toEqual([ann]);
    expect(filterRegistrations(all, { ...none, terms: ["ray"], raceIds: ["cat3"] })).toEqual([]);
  });
});

describe("statLabels", () => {
  it("labels the racer, check-in and bib tiles", () => {
    expect(statLabels({ registered: 168, checkedIn: 42, needsBib: 6 })).toEqual({
      racers: "168 racers", checkedIn: "42 of 168 checked in", needsBib: "6 need a bib", checkedInPercent: 25,
    });
    expect(statLabels({ registered: 1, checkedIn: 0, needsBib: 1 }).needsBib).toBe("1 needs a bib");
    expect(statLabels({ registered: 0, checkedIn: 0, needsBib: 0 }).checkedInPercent).toBe(0);
  });

  it("shows the filtered count out of the event's total when a filter hides some", () => {
    expect(statLabels({ registered: 5, checkedIn: 2, needsBib: 1 }, 31).racers).toBe("5 of 31 racers");
    expect(statLabels({ registered: 31, checkedIn: 4, needsBib: 0 }, 31).racers).toBe("31 racers");
  });

  it("counts rows", () => {
    const rows = [row({ id: "1", bib: "1", checkedInAtMs: 5 }), row({ id: "2" }), row({ id: "3", bib: "3" })];
    expect(countRegistrations(rows)).toEqual({ registered: 3, checkedIn: 1, needsBib: 1 });
  });
});

describe("filters in the page address", () => {
  it("round-trips through the query string", () => {
    const filter = { terms: ["lee ann", "101"], raceIds: ["r-1", "r-2"], needsBib: true, notCheckedIn: false };
    const search = filterToSearch(filter);
    expect(search).toBe("?q=lee+ann&q=101&race=r-1&race=r-2&needsBib=1");
    expect(filterFromSearch(search)).toEqual(filter);
  });

  it("defaults to no filters", () => {
    expect(filterFromSearch("")).toEqual({ terms: [], raceIds: [], needsBib: false, notCheckedIn: false });
    expect(filterToSearch({ terms: ["  "], raceIds: [], needsBib: false, notCheckedIn: false })).toBe("");
  });
});

describe("sortRegistrations", () => {
  const racer = row({}).racer;
  const ann = row({ id: "a", bib: "20", racingAge: 41, checkedInAtMs: 1, race: { id: "w", name: "Women Open" }, racer: { ...racer, firstName: "Ann", lastName: "Lee", gender: "F", team: "Velo" } });
  const bob = row({ id: "b", bib: "3", age: 30, racingAge: 30, race: { id: "c", name: "Cat 3 Men" }, racer: { ...racer, firstName: "Bob", lastName: "Ray", gender: "M", team: null } });
  const cy = row({ id: "c", bib: null, age: null, racingAge: 35, race: { id: "c", name: "Cat 3 Men" }, racer: { ...racer, firstName: "Cy", lastName: "Dee", gender: "M", team: "Spoke" } });
  const ids = (rows: RegistrationRow[]) => rows.map((r) => r.id).join("");

  it("sorts bibs as numbers, with racers lacking a bib last either way", () => {
    expect(ids(sortRegistrations([ann, bob, cy], { key: "bib", dir: "asc" }))).toBe("bac");
    expect(ids(sortRegistrations([ann, bob, cy], { key: "bib", dir: "desc" }))).toBe("abc");
  });

  it("sorts names by last then first name, and the other columns", () => {
    expect(ids(sortRegistrations([ann, bob, cy], { key: "name", dir: "asc" }))).toBe("cab");
    expect(ids(sortRegistrations([ann, bob, cy], { key: "age", dir: "asc" }))).toBe("bca"); // racing age
    expect(ids(sortRegistrations([ann, bob, cy], { key: "team", dir: "asc" }))).toBe("cab");
    expect(ids(sortRegistrations([ann, bob, cy], { key: "race", dir: "desc" }))).toBe("abc");
    expect(ids(sortRegistrations([ann, bob, cy], { key: "checkedIn", dir: "asc" }))).toBe("abc");
    expect(ids(sortRegistrations([ann, bob, cy], { key: "gender", dir: "asc" }))).toBe("abc");
  });

  it("keeps the sort in the page address", () => {
    expect(sortToSearch({ key: "name", dir: "desc" })).toEqual([["sort", "name"], ["dir", "desc"]]);
    expect(sortFromSearch("?q=x&sort=name&dir=desc")).toEqual({ key: "name", dir: "desc" });
    expect(sortFromSearch("?sort=nonsense")).toEqual({ key: "bib", dir: "asc" });
  });
});
