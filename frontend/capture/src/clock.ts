export type ClockSample = { t0: number; t1: number; t2: number; t3: number };

// NTP-style: offset = ((t1 - t0) + (t2 - t3)) / 2; keep the fastest round trip.
export function pickOffset(samples: ClockSample[]): { offsetMs: number; rttMs: number } {
  const measured = samples.map(({ t0, t1, t2, t3 }) => ({ offsetMs: Math.round((t1 - t0 + (t2 - t3)) / 2), rttMs: t3 - t0 - (t2 - t1) }));
  return measured.reduce((best, m) => (m.rttMs < best.rttMs ? m : best));
}
