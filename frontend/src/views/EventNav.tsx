import Tab from "@mui/material/Tab";
import Tabs from "@mui/material/Tabs";
import Typography from "@mui/material/Typography";
import { linkTo, raceHref, setupHref, startsHref } from "../route";

type Screen = "setup" | "starts" | "race";

// Event title plus the Setup | Starts | Results tabs. Setup is for admins.
export function EventNav({ eventId, eventName, current, admin }: { eventId: string; eventName: string; current: Screen; admin: boolean }) {
  return (
    <>
      <Typography variant="h4" component="h1" gutterBottom>
        {eventName}
      </Typography>
      <Tabs value={current} sx={{ mb: 2 }}>
        {admin && <Tab value="setup" label="Setup" component="a" {...linkTo(setupHref(eventId))} />}
        <Tab value="starts" label="Starts" component="a" {...linkTo(startsHref(eventId))} />
        <Tab value="race" label="Results" component="a" {...linkTo(raceHref(eventId))} />
      </Tabs>
    </>
  );
}
