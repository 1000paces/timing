import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

const rails = "http://localhost:3000";

export default defineConfig({
  base: "/console/",
  plugins: [react()],
  build: { outDir: "../public/console", emptyOutDir: true },
  server: {
    port: 5173,
    proxy: {
      "/session": rails,
      "/graphql": rails,
      "/cable": { target: "ws://localhost:3000", ws: true },
    },
  },
});
