import { useQuery } from "@apollo/client/react";
import Chip from "@mui/material/Chip";
import Stack from "@mui/material/Stack";
import Tab from "@mui/material/Tab";
import Tabs from "@mui/material/Tabs";
import Typography from "@mui/material/Typography";
import { useCallback } from "react";
import { PROBLEM_COUNT } from "../queries";
import { captureHref, linkTo, problemsHref, registrationHref, raceHref, setupHref, startsHref } from "../route";
import { useEventChanges } from "../useEventChanges";

type Screen = "setup" | "registration" | "problems" | "starts" | "capture" | "race";

// Event title plus the Event | Registration | Starts | Capture | Results | Problems
// tabs. Event (setup) is for admins. Problems shows how many there are, from any tab.
export function EventNav({ eventId, eventName, current, admin }: { eventId: string; eventName: string; current: Screen; admin: boolean }) {
  // no-cache: the count shares the standings field with fuller queries; keep it out of their cache entry.
  const count = useQuery<{ standings: { suggestions: { key: string }[] } }>(PROBLEM_COUNT, {
    variables: { eventId },
    fetchPolicy: "no-cache",
    pollInterval: 10_000,
  });
  const { refetch } = count;
  const refresh = useCallback(() => {
    refetch().catch(() => {});
  }, [refetch]);
  useEventChanges(eventId, refresh);
  const problems = count.data?.standings.suggestions.length ?? 0;

  return (
    <>
      <Typography variant="h4" component="h1" gutterBottom>
        {eventName}
      </Typography>
      <Tabs value={current} sx={{ mb: 2 }}>
        {admin && <Tab value="setup" label="Event" component="a" {...linkTo(setupHref(eventId))} />}
        <Tab value="registration" label="Registration" component="a" {...linkTo(registrationHref(eventId))} />
        <Tab value="starts" label="Starts" component="a" {...linkTo(startsHref(eventId))} />
        <Tab value="capture" label="Capture" component="a" {...linkTo(captureHref(eventId))} />
        <Tab value="race" label="Results" component="a" {...linkTo(raceHref(eventId))} />
        <Tab
          value="problems"
          component="a"
          {...linkTo(problemsHref(eventId))}
          label={
            <Stack direction="row" spacing={1} sx={{ alignItems: "center" }}>
              <span>Problems</span>
              {problems > 0 && <Chip size="small" color="warning" label={problems} aria-label={`${problems} problems`} />}
            </Stack>
          }
        />
      </Tabs>
    </>
  );
}
