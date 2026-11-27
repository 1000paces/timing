import type { StandingsData, Suggestion } from "./queries";
import { unassignedLabel } from "./races";

// The kinds of problem the review queue raises, as officials think of them.
export const PROBLEM_TYPES = [
  { id: "missed", label: "Missed crossing", color: "warning" },
  { id: "duplicate", label: "Duplicate tap", color: "warning" },
  { id: "lapped", label: "About to be lapped", color: "info" },
  { id: "overdue", label: "Overdue", color: "warning" },
  { id: "noBib", label: "No bib", color: "error" },
  { id: "unknownRacer", label: "Unknown racer", color: "error" },
  { id: "clock", label: "Clock not synced", color: "default" },
] as const;
export type ProblemTypeId = (typeof PROBLEM_TYPES)[number]["id"];
export const PROBLEM_TYPE = Object.fromEntries(PROBLEM_TYPES.map((t) => [t.id, t])) as Record<ProblemTypeId, (typeof PROBLEM_TYPES)[number]>;

const BY_KIND: Record<string, ProblemTypeId> = {
  SUSPECTED_MISSED_CROSSING: "missed",
  SUSPECTED_DUPLICATE: "duplicate",
  ABOUT_TO_BE_LAPPED: "lapped",
  OVERDUE: "overdue",
  UNSYNCED_CLOCK: "clock",
};

// Crossings the hub couldn't place have no race: no bib at all, or a bib nobody is registered under.
export function problemType(s: Suggestion): ProblemTypeId {
  if (s.kind === "UNASSIGNED_CAPTURE") return s.bib ? "unknownRacer" : "noBib";
  return BY_KIND[s.kind] ?? "clock";
}

export type Problem = { suggestion: Suggestion; type: ProblemTypeId; raceId: string | null; name: string | null };
export type ProblemFilter = { types: string[]; raceIds: string[]; terms: string[] }; // raceIds may include "none"
export const NO_PROBLEM_FILTER: ProblemFilter = { types: [], raceIds: [], terms: [] };

// Each filter in use must pass; within one, any value may match. Search matches bib or racer name.
export function filterProblems(problems: Problem[], filter: ProblemFilter): Problem[] {
  const needles = filter.terms.map((t) => t.trim().toLowerCase()).filter(Boolean);
  return problems.filter((p) => {
    if (filter.types.length && !filter.types.includes(p.type)) return false;
    if (filter.raceIds.length && !filter.raceIds.includes(p.raceId ?? "none")) return false;
    if (!needles.length) return true;
    const haystack = [p.suggestion.bib, p.name].map((v) => v?.toLowerCase());
    return needles.some((needle) => haystack.some((value) => value?.includes(needle)));
  });
}

export function typeCounts(problems: Problem[]): Partial<Record<ProblemTypeId, number>> {
  const counts: Partial<Record<ProblemTypeId, number>> = {};
  for (const p of problems) counts[p.type] = (counts[p.type] ?? 0) + 1;
  return counts;
}

export function issuesLabel(shown: number, total: number): string {
  const noun = total === 1 ? "issue" : "issues";
  return shown === total ? `${total} ${noun}` : `${shown} of ${total} ${noun}`;
}

const TYPE_IDS = new Set<string>(PROBLEM_TYPES.map((t) => t.id));

export function problemFilterFromSearch(search: string): ProblemFilter {
  const params = new URLSearchParams(search);
  return {
    types: params.getAll("type").filter((t) => TYPE_IDS.has(t)),
    raceIds: params.getAll("race").filter(Boolean),
    terms: params.getAll("q").filter((t) => t.trim()),
  };
}

export function problemFilterToSearch(filter: ProblemFilter): string {
  const params = new URLSearchParams();
  filter.types.forEach((t) => params.append("type", t));
  filter.raceIds.forEach((r) => params.append("race", r));
  filter.terms.filter((t) => t.trim()).forEach((t) => params.append("q", t));
  const query = params.toString();
  return query ? `?${query}` : "";
}

// Readable lines for no-bib / unknown-bib crossings, keyed like their suggestions.
export function unassignedLabels(report: StandingsData["standings"] | undefined): Map<string, string> {
  const starts = (report?.races ?? []).flatMap((r) => (r.startAtMs == null ? [] : [r.startAtMs]));
  return new Map((report?.unassigned ?? []).map((u) => [`unassigned:${u.captureId}`, unassignedLabel(u, starts)]));
}
