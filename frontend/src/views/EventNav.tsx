import Tab from "@mui/material/Tab";
import Tabs from "@mui/material/Tabs";
import Typography from "@mui/material/Typography";
import { linkTo, raceHref, startsHref } from "../route";

// Event title plus the Start | Race screen tabs shown inside an event.
export function EventNav({ eventId, eventName, current }: { eventId: string; eventName: string; current: "starts" | "race" }) {
  return (
    <>
      <Typography variant="h4" component="h1" gutterBottom>
        {eventName}
      </Typography>
      <Tabs value={current} sx={{ mb: 2 }}>
        <Tab value="starts" label="Start" component="a" {...linkTo(startsHref(eventId))} />
        <Tab value="race" label="Race" component="a" {...linkTo(raceHref(eventId))} />
      </Tabs>
    </>
  );
}
