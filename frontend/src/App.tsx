import AppBar from "@mui/material/AppBar";
import Box from "@mui/material/Box";
import Button from "@mui/material/Button";
import CircularProgress from "@mui/material/CircularProgress";
import Link from "@mui/material/Link";
import Toolbar from "@mui/material/Toolbar";
import Typography from "@mui/material/Typography";
import { useCallback, useEffect, useState } from "react";
import { client } from "./api";
import { ColorModeToggle } from "./ColorModeToggle";
import { eventsHref, linkTo, useRoute } from "./route";
import { currentOfficial, signOut, type Official } from "./session";
import { CaptureScreen } from "./views/CaptureScreen";
import { Events } from "./views/Events";
import { ProblemsScreen } from "./views/ProblemsScreen";
import { RaceScreen } from "./views/RaceScreen";
import { RegistrationScreen } from "./views/RegistrationScreen";
import { SetupScreen } from "./views/SetupScreen";
import { SignIn } from "./views/SignIn";
import { StartScreen } from "./views/StartScreen";

export function App() {
  const [official, setOfficial] = useState<Official | null | undefined>(undefined);
  const route = useRoute();

  useEffect(() => {
    currentOfficial().then(setOfficial).catch(() => setOfficial(null));
  }, []);

  const signedOut = useCallback(() => {
    void client.clearStore();
    setOfficial(null);
  }, []);

  async function handleSignOut() {
    await signOut();
    signedOut();
  }

  if (official === undefined) {
    return (
      <Box sx={{ display: "grid", placeItems: "center", minHeight: "100vh" }}>
        <CircularProgress />
      </Box>
    );
  }
  if (official === null) return <SignIn onSignedIn={setOfficial} />;

  return (
    <>
      <AppBar position="static" color="default" elevation={1}>
        <Toolbar variant="dense" sx={{ gap: 2 }}>
          <Link {...linkTo(eventsHref())} color="inherit" underline="hover" variant="h6">
            Events
          </Link>
          <Box sx={{ flex: 1 }} />
          <Typography variant="body2">
            {official.name} ({official.role})
          </Typography>
          <ColorModeToggle />
          <Button color="inherit" onClick={handleSignOut}>
            Sign out
          </Button>
        </Toolbar>
      </AppBar>
      {route.view === "events" && <Events official={official} onSignedOut={signedOut} />}
      {route.view === "starts" && <StartScreen eventId={route.eventId} official={official} onSignedOut={signedOut} />}
      {route.view === "registration" && <RegistrationScreen eventId={route.eventId} official={official} onSignedOut={signedOut} />}
      {route.view === "problems" && <ProblemsScreen eventId={route.eventId} official={official} onSignedOut={signedOut} />}
      {route.view === "capture" && <CaptureScreen eventId={route.eventId} official={official} onSignedOut={signedOut} />}
      {route.view === "setup" && <SetupScreen eventId={route.eventId} official={official} onSignedOut={signedOut} />}
      {route.view === "race" && <RaceScreen eventId={route.eventId} official={official} onSignedOut={signedOut} />}
    </>
  );
}
