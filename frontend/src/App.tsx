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
import { useRoute } from "./route";
import { currentOfficial, signOut, type Official } from "./session";
import { Events } from "./views/Events";
import { RaceScreen } from "./views/RaceScreen";
import { SignIn } from "./views/SignIn";

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
          <Link href="#/" color="inherit" underline="hover" variant="h6">
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
      {route.view === "events" && <Events onSignedOut={signedOut} />}
      {route.view === "event" && (
        <RaceScreen eventId={route.eventId} groupId={route.groupId} official={official} onSignedOut={signedOut} />
      )}
    </>
  );
}
