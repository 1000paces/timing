import { useCallback, useEffect, useState } from "react";
import { client } from "./api";
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

  if (official === undefined) return <p className="page muted">Loading…</p>;
  if (official === null) return <SignIn onSignedIn={setOfficial} />;

  return (
    <div>
      <header className="topbar">
        <a href="#/">Events</a>
        <span className="spacer" />
        <span>
          {official.name} ({official.role})
        </span>
        <button onClick={handleSignOut}>Sign out</button>
      </header>
      {route.view === "events" && <Events onSignedOut={signedOut} />}
      {route.view === "event" && (
        <RaceScreen eventId={route.eventId} groupId={route.groupId} official={official} onSignedOut={signedOut} />
      )}
    </div>
  );
}
