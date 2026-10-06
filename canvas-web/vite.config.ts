import react from "@vitejs/plugin-react";
import { cpSync, existsSync } from "node:fs";
import { defineConfig } from "vite";

// Excalidraw fetches fonts from EXCALIDRAW_ASSET_PATH at runtime; ship them in the bundle.
const fontsSrc = "node_modules/@excalidraw/excalidraw/dist/prod/fonts";
if (!existsSync("public/fonts")) cpSync(fontsSrc, "public/fonts", { recursive: true });

export default defineConfig({
  plugins: [react()],
  base: "./",
  define: { "process.env.IS_PREACT": JSON.stringify("false") },
  build: {
    outDir: "../App/Resources/canvas-web",
    emptyOutDir: true,
    chunkSizeWarningLimit: 5000,
  },
  server: { fs: { allow: [".."] } },
});
