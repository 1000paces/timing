import Tab from "@mui/material/Tab";
import Tabs from "@mui/material/Tabs";
import Typography from "@mui/material/Typography";
import { captureHref, linkTo, registrationHref, raceHref, setupHref, startsHref } from "../route";

type Screen = "setup" | "registration" | "starts" | "capture" | "race";

// Event title plus the Setup | Registration | Starts | Capture | Results tabs. Setup is for admins.
export function EventNav({ eventId, eventName, current, admin }: { eventId: string; eventName: string; current: Screen; admin: boolean }) {
  return (
    <>
      <Typography variant="h4" component="h1" gutterBottom>
        {eventName}
      </Typography>
      <Tabs value={current} sx={{ mb: 2 }}>
        {admin && <Tab value="setup" label="Setup" component="a" {...linkTo(setupHref(eventId))} />}
        <Tab value="registration" label="Registration" component="a" {...linkTo(registrationHref(eventId))} />
        <Tab value="starts" label="Starts" component="a" {...linkTo(startsHref(eventId))} />
        <Tab value="capture" label="Capture" component="a" {...linkTo(captureHref(eventId))} />
        <Tab value="race" label="Results" component="a" {...linkTo(raceHref(eventId))} />
      </Tabs>
    </>
  );
}
