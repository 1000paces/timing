# To Do — examine later

Items deliberately deferred. Each has enough context to pick up cold.

## Results engine

### Compare early laps against the field, not just the rider's own laps
- **Idea:** use the field's lap times as the comparison point for anomaly
  detection (missed crossing / short lap), especially early in a race.
- **Why:** with only 1–2 laps of their own, a rider's "typical lap" is easily
  distorted by a single missed crossing. (We already fixed the worst symptom: a
  `short` suggestion is no longer raised next to an abnormally long lap.)
- **Proposed shape:** use the field **median** (not average — one missed lap
  skews an average) of that lap index until the rider has ≥ 2 other laps of
  their own; then switch to the rider's own median. Riders' paces differ by
  30–40% across a field, so own-pace stays the better reference once available.
- **Catch:** in small fields the field median is fragile — in the 3-rider
  `missed-crossings.yml` golden race, one rider's missed lap skews the median and
  rider 3's genuine missed crossing would stop being flagged. Likely needs a
  minimum field size (e.g. ≥ 5 other riders with that lap) before trusting it.
- **Where:** `packs/results/lib/results/anomalies.rb` (`RaceLaps#typical`),
  spec §4.4 "Reference lap time".
- **Raised:** 2026-10-01.
