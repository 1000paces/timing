import { useMutation } from "@apollo/client/react";
import Alert from "@mui/material/Alert";
import Button from "@mui/material/Button";
import List from "@mui/material/List";
import ListItem from "@mui/material/ListItem";
import Paper from "@mui/material/Paper";
import Stack from "@mui/material/Stack";
import TextField from "@mui/material/TextField";
import Typography from "@mui/material/Typography";
import { useState } from "react";
import { ACCEPT_SUGGESTION, DISMISS_SUGGESTION, type MutationResult, type Suggestion } from "../queries";

type Props = { eventId: string; suggestions: Suggestion[]; labels: Map<string, string>; canAct: boolean; onChanged: () => void };

export function ReviewQueue({ eventId, suggestions, labels, canAct, onChanged }: Props) {
  return (
    <Paper component="aside" sx={{ p: 2, position: "sticky", top: 16 }}>
      <Typography variant="h6" component="h2">
        Review queue ({suggestions.length})
      </Typography>
      {suggestions.length === 0 && <Typography color="text.secondary">Nothing to review.</Typography>}
      <List disablePadding>
        {suggestions.map((s) => (
          <SuggestionItem key={s.key} eventId={eventId} suggestion={s} label={labels.get(s.key)} canAct={canAct} onChanged={onChanged} />
        ))}
      </List>
    </Paper>
  );
}

function SuggestionItem({ eventId, suggestion, label, canAct, onChanged }: { eventId: string; suggestion: Suggestion; label?: string; canAct: boolean; onChanged: () => void }) {
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
    <ListItem data-testid="suggestion" divider sx={{ display: "block", px: 0 }}>
      <Typography variant="body2">{label ?? suggestion.message}</Typography>
      {canAct && (
        <Stack direction="row" spacing={1} sx={{ mt: 1, alignItems: "center" }}>
          {needsBib && (
            <TextField label="Bib" size="small" value={bib} onChange={(e) => setBib(e.target.value)} sx={{ width: 90 }} />
          )}
          {!needsCrossing && (
            <Button size="small" variant="contained" onClick={onAccept} disabled={busy || (needsBib && !bib.trim())}>
              Accept
            </Button>
          )}
          <Button size="small" onClick={onDismiss} disabled={busy}>
            Dismiss
          </Button>
          {needsCrossing && (
            <Typography variant="caption" color="text.secondary">
              needs a crossing — not available yet
            </Typography>
          )}
        </Stack>
      )}
      {error && <Alert severity="error" sx={{ mt: 1 }}>{error}</Alert>}
    </ListItem>
  );
}
