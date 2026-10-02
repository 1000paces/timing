import { createTheme } from "@mui/material/styles";

// Light and dark schemes; the console starts dark (see main.tsx) and remembers
// the official's choice in localStorage.
export const theme = createTheme({
  colorSchemes: { light: true, dark: true },
  cssVariables: { colorSchemeSelector: "class" },
});
