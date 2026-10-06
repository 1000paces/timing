export type RegistrationRow = {
  id: string;
  bib: string | null;
  age: number | null;
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

// Counts of the rows shown; "N of TOTAL" when a filter hides some.
export function countsLabel({ registered, checkedIn, needsBib }: RegistrationCounts, total = registered): string {
  const shown = registered === total ? `${registered}` : `${registered} of ${total}`;
  return `${shown} registered · ${checkedIn} checked in · ${needsBib} ${needsBib === 1 ? "needs" : "need"} a bib`;
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
