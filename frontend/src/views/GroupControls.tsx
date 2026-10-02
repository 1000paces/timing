import { useMutation } from "@apollo/client/react";
import { useRef, useState, type FormEvent } from "react";
import { formatClock } from "../format";
import { FIRE_START, SET_LAP_COUNT, type MutationResult } from "../queries";

type Props = {
  groupId: string;
  started: boolean | null; // null while not yet known
  startedAtMs: number | null;
  lapCount: number | null;
  canAct: boolean;
  onChanged: () => void;
};

export function GroupControls({ groupId, started, startedAtMs, lapCount, canAct, onChanged }: Props) {
  const [fireStart] = useMutation<{ fireStart: MutationResult }>(FIRE_START);
  const [setLapCount] = useMutation<{ setLapCount: MutationResult }>(SET_LAP_COUNT);
  const [firing, setFiring] = useState(false);
  const firingRef = useRef(false); // a ref, so a double-click's second event sees it immediately
  const [laps, setLaps] = useState("");
  const [error, setError] = useState<string | null>(null);

  async function go() {
    if (firingRef.current) return; // one GO per click burst (Review Focus 1)
    firingRef.current = true;
    setFiring(true);
    setError(null);
    try {
      const { data } = await fireStart({ variables: { startGroupId: groupId } });
      const errors = data?.fireStart.errors ?? [];
      if (errors.length) {
        setError(errors.join("; "));
        firingRef.current = false;
        setFiring(false);
      }
    } catch (e) {
      setError((e as Error).message);
      firingRef.current = false;
      setFiring(false);
    }
    onChanged();
  }

  async function submitLaps(event: FormEvent) {
    event.preventDefault();
    setError(null);
    try {
      const { data } = await setLapCount({ variables: { startGroupId: groupId, laps: Number(laps) } });
      const errors = data?.setLapCount.errors ?? [];
      if (errors.length) setError(errors.join("; "));
      else setLaps("");
    } catch (e) {
      setError((e as Error).message);
    }
    onChanged();
  }

  return (
    <div className="panel controls">
      {started ? (
        <strong>Started at {startedAtMs ? formatClock(startedAtMs) : "—"}</strong>
      ) : started === null ? (
        <span className="muted">Checking start…</span>
      ) : canAct ? (
        <button className="go" onClick={go} disabled={firing}>GO</button>
      ) : (
        <span className="muted">Not started</span>
      )}
      <span>Lap count: {lapCount ?? "not set"}</span>
      {canAct && (
        <form onSubmit={submitLaps} className="controls">
          <label>
            Laps <input type="number" min={1} value={laps} onChange={(e) => setLaps(e.target.value)} style={{ width: 64 }} />
          </label>
          <button type="submit" disabled={!laps}>Set laps</button>
        </form>
      )}
      {error && <span className="error">{error}</span>}
    </div>
  );
}
