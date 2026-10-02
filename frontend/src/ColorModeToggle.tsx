import DarkModeIcon from "@mui/icons-material/DarkMode";
import LightModeIcon from "@mui/icons-material/LightMode";
import IconButton from "@mui/material/IconButton";
import { useColorScheme } from "@mui/material/styles";

export function ColorModeToggle() {
  const { mode, setMode } = useColorScheme();
  if (!mode) return null;
  const dark = mode !== "light";
  return (
    <IconButton color="inherit" aria-label={dark ? "Switch to light mode" : "Switch to dark mode"} onClick={() => setMode(dark ? "light" : "dark")}>
      {dark ? <LightModeIcon /> : <DarkModeIcon />}
    </IconButton>
  );
}
