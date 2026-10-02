import Alert from "@mui/material/Alert";
import Box from "@mui/material/Box";
import Button from "@mui/material/Button";
import Paper from "@mui/material/Paper";
import Stack from "@mui/material/Stack";
import TextField from "@mui/material/TextField";
import Typography from "@mui/material/Typography";
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
    <Box sx={{ display: "grid", placeItems: "center", minHeight: "100vh" }}>
      <Paper component="form" onSubmit={submit} sx={{ p: 4, width: 320 }}>
        <Stack spacing={2}>
          <Typography variant="h5" component="h1">
            Timing console
          </Typography>
          <TextField label="Name" value={name} onChange={(e) => setName(e.target.value)} autoFocus />
          <TextField
            label="PIN"
            type="password"
            value={pin}
            onChange={(e) => setPin(e.target.value)}
            slotProps={{ htmlInput: { inputMode: "numeric" } }}
          />
          <Button type="submit" variant="contained" disabled={busy || !name || !pin}>
            Sign in
          </Button>
          {error && <Alert severity="error">{error}</Alert>}
        </Stack>
      </Paper>
    </Box>
  );
}
