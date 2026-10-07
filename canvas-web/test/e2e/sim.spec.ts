import { expect, test } from "@playwright/test";

/** Mount the sim runtime in the page and record a value every frame (through a readout formula), for `seconds` of sim time. */
async function run(page: import("@playwright/test").Page, spec: unknown, watch: string, seconds: number) {
  await page.goto("/world.html");
  return page.evaluate(async ({ spec, watch, seconds }) => {
    // Loaded from the dev server, in the page.
    const load = (path: string) => import(/* @vite-ignore */ path);
    const { mountSim } = (await load("/src/live/sim.ts")) as typeof import("../../src/live/sim");
    const { compileExpr } = (await load("/src/live/expr.ts")) as typeof import("../../src/live/expr");
    const root = document.createElement("div");
    root.style.cssText = "position:fixed;left:0;top:0;width:700px;height:420px;z-index:99";
    document.body.appendChild(root);
    const samples: [number, number][] = [];
    const s = { ...(spec as object), readouts: [{ label: "w", expr: watch }] };
    mountSim(root, s, (src: string) => {
      const f = compileExpr(src);
      return (v: Record<string, number>) => { const r = f(v); if (src === watch) samples.push([v.t!, r]); return r; };
    });
    // Wait for simulated time, not wall time: a busy machine runs fewer frames, never different physics.
    const until = performance.now() + 25000;
    while ((samples.at(-1)?.[0] ?? 0) < seconds && performance.now() < until) await new Promise((r) => setTimeout(r, 100));
    return samples;
  }, { spec, watch, seconds });
}

test("a pendulum swings with the period physics says: 2π√(L/g)", async ({ page }) => {
  test.slow();
  const L = 1;
  const samples = await run(page, {
    view: [-1.5, 0, 1.5, 3], floor: false,
    bodies: [{ id: "pivot", r: 0.05, x: 0, y: 2.5, fixed: true }, { id: "bob", r: 0.1, x: 0.1, y: 2.5 - Math.sqrt(L * L - 0.01) }],
    links: [{ type: "rod", a: "pivot", b: "bob" }],
  }, "bob_x", 5);
  // Times the bob crosses the middle going right: one per period.
  const crossings = samples.filter(([, x], i) => i > 0 && samples[i - 1]![1] < 0 && x >= 0).map(([t]) => t);
  expect(crossings.length).toBeGreaterThanOrEqual(2);
  const period = (crossings.at(-1)! - crossings[0]!) / (crossings.length - 1);
  expect(Math.abs(period - 2 * Math.PI * Math.sqrt(L / 9.81)) / 2.006).toBeLessThan(0.03);
});

test("a ball dropped from 5 m lands after √(2h/g) and bounces lower", async ({ page }) => {
  test.slow();
  const samples = await run(page, {
    view: [-2, 0, 2, 6], bodies: [{ id: "ball", r: 0.1, x: 0, y: 5.1, bounce: 0.5 }],
  }, "ball_y", 3);
  // The first bounce: the lowest point before it starts going up again (frames rarely land on the instant of contact).
  const landed = samples.find(([, y], i) => i > 0 && i < samples.length - 1 && y <= samples[i - 1]![1] && y < samples[i + 1]![1]);
  expect(landed).toBeTruthy();
  expect(Math.abs(landed![0] - Math.sqrt((2 * 5) / 9.81))).toBeLessThan(0.04);
  const after = samples.filter(([t]) => t > landed![0] + 0.05).map(([, y]) => y);
  const peak = Math.max(...after);
  expect(peak).toBeGreaterThan(0.8); // bounce 0.5: about a quarter of the height
  expect(peak).toBeLessThan(1.6);
});
