export type RegistrationRow = {
  id: string;
  bib: string | null;
  age: number | null; // entered or imported for this event
  racingAge: number | null; // age, else from the birth date by the event's age rule
  source: string;
  checkedInAtMs: number | null;
  eligibilityWarnings: string[];
  race: { id: string; name: string };
  racer: {
    firstName: string;
    lastName: string;
    gender: string;
    team: string | null;
    licenseNumber: string | null;
    birthDate: string | null;
    city: string | null;
    state: string | null;
  };
};

export type RegistrationFilter = { terms: string[]; raceIds: string[]; needsBib: boolean; notCheckedIn: boolean };

export const NO_FILTER: RegistrationFilter = { terms: [], raceIds: [], needsBib: false, notCheckedIn: false };

// Each filter in use must pass. Within Search and Race, any value may match:
// several search terms (name, bib, team or license, ignoring case) or races.
export function filterRegistrations(rows: RegistrationRow[], filter: RegistrationFilter): RegistrationRow[] {
  const needles = filter.terms.map((t) => t.trim().toLowerCase()).filter(Boolean);
  return rows.filter((r) => {
    if (filter.raceIds.length && !filter.raceIds.includes(r.race.id)) return false;
    if (filter.needsBib && r.bib) return false;
    if (filter.notCheckedIn && r.checkedInAtMs != null) return false;
    if (!needles.length) return true;
    const haystack = [`${r.racer.firstName} ${r.racer.lastName}`, r.bib, r.racer.team, r.racer.licenseNumber].map((v) => v?.toLowerCase());
    return needles.some((needle) => haystack.some((value) => value?.includes(needle)));
  });
}

export type RegistrationCounts = { registered: number; checkedIn: number; needsBib: number };

export function countRegistrations(rows: RegistrationRow[]): RegistrationCounts {
  return {
    registered: rows.length,
    checkedIn: rows.filter((r) => r.checkedInAtMs != null).length,
    needsBib: rows.filter((r) => !r.bib).length,
  };
}

export type StatLabels = { racers: string; checkedIn: string; needsBib: string; checkedInPercent: number };

// Labels for the stat tiles, describing the rows shown ("N of TOTAL racers"
// when a filter hides some).
export function statLabels({ registered, checkedIn, needsBib }: RegistrationCounts, total = registered): StatLabels {
  return {
    racers: registered === total ? `${registered} racers` : `${registered} of ${total} racers`,
    checkedIn: `${checkedIn} of ${registered} checked in`,
    needsBib: `${needsBib} ${needsBib === 1 ? "needs" : "need"} a bib`,
    checkedInPercent: registered ? Math.round((checkedIn / registered) * 100) : 0,
  };
}

// Filters live in the page address (?q=..&q=..&race=..&needsBib=1&notCheckedIn=1)
// so a refresh keeps them and the link can be shared.
export function filterFromSearch(search: string): RegistrationFilter {
  const params = new URLSearchParams(search);
  return {
    terms: params.getAll("q").filter((t) => t.trim()),
    raceIds: params.getAll("race").filter(Boolean),
    needsBib: params.get("needsBib") === "1",
    notCheckedIn: params.get("notCheckedIn") === "1",
  };
}

export function filterToSearch(filter: RegistrationFilter): string {
  const params = new URLSearchParams();
  filter.terms.filter((t) => t.trim()).forEach((t) => params.append("q", t));
  filter.raceIds.forEach((id) => params.append("race", id));
  if (filter.needsBib) params.set("needsBib", "1");
  if (filter.notCheckedIn) params.set("notCheckedIn", "1");
  const query = params.toString();
  return query ? `?${query}` : "";
}

export const SORT_KEYS = ["bib", "name", "gender", "age", "team", "race", "checkedIn"] as const;
export type SortKey = (typeof SORT_KEYS)[number];
export type RegistrationSort = { key: SortKey; dir: "asc" | "desc" };
export const DEFAULT_SORT: RegistrationSort = { key: "bib", dir: "asc" };

// A value to compare, or null for "nothing here" (always sorted last).
function sortValue(r: RegistrationRow, key: SortKey): string | number | null {
  switch (key) {
    case "bib":
      return r.bib ? Number(r.bib) || r.bib : null;
    case "name":
      return `${r.racer.lastName} ${r.racer.firstName}`.toLowerCase();
    case "gender":
      return r.racer.gender;
    case "age":
      return r.racingAge;
    case "team":
      return r.racer.team?.toLowerCase() || null;
    case "race":
      return r.race.name.toLowerCase();
    case "checkedIn":
      return r.checkedInAtMs != null ? 0 : 1; // checked in first
  }
}

export function sortRegistrations(rows: RegistrationRow[], sort: RegistrationSort): RegistrationRow[] {
  const sign = sort.dir === "asc" ? 1 : -1;
  return [...rows].sort((a, b) => {
    const x = sortValue(a, sort.key);
    const y = sortValue(b, sort.key);
    if (x == null || y == null) return x == null && y == null ? 0 : x == null ? 1 : -1;
    if (typeof x === "number" && typeof y === "number") return (x - y) * sign;
    return String(x).localeCompare(String(y), undefined, { numeric: true }) * sign;
  });
}

export function sortFromSearch(search: string): RegistrationSort {
  const params = new URLSearchParams(search);
  const key = params.get("sort");
  if (!SORT_KEYS.includes(key as SortKey)) return DEFAULT_SORT;
  return { key: key as SortKey, dir: params.get("dir") === "desc" ? "desc" : "asc" };
}

export function sortToSearch(sort: RegistrationSort): [string, string][] {
  return [["sort", sort.key], ["dir", sort.dir]];
}
