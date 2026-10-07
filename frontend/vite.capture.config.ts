import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";
import { VitePWA } from "vite-plugin-pwa";

// The phone capture app: served by the hub at /capture-app/, works offline once loaded.
export default defineConfig({
  root: "capture",
  base: "/capture-app/",
  plugins: [
    react(),
    VitePWA({
      registerType: "autoUpdate",
      injectRegister: false, // registered from main.tsx
      manifest: {
        name: "Timing Capture",
        short_name: "Capture",
        start_url: "/capture-app/",
        scope: "/capture-app/",
        display: "standalone",
        background_color: "#121212",
        theme_color: "#121212",
        icons: [{ src: "icon.svg", sizes: "any", type: "image/svg+xml", purpose: "any" }],
      },
      workbox: { globPatterns: ["**/*.{js,css,html,svg}"], navigateFallback: "/capture-app/index.html", maximumFileSizeToCacheInBytes: 3_000_000 },
    }),
  ],
  build: { outDir: "../../public/capture-app", emptyOutDir: true, chunkSizeWarningLimit: 1000 },
  server: { port: 5174 },
});
