// "1st", "2nd", "3rd", "4th", … "11th", "21st".
export function positionLabel(n: number): string {
  const teen = n % 100 >= 11 && n % 100 <= 13;
  const suffix = teen ? "th" : ({ 1: "st", 2: "nd", 3: "rd" } as Record<number, string>)[n % 10] ?? "th";
  return `${n}${suffix}`;
}

// Why a crossing didn't count (null for counted ones).
export function kindLabel(kind: string): string | null {
  return ({ DUPLICATE: "duplicate", BEFORE_START: "before start", AFTER_FINISH: "after finish", AFTER_PULL: "after pull" } as Record<string, string>)[kind] ?? null;
}

// Halfway between two times (whole milliseconds), to pre-fill a missed crossing.
export const midpoint = (a: number, b: number) => Math.floor((a + b) / 2);
