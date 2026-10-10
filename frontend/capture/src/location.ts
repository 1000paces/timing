import type { Roster } from "./api";

// Where this phone is on the course (null: the finish line), and when that was
// last chosen, in hub time.
export type Location = { checkpointId: string | null; changedAtMs: number };

// The hub wins when an official moved the phone after the phone's own last change.
export function shouldAdopt(local: Location | null, hub: Roster["device"]): boolean {
  if (hub.checkpoint_set_at_ms == null) return false;
  if (local && hub.checkpoint_id === local.checkpointId) return false;
  return !local || hub.checkpoint_set_at_ms > local.changedAtMs;
}

export function locationName(checkpointId: string | null, roster: Pick<Roster, "checkpoints"> | null): string {
  if (checkpointId == null) return "Finish";
  return roster?.checkpoints.find((c) => c.id === checkpointId)?.name ?? "Unknown checkpoint";
}
