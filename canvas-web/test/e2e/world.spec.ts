import { expect, test, type Page } from "@playwright/test";

type World = {
  cam: { s: number };
  anchor: { portalId: string; scene: { title: string }; children: Map<string, unknown>; spec: { doors: { id: string }[]; panels: { id: string; title: string }[] } } | null;
  transitioning: boolean;
  flyThrough(id: string): void;
  zoomBy(f: number): Promise<void>;
  focusPanel(id: string): void;
};
const w = (page: Page) => page.evaluate(() => {
  const x = (window as unknown as { __enjinWorld: World }).__enjinWorld;
  return { portal: x.anchor?.portalId, title: x.anchor?.scene.title, s: x.cam.s, peeked: [...(x.anchor?.children.keys() ?? [])], busy: x.transitioning };
});
const calls = (page: Page, method: string) =>
  page.evaluate((m) => (window as unknown as { __devLog: { method: string; params: Record<string, unknown> }[] }).__devLog.filter((r) => r.method === m).map((r) => r.params), method);
const zoom = async (page: Page, f: number, times: number) => {
  for (let i = 0; i < times; i++) {
    await page.evaluate((k) => (window as unknown as { __enjinWorld: World }).__enjinWorld.zoomBy(k), f);
    await page.waitForTimeout(150);
  }
};

test.beforeEach(async ({ page }) => {
  await page.goto("/world.html?fixture=motors");
  await page.waitForFunction(() => (window as unknown as { __enjinWorld?: World }).__enjinWorld?.anchor?.portalId === "p-root");
});

test("doors show the world inside them, and flying into one goes through", async ({ page }) => {
  // Topics that have been explored are peeked (no side effects) and drawn inside their door.
  await expect.poll(async () => (await w(page)).peeked.sort()).toEqual(["c-everywhere", "c-how"]);
  expect((await calls(page, "portal.enter")).length).toBe(0);
  await page.evaluate(() => (window as unknown as { __enjinWorld: World }).__enjinWorld.flyThrough("c-how"));
  await expect.poll(async () => (await w(page)).portal, { timeout: 5000 }).toBe("p-how");
  expect(await calls(page, "portal.enter")).toEqual([{ portalId: "p-root", cardId: "c-how" }]);
});

test("pulling back far enough rises to the world around", async ({ page }) => {
  await page.evaluate(() => (window as unknown as { __enjinWorld: World }).__enjinWorld.flyThrough("c-how"));
  await expect.poll(async () => (await w(page)).portal, { timeout: 5000 }).toBe("p-how");
  await expect.poll(async () => (await w(page)).busy).toBe(false);
  await page.waitForTimeout(1000);
  await zoom(page, 0.6, 5);
  await expect.poll(async () => (await w(page)).portal, { timeout: 5000 }).toBe("p-root");
  expect(await calls(page, "portal.exit")).toEqual([{ portalId: "p-how" }]);
});

test("zoom into a part of the model and you go inside it: it becomes a topic of its own", async ({ page }) => {
  await page.evaluate(() => (window as unknown as { __enjinWorld: World }).__enjinWorld.flyThrough("c-how"));
  await expect.poll(async () => (await w(page)).portal, { timeout: 5000 }).toBe("p-how");
  await page.waitForTimeout(1200);
  await zoom(page, 1.6, 8);
  await expect.poll(async () => (await calls(page, "portal.zoomInto")).length, { timeout: 5000 }).toBe(1);
  const [req] = await calls(page, "portal.zoomInto");
  expect(req!.portalId).toBe("p-how");
  await expect.poll(async () => (await w(page)).title).toBe(req!.title);
});

test("zoom into a panel and you go inside it", async ({ page }) => {
  const id = await page.evaluate(() => (window as unknown as { __enjinWorld: World }).__enjinWorld.anchor!.spec.panels[0]!.id);
  await page.evaluate((c) => (window as unknown as { __enjinWorld: World }).__enjinWorld.focusPanel(c), id);
  await page.waitForTimeout(800);
  await zoom(page, 1.5, 6);
  await expect.poll(async () => (await calls(page, "portal.zoomInto")).length, { timeout: 5000 }).toBe(1);
  expect((await calls(page, "portal.zoomInto"))[0]!.cardId).toBe(id);
});

test("two fingers pinch to zoom; one finger pans", async ({ page }) => {
  const host = page.locator("#world");
  const before = await w(page);
  const ev = (type: string, id: number, x: number, y: number) =>
    host.dispatchEvent(type, { pointerId: id, clientX: x, clientY: y, isPrimary: id === 1, pointerType: "touch", bubbles: true });
  await ev("pointerdown", 1, 600, 500);
  await ev("pointerdown", 2, 700, 500);
  for (let i = 1; i <= 5; i++) { await ev("pointermove", 1, 600 - i * 20, 500); await ev("pointermove", 2, 700 + i * 20, 500); }
  await ev("pointerup", 1, 500, 500);
  await ev("pointerup", 2, 800, 500);
  const after = await w(page);
  expect(after.s / before.s).toBeGreaterThan(2.5);
  const tx = await page.evaluate(() => (window as unknown as { __enjinWorld: { cam: { tx: number } } }).__enjinWorld.cam.tx);
  await ev("pointerdown", 1, 300, 300);
  for (let i = 1; i <= 5; i++) await ev("pointermove", 1, 300 + i * 30, 300);
  await ev("pointerup", 1, 450, 300);
  const tx2 = await page.evaluate(() => (window as unknown as { __enjinWorld: { cam: { tx: number } } }).__enjinWorld.cam.tx);
  expect(tx2 - tx).toBeGreaterThan(100);
});

test("a new world being written never freezes: doors and panels stream in while you pan", async ({ page }) => {
  // A topic with nothing inside yet: Enjin fills it while you watch.
  await page.evaluate(() => (window as unknown as { __enjinWorld: World }).__enjinWorld.flyThrough("c-homemade"));
  await expect.poll(async () => (await w(page)).portal, { timeout: 5000 }).toBe("p-c-homemade");
  const portal = (await w(page)).portal!;
  // Stream like the agent does: new doors and growing panels, many times a second.
  await page.evaluate((portalId) => new Promise<void>((done) => {
    let i = 0;
    const t = setInterval(() => {
      i++;
      const ops = Array.from({ length: 1 + Math.floor(i / 2) }, (_, n) => ({
        op: "upsert",
        card: { id: `s${n}`, type: n % 2 ? "topic" : "note", title: `Thing ${n}`, summary: "word ".repeat(Math.min(40, i)), state: "filling", childCount: 0 },
      }));
      (window as unknown as { enjin: { handle(r: unknown): void } }).enjin.handle({ v: 1, id: `s${i}`, method: "canvas.applyOps", params: { portalId, ops } });
      if (i >= 24) { clearInterval(t); done(); }
    }, 170); // about the pace of the agent's partial previews
  }), portal);
  // Still alive: a pan moves what's drawn on screen (not just the camera), and the cards (doors included) arrived.
  const tx = () => page.evaluate(() => {
    const m = /translate\((-?[\d.]+)px/.exec((window as unknown as { __enjinWorld: { anchor: { el: HTMLElement } } }).__enjinWorld.anchor.el.style.transform);
    return Number(m?.[1] ?? NaN);
  });
  await page.waitForTimeout(400);
  const before = await tx();
  const host = page.locator("#world");
  const ev = (type: string, x: number) => host.dispatchEvent(type, { pointerId: 1, clientX: x, clientY: 400, isPrimary: true, pointerType: "touch", bubbles: true });
  await ev("pointerdown", 300);
  for (let i = 1; i <= 4; i++) await ev("pointermove", 300 + i * 40);
  await ev("pointerup", 460);
  await page.waitForTimeout(200);
  expect(Math.abs((await tx()) - before)).toBeGreaterThan(100);
  await expect.poll(() => page.evaluate(() => (window as unknown as { __enjinWorld: World }).__enjinWorld.anchor!.spec.doors.length)).toBeGreaterThan(3);
  const errors = await page.evaluate(() => (window as unknown as { __devLog: { method: string; params: { level?: string; message?: string } }[] }).__devLog
    .filter((r) => r.method === "log.event" && r.params.level === "error" && /world/.test(r.params.message ?? "")));
  expect(errors).toEqual([]);
});

test("an error in one frame never freezes the world", async ({ page }) => {
  const drawn = () => page.evaluate(() => (window as unknown as { __enjinWorld: { anchor: { el: HTMLElement } } }).__enjinWorld.anchor.el.style.transform);
  // Something goes wrong while drawing (say, a half-written model): once.
  await page.evaluate(() => {
    const m = (window as unknown as { __enjinWorld: { anchor: { model: { update(t: number): boolean } } } }).__enjinWorld.anchor.model;
    const real = m.update.bind(m);
    let thrown = false;
    m.update = (t: number) => { if (!thrown) { thrown = true; throw new Error("boom"); } return real(t); };
  });
  await page.waitForTimeout(300);
  const before = await drawn();
  await page.evaluate(() => (window as unknown as { __enjinWorld: World }).__enjinWorld.zoomBy(1.3));
  await page.waitForTimeout(700);
  expect(await drawn()).not.toBe(before);
});
