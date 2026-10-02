import { useMutation, useQuery } from "@apollo/client/react";
import Alert from "@mui/material/Alert";
import Button from "@mui/material/Button";
import Container from "@mui/material/Container";
import Dialog from "@mui/material/Dialog";
import DialogActions from "@mui/material/DialogActions";
import DialogContent from "@mui/material/DialogContent";
import DialogTitle from "@mui/material/DialogTitle";
import LinearProgress from "@mui/material/LinearProgress";
import Link from "@mui/material/Link";
import List from "@mui/material/List";
import ListItem from "@mui/material/ListItem";
import Paper from "@mui/material/Paper";
import Stack from "@mui/material/Stack";
import Typography from "@mui/material/Typography";
import { useEffect, useState } from "react";
import { CREATE_EVENT, DISCIPLINES, EVENTS, type DisciplinesData, type EventInput, type EventsData, type MutationResult } from "../queries";
import { isSignedOutError } from "../roles";
import { linkTo, navigate, setupHref, startsHref } from "../route";
import type { Official } from "../session";
import { EventFields } from "./EventFields";

export function Events({ official, onSignedOut }: { official: Official; onSignedOut: () => void }) {
  const { data, error, loading } = useQuery<EventsData>(EVENTS, { fetchPolicy: "network-only" });
  const [creating, setCreating] = useState(false);
  useEffect(() => {
    if (isSignedOutError(error)) onSignedOut();
  }, [error, onSignedOut]);

  return (
    <Container maxWidth="md" sx={{ py: 3 }}>
      <Stack direction="row" sx={{ alignItems: "center", mb: 2 }}>
        <Typography variant="h4" component="h1" sx={{ flex: 1 }}>
          Events
        </Typography>
        {official.role === "admin" && (
          <Button variant="contained" onClick={() => setCreating(true)}>
            New event
          </Button>
        )}
      </Stack>
      {loading && <LinearProgress />}
      {error && <Alert severity="error">{error.message}</Alert>}
      {data && (
        <Paper>
          <List>
            {data.events.map((event) => (
              <ListItem key={event.id}>
                <Link {...linkTo(startsHref(event.id))} underline="hover">
                  {event.name} — {event.date}
                  {event.location ? ` — ${event.location}` : ""}
                </Link>
              </ListItem>
            ))}
            {data.events.length === 0 && (
              <ListItem>
                <Typography color="text.secondary">No events yet.</Typography>
              </ListItem>
            )}
          </List>
        </Paper>
      )}
      {creating && <NewEventDialog onClose={() => setCreating(false)} />}
    </Container>
  );
}

function NewEventDialog({ onClose }: { onClose: () => void }) {
  const disciplines = useQuery<DisciplinesData>(DISCIPLINES);
  const [createEvent, { loading }] = useMutation<{ createEvent: MutationResult & { event: { id: string } | null } }>(CREATE_EVENT);
  const [value, setValue] = useState<EventInput | null>(null);
  const [errors, setErrors] = useState<string[]>([]);

  const list = disciplines.data?.disciplines;
  useEffect(() => {
    if (list && !value) {
      const first = list[0];
      setValue({ name: "", date: new Date().toISOString().slice(0, 10), location: null, discipline: first.id, subDiscipline: null, finishWithLeader: first.finishWithLeader });
    }
  }, [list, value]);

  async function create() {
    if (!value) return;
    try {
      const { data } = await createEvent({ variables: value });
      const result = data?.createEvent;
      if (result?.event) navigate(setupHref(result.event.id));
      else setErrors(result?.errors ?? ["Couldn't create the event"]);
    } catch (e) {
      setErrors([(e as Error).message]);
    }
  }

  return (
    <Dialog open onClose={onClose} fullWidth maxWidth="xs">
      <DialogTitle>New event</DialogTitle>
      <DialogContent>
        {errors.map((e) => (
          <Alert key={e} severity="error" sx={{ mb: 1 }}>{e}</Alert>
        ))}
        {value && list ? <EventFields value={value} onChange={setValue} disciplines={list} /> : <LinearProgress />}
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>Cancel</Button>
        <Button variant="contained" onClick={create} disabled={!value || loading}>Create</Button>
      </DialogActions>
    </Dialog>
  );
}
