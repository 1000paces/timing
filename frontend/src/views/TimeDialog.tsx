import Button from "@mui/material/Button";
import Dialog from "@mui/material/Dialog";
import DialogActions from "@mui/material/DialogActions";
import DialogContent from "@mui/material/DialogContent";
import DialogTitle from "@mui/material/DialogTitle";
import TextField from "@mui/material/TextField";
import { useState, type ReactNode } from "react";
import { fromLocalInput, toLocalInput } from "../format";

// Pick a time of day (to the second), pre-filled with atMs.
export function TimeDialog({ title, action, atMs, onCancel, onSave, children }: { title: string; action: string; atMs: number; onCancel: () => void; onSave: (atMs: number) => void; children?: ReactNode }) {
  const [value, setValue] = useState(toLocalInput(atMs, { seconds: true }));
  const parsed = fromLocalInput(value);
  return (
    <Dialog open onClose={onCancel}>
      <DialogTitle>{title}</DialogTitle>
      <DialogContent>
        <TextField label="Time" type="datetime-local" value={value} onChange={(e) => setValue(e.target.value)} sx={{ mt: 1 }}
          slotProps={{ inputLabel: { shrink: true }, htmlInput: { step: 1 } }} />
        {children}
      </DialogContent>
      <DialogActions>
        <Button onClick={onCancel}>Cancel</Button>
        <Button variant="contained" disabled={parsed == null} onClick={() => parsed != null && onSave(parsed)}>{action}</Button>
      </DialogActions>
    </Dialog>
  );
}
