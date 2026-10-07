import CssBaseline from "@mui/material/CssBaseline";
import { ThemeProvider } from "@mui/material/styles";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { theme } from "../../src/theme";
import { App } from "./App";

// The offline app shell (service worker) — production builds only. When a new
// version of the app takes over (after an update on the hub), reload once so the
// screen isn't left on the old cached copy. Nothing on the phone is lost: the
// log lives in IndexedDB, not in the page.
if ("serviceWorker" in navigator && import.meta.env.PROD) {
  const hadController = !!navigator.serviceWorker.controller;
  let reloaded = false;
  navigator.serviceWorker.addEventListener("controllerchange", () => {
    if (!hadController || reloaded) return; // first install: the page is already current
    reloaded = true;
    window.location.reload();
  });
  void navigator.serviceWorker.register("/capture-app/sw.js", { scope: "/capture-app/" }).then((r) => r.update()).catch(() => {});
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <ThemeProvider theme={theme} defaultMode="dark">
      <CssBaseline />
      <App />
    </ThemeProvider>
  </StrictMode>,
);
