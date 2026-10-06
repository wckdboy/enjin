import { expect, test } from "@playwright/test";

type Debug = { portals: { portalId: string | null; overlay: { fadeOut(ms: number): Promise<void>; el: HTMLCanvasElement | null } } };

/** Mean absolute per-channel difference (0..255) between two same-size canvases. */
const diffScript = () => {
  const d = (window as unknown as { __enjinDebug: Debug }).__enjinDebug;
  const preview = (window as unknown as { __lastPreview?: HTMLCanvasElement }).__lastPreview!;
  const live = document.querySelector("canvas.excalidraw__canvas.static") as HTMLCanvasElement;
  const w = Math.min(preview.width, live.width);
  const h = Math.min(preview.height, live.height);
  const a = preview.getContext("2d")!.getImageData(0, 0, w, h).data;
  const b = live.getContext("2d")!.getImageData(0, 0, w, h).data;
  let sum = 0;
  let n = 0;
  for (let i = 0; i < a.length; i += 16) {
    for (let c = 0; c < 3; c++) sum += Math.abs(a[i + c]! - b[i + c]!);
    n += 3;
  }
  return { mean: sum / n, sizes: [preview.width, preview.height, live.width, live.height], portal: d.portals.portalId };
};

test("dive is seamless: the last preview frame matches the live portal", async ({ page }) => {
  await page.goto("/");
  await page.waitForFunction(() => (window as unknown as { __enjinDebug?: Debug }).__enjinDebug?.portals.portalId === "p-root");
  await page.waitForTimeout(300);
  // Same chrome insets as the app (rail, top bar, dock), so framing is off-center.
  await page.evaluate(() => window.enjin!.handle({ v: 1, id: "i", method: "canvas.setInsets", params: { top: 80, left: 100, bottom: 150, right: 24 } }));
  await page.waitForTimeout(100);
  // Keep the final preview around so we can compare it with what Excalidraw draws.
  await page.evaluate(() => {
    const o = (window as unknown as { __enjinDebug: Debug }).__enjinDebug.portals.overlay;
    o.fadeOut = async () => {
      (window as unknown as { __lastPreview?: HTMLCanvasElement }).__lastPreview = o.el!;
    };
  });

  const shots: Buffer[] = [];
  const dive = page.evaluate(() => (window as unknown as { __enjinDebug: { portals: { requestDive(id: string): Promise<void> } } }).__enjinDebug.portals.requestDive("c-legions"));
  for (let i = 0; i < 6; i++) {
    shots.push(await page.screenshot({ path: `test-results/dive-${i}.png` }));
    await page.waitForTimeout(90);
  }
  await dive;
  await page.waitForTimeout(150);
  const r = await page.evaluate(diffScript);
  console.log("SEAM", JSON.stringify(r));
  expect(r.portal).toBe("p-legions");
  expect(r.sizes[0]).toBe(r.sizes[2]);
  expect(r.mean).toBeLessThan(4);
  await page.screenshot({ path: "test-results/dive-end.png" });
});

test("exit pulls back out through the card", async ({ page }) => {
  await page.goto("/");
  await page.waitForFunction(() => (window as unknown as { __enjinDebug?: Debug }).__enjinDebug?.portals.portalId === "p-root");
  await page.waitForTimeout(300);
  const ctl = () => (window as unknown as { __enjinDebug: { portals: { requestDive(id: string): Promise<void>; requestExit(): Promise<void> } } }).__enjinDebug.portals;
  await page.evaluate((f) => (eval(f) as typeof ctl)().requestDive("c-legions"), `(${ctl.toString()})`);
  await page.waitForTimeout(200);
  await page.screenshot({ path: "test-results/exit-0.png" });
  const exit = page.evaluate((f) => (eval(f) as typeof ctl)().requestExit(), `(${ctl.toString()})`);
  for (let i = 1; i < 6; i++) {
    await page.waitForTimeout(80);
    await page.screenshot({ path: `test-results/exit-${i}.png` });
  }
  await exit;
  expect(await page.evaluate(() => (window as unknown as { __enjinDebug: Debug }).__enjinDebug.portals.portalId)).toBe("p-root");
  expect(await page.locator("[data-enjin=preview-overlay] canvas").count()).toBe(0);
});
