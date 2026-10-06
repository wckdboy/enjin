import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "test/e2e",
  timeout: 30_000,
  use: { baseURL: "http://localhost:5199", ...devices["iPad Pro 11"], hasTouch: true },
  projects: [{ name: "webkit", use: { browserName: "webkit" } }],
  webServer: { command: "npx vite --port 5199 --strictPort", url: "http://localhost:5199", reuseExistingServer: true },
});
