import { expect, test, type Page } from "@playwright/test";

// Live models are model-written code: they must run, but in a box.

async function ready(page: Page) {
  await page.goto("/");
  await page.waitForFunction(() => (window as unknown as { __enjinDebug?: { portals: { portalId: string | null } } }).__enjinDebug?.portals.portalId === "p-root");
  await page.waitForTimeout(400);
}

const call = (page: Page, method: string, params: unknown) =>
  page.evaluate(([method, params]) => window.enjin!.handle({ v: 1, id: "t", method, params }), [method, params] as const);

const PROBE = `<canvas id="c"></canvas><script>
const r = {};
try { parent.document.title = "pwned"; r.parent = "open"; } catch (e) { r.parent = "blocked"; }
try { localStorage.setItem("k", "v"); r.storage = "open"; } catch (e) { r.storage = "blocked"; }
fetch("https://example.com/").then(() => { r.net = "open"; }, () => { r.net = "blocked"; })
  .finally(() => parent.postMessage({ live: r }, "*"));
</script>`;

test("a live model runs sandboxed: no parent access, no storage, no network", async ({ page }) => {
  await ready(page);
  const report = page.evaluate(
    () => new Promise<Record<string, string>>((resolve) => addEventListener("message", (e) => e.data?.live && resolve(e.data.live))),
  );
  await call(page, "canvas.applyOps", {
    portalId: "p-root",
    ops: [{ op: "upsert", card: { id: "c-live", type: "note", title: "Probe", summary: "", state: "filled", childCount: 0, visual: { kind: "live", html: PROBE } } }],
  });
  expect(await report).toEqual({ parent: "blocked", storage: "blocked", net: "blocked" });
  expect(await page.title()).not.toBe("pwned");
  const iframe = page.locator('[data-enjin="live"] iframe[data-card-id="c-live"]');
  await expect(iframe).toHaveAttribute("sandbox", "allow-scripts");
});

test("a live model takes touches only while its card is selected, and waits for complete html", async ({ page }) => {
  await ready(page);
  // Still being written: a slot that says so, no frame yet.
  await call(page, "canvas.applyOps", {
    portalId: "p-root",
    ops: [{ op: "upsert", card: { id: "c-live", type: "note", title: "Pendulum", summary: "", state: "filling", childCount: 0, visual: { kind: "live" } } }],
  });
  const iframe = page.locator('[data-enjin="live"] iframe[data-card-id="c-live"]');
  await expect(iframe).toHaveCount(0);
  await call(page, "canvas.applyOps", {
    portalId: "p-root",
    ops: [{ op: "upsert", card: { id: "c-live", type: "note", title: "Pendulum", summary: "", state: "filled", childCount: 0, visual: { kind: "live", html: "<p>tick</p>" } } }],
  });
  await expect(iframe).toHaveCount(1);
  await expect(iframe).toHaveCSS("pointer-events", "none");

  // Tap the card (on its title, above the model) to select it.
  const p = await page.evaluate(() => {
    const { api } = (window as unknown as { __enjinDebug: { api: { getSceneElements(): { x: number; y: number; width: number; customData?: Record<string, string> }[]; getAppState(): { scrollX: number; scrollY: number; zoom: { value: number } } } } }).__enjinDebug;
    const f = api.getSceneElements().find((e) => e.customData?.cardId === "c-live" && e.customData?.role === "frame")!;
    const s = api.getAppState();
    return { x: (f.x + f.width / 2 + s.scrollX) * s.zoom.value, y: (f.y + 20 + s.scrollY) * s.zoom.value };
  });
  await page.touchscreen.tap(p.x, p.y);
  await expect(iframe).toHaveCSS("pointer-events", "auto");
});
