import BackspaceOutlinedIcon from "@mui/icons-material/BackspaceOutlined";
import Box from "@mui/material/Box";
import Button from "@mui/material/Button";

const KEYS = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "⌫", "0"];

// Big keys for gloves and cold hands; our own, so the phone's keyboard never covers the list.
// compact: shorter keys, for short (landscape) screens.
export function Keypad({ onDigit, onBack, onEnter, enterLabel = "Enter", compact = false }: {
  onDigit: (d: string) => void;
  onBack: () => void;
  onEnter?: () => void;
  enterLabel?: string;
  compact?: boolean;
}) {
  const height = compact ? 44 : 56;
  return (
    <Box sx={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 1 }}>
      {KEYS.map((k) =>
        k === "⌫" ? (
          <Button key={k} variant="outlined" aria-label="Backspace" onClick={onBack} sx={{ minHeight: height }}>
            <BackspaceOutlinedIcon />
          </Button>
        ) : (
          <Button key={k} variant="outlined" onClick={() => onDigit(k)} sx={{ minHeight: height, fontSize: compact ? 20 : 24 }}>
            {k}
          </Button>
        ),
      )}
      {onEnter ? (
        <Button variant="contained" color="success" onPointerDown={(e) => e.preventDefault()} onClick={onEnter} sx={{ minHeight: height, fontSize: 20 }}>
          {enterLabel}
        </Button>
      ) : (
        <span />
      )}
    </Box>
  );
}
