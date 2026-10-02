import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

const rails = "http://localhost:3000";

export default defineConfig({
  base: "/console/",
  plugins: [react()],
  // MUI makes one ~700 kB bundle; fine for a console loaded once over the LAN.
  build: { outDir: "../public/console", emptyOutDir: true, chunkSizeWarningLimit: 1000 },
  server: {
    port: 5173,
    proxy: {
      "/session": rails,
      "/graphql": rails,
      "/cable": { target: "ws://localhost:3000", ws: true },
    },
  },
});
