import { useQuery } from "@apollo/client/react";
import Alert from "@mui/material/Alert";
import Container from "@mui/material/Container";
import LinearProgress from "@mui/material/LinearProgress";
import Link from "@mui/material/Link";
import List from "@mui/material/List";
import ListItem from "@mui/material/ListItem";
import Paper from "@mui/material/Paper";
import Typography from "@mui/material/Typography";
import { useEffect } from "react";
import { EVENTS, type EventsData } from "../queries";
import { isSignedOutError } from "../roles";
import { linkTo, startsHref } from "../route";

export function Events({ onSignedOut }: { onSignedOut: () => void }) {
  const { data, error, loading } = useQuery<EventsData>(EVENTS, { fetchPolicy: "network-only" });
  useEffect(() => {
    if (isSignedOutError(error)) onSignedOut();
  }, [error, onSignedOut]);

  return (
    <Container maxWidth="md" sx={{ py: 3 }}>
      <Typography variant="h4" component="h1" gutterBottom>
        Events
      </Typography>
      {loading && <LinearProgress />}
      {error && <Alert severity="error">{error.message}</Alert>}
      {data && (
        <Paper>
          <List>
            {data.events.map((event) => (
              <ListItem key={event.id}>
                <Link {...linkTo(startsHref(event.id))} underline="hover">
                  {event.name} — {event.date}
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
    </Container>
  );
}
