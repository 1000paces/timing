import Chip from "@mui/material/Chip";
import Stack from "@mui/material/Stack";
import type { ReactNode } from "react";

// A filter control with its chosen values as chips underneath, so the control
// keeps its size however many values are picked.
export function FilterWithChips({ chips, onDelete, children }: {
  chips: { key: string; label: string }[];
  onDelete: (key: string) => void;
  children: ReactNode;
}) {
  return (
    <Stack spacing={0.5}>
      {children}
      {chips.length > 0 && (
        <Stack direction="row" sx={{ flexWrap: "wrap", gap: 0.75, maxWidth: 260 }}>
          {chips.map((c) => <Chip key={c.key} size="small" label={c.label} onDelete={() => onDelete(c.key)} />)}
        </Stack>
      )}
    </Stack>
  );
}
