import { useState, type FormEvent } from "react";
import { signIn, type Official } from "../session";

export function SignIn({ onSignedIn }: { onSignedIn: (official: Official) => void }) {
  const [name, setName] = useState("");
  const [pin, setPin] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      onSignedIn(await signIn(name.trim(), pin));
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className="signin" onSubmit={submit}>
      <h1>Timing console</h1>
      <label>
        Name
        <input value={name} onChange={(e) => setName(e.target.value)} autoFocus />
      </label>
      <label>
        PIN
        <input type="password" inputMode="numeric" value={pin} onChange={(e) => setPin(e.target.value)} />
      </label>
      <button type="submit" disabled={busy || !name || !pin}>Sign in</button>
      {error && <p className="error">{error}</p>}
    </form>
  );
}
