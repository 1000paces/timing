import BackspaceOutlinedIcon from "@mui/icons-material/BackspaceOutlined";
import Box from "@mui/material/Box";
import Button from "@mui/material/Button";

const KEYS = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "⌫", "0"];

// Big keys for gloves and cold hands; our own, so the phone's keyboard never covers the list.
// compact: shorter keys, for short (landscape) screens.
// fill: stretch the four rows to fill the parent's height (landscape panel).
export function Keypad({ onDigit, onBack, onEnter, enterLabel = "Enter", compact = false, fill = false }: {
  onDigit: (d: string) => void;
  onBack: () => void;
  onEnter?: () => void;
  enterLabel?: string;
  compact?: boolean;
  fill?: boolean;
}) {
  const height = fill ? 40 : compact ? 44 : 56;
  return (
    <Box sx={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 1, ...(fill && { height: "100%", gridTemplateRows: "repeat(4, minmax(0, 1fr))" }) }}>
      {KEYS.map((k) =>
        k === "⌫" ? (
          <Button key={k} variant="outlined" aria-label="Backspace" onClick={onBack} sx={{ minHeight: height, height: fill ? "100%" : undefined }}>
            <BackspaceOutlinedIcon />
          </Button>
        ) : (
          <Button key={k} variant="outlined" onClick={() => onDigit(k)} sx={{ minHeight: height, height: fill ? "100%" : undefined, fontSize: compact || fill ? 22 : 24 }}>
            {k}
          </Button>
        ),
      )}
      {onEnter ? (
        <Button variant="contained" color="success" onPointerDown={(e) => e.preventDefault()} onClick={onEnter} sx={{ minHeight: height, height: fill ? "100%" : undefined, fontSize: 20 }}>
          {enterLabel}
        </Button>
      ) : (
        <span />
      )}
    </Box>
  );
}
