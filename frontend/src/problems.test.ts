import { describe, expect, it } from "vitest";
import { filterProblems, issuesLabel, problemFilterFromSearch, problemFilterToSearch, problemType, typeCounts, type Problem } from "./problems";
import type { Suggestion } from "./queries";

const suggestion = (over: Partial<Suggestion>): Suggestion => ({ key: "k", kind: "SUSPECTED_MISSED_CROSSING", bib: "101", raceId: "r1", message: "", needs: [], ...over });
const problem = (over: Partial<Suggestion>, name: string | null = "Ann Lee"): Problem => {
  const s = suggestion(over);
  return { suggestion: s, type: problemType(s), raceId: s.raceId, name };
};

describe("problemType", () => {
  it("names each kind; crossings without a race split into no bib and unknown racer", () => {
    expect(problemType(suggestion({ kind: "SUSPECTED_MISSED_CROSSING" }))).toBe("missed");
    expect(problemType(suggestion({ kind: "SUSPECTED_DUPLICATE" }))).toBe("duplicate");
    expect(problemType(suggestion({ kind: "OVERDUE" }))).toBe("overdue");
    expect(problemType(suggestion({ kind: "ABOUT_TO_BE_LAPPED" }))).toBe("lapped");
    expect(problemType(suggestion({ kind: "UNSYNCED_CLOCK", bib: null }))).toBe("clock");
    expect(problemType(suggestion({ kind: "UNASSIGNED_CAPTURE", bib: null }))).toBe("noBib");
    expect(problemType(suggestion({ kind: "UNASSIGNED_CAPTURE", bib: "400" }))).toBe("unknownRacer");
  });
});

describe("filterProblems", () => {
  const missed = problem({ key: "m", bib: "101" });
  const lapped = problem({ key: "l", kind: "ABOUT_TO_BE_LAPPED", bib: "205", raceId: "r2" }, "Bo Yu");
  const noBib = problem({ key: "n", kind: "UNASSIGNED_CAPTURE", bib: null, raceId: null }, null);
  const all = [missed, lapped, noBib];
  const none = { types: [], raceIds: [], terms: [] };

  it("filters by any of several types and races ('none' = no race)", () => {
    expect(filterProblems(all, { ...none, types: ["missed", "noBib"] })).toEqual([missed, noBib]);
    expect(filterProblems(all, { ...none, raceIds: ["r2", "none"] })).toEqual([lapped, noBib]);
  });

  it("searches bib or racer name", () => {
    expect(filterProblems(all, { ...none, terms: ["205"] })).toEqual([lapped]);
    expect(filterProblems(all, { ...none, terms: ["ann", "yu"] })).toEqual([missed, lapped]);
  });

  it("counts problems per type", () => {
    expect(typeCounts(all)).toEqual({ missed: 1, lapped: 1, noBib: 1 });
  });
});

describe("issuesLabel and the page address", () => {
  it("words the count", () => {
    expect(issuesLabel(5, 5)).toBe("5 issues");
    expect(issuesLabel(1, 1)).toBe("1 issue");
    expect(issuesLabel(2, 5)).toBe("2 of 5 issues");
  });

  it("round-trips filters through the query string", () => {
    const filter = { types: ["missed", "noBib"], raceIds: ["none"], terms: ["101"] };
    expect(problemFilterToSearch(filter)).toBe("?type=missed&type=noBib&race=none&q=101");
    expect(problemFilterFromSearch("?type=missed&type=noBib&race=none&q=101&type=bogus")).toEqual(filter);
  });
});
