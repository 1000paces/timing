import { useMutation, useQuery } from "@apollo/client/react";
import Alert from "@mui/material/Alert";
import Box from "@mui/material/Box";
import Button from "@mui/material/Button";
import Dialog from "@mui/material/Dialog";
import DialogActions from "@mui/material/DialogActions";
import DialogTitle from "@mui/material/DialogTitle";
import LinearProgress from "@mui/material/LinearProgress";
import List from "@mui/material/List";
import ListItem from "@mui/material/ListItem";
import Paper from "@mui/material/Paper";
import TextField from "@mui/material/TextField";
import Typography from "@mui/material/Typography";
import { useCallback, useState } from "react";
import { formatClock } from "../format";
import { REVERT_RULING, RULINGS, type FixResults, type HistoryEntry } from "../queries";
import { navigate, raceHref } from "../route";
import { useEventChanges } from "../useEventChanges";

const PAGE = 50;

// Every ruling for the event, newest first: who did what, with Undo for chiefs.
export function HistoryList({ eventId, canAct }: { eventId: string; canAct: boolean }) {
  const [search, setSearch] = useState("");
  const [limit, setLimit] = useState(PAGE);
  const history = useQuery<{ rulings: HistoryEntry[] }>(RULINGS, { variables: { eventId, search: search.trim() || null, limit }, fetchPolicy: "cache-and-network" });
  const [revert] = useMutation<FixResults>(REVERT_RULING);
  const [undoing, setUndoing] = useState<HistoryEntry | null>(null);
  const [error, setError] = useState<string | null>(null);
  const { refetch } = history;
  const refresh = useCallback(() => {
    refetch().catch(() => {});
  }, [refetch]);
  useEventChanges(eventId, refresh);

  async function undo(entry: HistoryEntry) {
    setUndoing(null);
    try {
      const errors = (await revert({ variables: { id: entry.id } })).data?.revertRuling?.errors ?? [];
      setError(errors.length ? errors.join("; ") : null);
    } catch (e) {
      setError((e as Error).message);
    }
    refresh();
  }

  const entries = history.data?.rulings ?? [];
  return (
    <Box>
      <TextField size="small" label="Search history" placeholder="Bib or racer" value={search} onChange={(e) => { setSearch(e.target.value); setLimit(PAGE); }} sx={{ mb: 2, width: 260 }} />
      {error && <Alert severity="error" sx={{ mb: 2 }} onClose={() => setError(null)}>{error}</Alert>}
      {!history.data && <LinearProgress />}
      <Paper sx={{ px: 2 }}>
        {history.data && entries.length === 0 && <Typography color="text.secondary" sx={{ py: 2 }}>No fixes yet.</Typography>}
        <List disablePadding>
          {entries.map((e) => (
            <ListItem key={e.id} data-testid="history-entry" divider sx={{ gap: 2, alignItems: "flex-start" }}>
              <Typography sx={{ fontFamily: "monospace", width: 80, flexShrink: 0 }}>{formatClock(e.createdAtMs)}</Typography>
              <Box sx={{ flex: 1, minWidth: 0 }}>
                <Typography sx={{ textDecoration: e.undone ? "line-through" : "none", color: e.undone ? "text.disabled" : "text.primary" }}>{e.description}</Typography>
                <Typography variant="caption" color="text.secondary">
                  {e.officialName ?? "Hub"}
                  {e.undone ? ` · undone by ${e.undoneBy ?? "an official"}${e.undoneAtMs ? ` at ${formatClock(e.undoneAtMs)}` : ""}` : ""}
                </Typography>
              </Box>
              {e.bib && (
                <Button size="small" onClick={() => navigate(`${raceHref(eventId)}?racer=${encodeURIComponent(e.bib!)}`)}>Bib {e.bib}</Button>
              )}
              {canAct && !e.undone && e.kind !== "revert" && <Button size="small" onClick={() => setUndoing(e)}>Undo</Button>}
            </ListItem>
          ))}
        </List>
        {entries.length >= limit && <Button fullWidth onClick={() => setLimit(limit + PAGE)}>Show more</Button>}
      </Paper>
      <Dialog open={undoing != null} onClose={() => setUndoing(null)}>
        <DialogTitle>Undo "{undoing?.description}"?</DialogTitle>
        <DialogActions>
          <Button onClick={() => setUndoing(null)}>Cancel</Button>
          <Button variant="contained" onClick={() => undoing && void undo(undoing)}>Undo</Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}
