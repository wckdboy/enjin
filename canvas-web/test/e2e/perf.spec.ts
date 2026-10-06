import { expect, test } from "@playwright/test";

// Plan §8: 300 cards / 20 portals. Headless WebKit on a Mac is not an iPad, so
// these are loose regression guards; the real numbers come from the device.
type Debug = { api: { getAppState(): { scrollX: number; scrollY: number; zoom: { value: number } }; updateScene(u: unknown): void }; portals: { portalId: string | null } };

test("300-card notebook: dive, portal load and panning stay fast", async ({ page }) => {
  await page.goto("/?fixture=big");
  await page.waitForFunction(() => (window as unknown as { __enjinDebug?: Debug }).__enjinDebug?.portals.portalId === "p-root");
  await page.waitForTimeout(300);

  // Dive into each of the 20 portals and back, timing the whole dive.
  const dives: number[] = [];
  for (let i = 0; i < 20; i++) {
    const ms = await page.evaluate(async (i) => {
      const t0 = performance.now();
      const res = await window.enjin!.handle({ v: 1, id: `d${i}`, method: "portal.load", params: { scene: (window as unknown as { __devScene(id: string): unknown }).__devScene(`p-${i}`), transition: "dive" } });
      if ("error" in res) throw new Error(JSON.stringify(res));
      return performance.now() - t0;
    }, i);
    dives.push(ms);
  }
  dives.sort((a, b) => a - b);
  const p50 = dives[10]!;
  const max = dives[19]!;

  // Pan for one second on a 15-card portal and record frame intervals.
  const frames = await page.evaluate(
    () =>
      new Promise<number[]>((resolve) => {
        const { api } = (window as unknown as { __enjinDebug: Debug }).__enjinDebug;
        const start = api.getAppState();
        const out: number[] = [];
        let last = performance.now();
        const t0 = last;
        const step = (now: number) => {
          out.push(now - last);
          last = now;
          api.updateScene({ appState: { scrollX: start.scrollX - (now - t0) * 0.6 } });
          if (now - t0 < 1000) requestAnimationFrame(step);
          else resolve(out.slice(1));
        };
        requestAnimationFrame(step);
      }),
  );
  frames.sort((a, b) => a - b);
  const p95 = frames[Math.floor(frames.length * 0.95)]!;
  console.log(`PERF dive p50=${p50.toFixed(0)}ms max=${max.toFixed(0)}ms (440ms of it is animation); pan frames=${frames.length} p95=${p95.toFixed(1)}ms`);

  // Dive = 180ms fade + 260ms grow + paint; anything far above means render work crept in.
  expect(p50).toBeLessThan(900);
  expect(p95).toBeLessThan(50);
});
