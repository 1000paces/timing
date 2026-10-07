import Chip from "@mui/material/Chip";
import Stack from "@mui/material/Stack";
import Typography from "@mui/material/Typography";
import { PROBLEM_TYPE, problemType } from "../problems";
import type { Suggestion } from "../queries";

// A problem's type chip, race and racer, shown above its message.
export function ProblemMeta({ suggestion, raceName, racerName }: { suggestion: Suggestion; raceName?: string; racerName?: string | null }) {
  const type = PROBLEM_TYPE[problemType(suggestion)];
  const where = [raceName ?? (suggestion.raceId ? null : "No race"), suggestion.bib && `Bib ${suggestion.bib}${racerName ? ` · ${racerName}` : ""}`];
  return (
    <Stack direction="row" spacing={1} sx={{ alignItems: "center", mb: 0.5 }}>
      <Chip data-testid="problem-type" size="small" color={type.color} label={type.label} />
      <Typography variant="body2" color="text.secondary">{where.filter(Boolean).join(" · ")}</Typography>
    </Stack>
  );
}
