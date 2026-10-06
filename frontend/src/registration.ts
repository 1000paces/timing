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

export type RegistrationFilter = { search: string; raceId: string | null; needsBib: boolean; notCheckedIn: boolean };

// Search matches name, bib, team or license, ignoring case.
export function filterRegistrations(rows: RegistrationRow[], filter: RegistrationFilter): RegistrationRow[] {
  const needle = filter.search.trim().toLowerCase();
  return rows.filter((r) => {
    if (filter.raceId && r.race.id !== filter.raceId) return false;
    if (filter.needsBib && r.bib) return false;
    if (filter.notCheckedIn && r.checkedInAtMs != null) return false;
    if (!needle) return true;
    const haystack = [`${r.racer.firstName} ${r.racer.lastName}`, r.bib, r.racer.team, r.racer.licenseNumber];
    return haystack.some((value) => value?.toLowerCase().includes(needle));
  });
}

export function countsLabel({ registered, checkedIn, needsBib }: { registered: number; checkedIn: number; needsBib: number }): string {
  return `${registered} registered · ${checkedIn} checked in · ${needsBib} ${needsBib === 1 ? "needs" : "need"} a bib`;
}
