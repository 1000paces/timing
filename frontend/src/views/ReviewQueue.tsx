import { useMutation } from "@apollo/client/react";
import { useState } from "react";
import { ACCEPT_SUGGESTION, DISMISS_SUGGESTION, type MutationResult, type Suggestion } from "../queries";

type Props = { eventId: string; suggestions: Suggestion[]; canAct: boolean; onChanged: () => void };

export function ReviewQueue({ eventId, suggestions, canAct, onChanged }: Props) {
  return (
    <aside className="panel queue">
      <h2>Review queue ({suggestions.length})</h2>
      {suggestions.length === 0 && <p className="muted">Nothing to review.</p>}
      <ul>
        {suggestions.map((s) => (
          <SuggestionItem key={s.key} eventId={eventId} suggestion={s} canAct={canAct} onChanged={onChanged} />
        ))}
      </ul>
    </aside>
  );
}

function SuggestionItem({ eventId, suggestion, canAct, onChanged }: { eventId: string; suggestion: Suggestion; canAct: boolean; onChanged: () => void }) {
  const [accept] = useMutation<{ acceptSuggestion: MutationResult }>(ACCEPT_SUGGESTION);
  const [dismiss] = useMutation<{ dismissSuggestion: MutationResult }>(DISMISS_SUGGESTION);
  const [bib, setBib] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const needsBib = suggestion.needs.includes("bib");
  const needsCrossing = suggestion.needs.includes("capture_id");

  async function run(action: () => Promise<string[]>) {
    setBusy(true);
    setError(null);
    try {
      const errors = await action();
      if (errors.length) setError(errors.join("; "));
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
      onChanged(); // refresh even on error: someone else may have handled it (Review Focus 4)
    }
  }

  const onAccept = () =>
    run(async () => {
      const { data } = await accept({ variables: { eventId, key: suggestion.key, bib: needsBib ? bib.trim() : null } });
      return data?.acceptSuggestion.errors ?? [];
    });
  const onDismiss = () =>
    run(async () => {
      const { data } = await dismiss({ variables: { eventId, key: suggestion.key } });
      return data?.dismissSuggestion.errors ?? [];
    });

  return (
    <li data-testid="suggestion">
      <div>{suggestion.message}</div>
      {canAct && (
        <div className="actions">
          {needsBib && <input aria-label="Bib" placeholder="Bib" value={bib} onChange={(e) => setBib(e.target.value)} style={{ width: 70 }} />}
          {!needsCrossing && (
            <button onClick={onAccept} disabled={busy || (needsBib && !bib.trim())}>Accept</button>
          )}
          <button onClick={onDismiss} disabled={busy}>Dismiss</button>
          {needsCrossing && <span className="muted">needs a crossing — not available yet</span>}
        </div>
      )}
      {error && <div className="error">{error}</div>}
    </li>
  );
}
