import { expect, test, type Page } from "@playwright/test";

type Debug = {
  api: {
    getSceneElements(): { id: string; type: string; x: number; y: number; text?: string; customData?: Record<string, string> }[];
    getAppState(): { scrollX: number; scrollY: number; zoom: { value: number }; width: number; height: number };
    updateScene(u: unknown): void;
  };
  portals: { portalId: string | null };
};

// Any uncaught page error fails the test that caused it.
let pageErrors: string[] = [];
test.beforeEach(({ page }) => {
  pageErrors = [];
  page.on("pageerror", (e) => pageErrors.push(e.message));
});
test.afterEach(() => {
  expect(pageErrors, "uncaught page errors").toEqual([]);
});

async function ready(page: Page) {
  await page.goto("/");
  await page.waitForFunction(() => (window as unknown as { __enjinDebug?: Debug }).__enjinDebug?.portals.portalId === "p-root");
  await page.waitForTimeout(400); // jump transition
}

const portalId = (page: Page) => page.evaluate(() => (window as unknown as { __enjinDebug: Debug }).__enjinDebug.portals.portalId);

/** View-space center of a card's frame. */
async function cardCenter(page: Page, cardId: string) {
  return page.evaluate((cardId) => {
    const { api } = (window as unknown as { __enjinDebug: Debug }).__enjinDebug;
    const f = api.getSceneElements().find((e) => e.customData?.cardId === cardId && e.customData?.role === "frame") as unknown as {
      x: number; y: number; width: number; height: number;
    };
    const s = api.getAppState();
    return { x: (f.x + f.width / 2 + s.scrollX) * s.zoom.value, y: (f.y + f.height / 2 + s.scrollY) * s.zoom.value };
  }, cardId);
}

async function doubleTap(page: Page, p: { x: number; y: number }) {
  await page.touchscreen.tap(p.x, p.y);
  await page.touchscreen.tap(p.x, p.y);
}

const call = (page: Page, method: string, params: unknown) =>
  page.evaluate(([method, params]) => window.enjin!.handle({ v: 1, id: "t", method, params }), [method, params] as const);

const frames = (page: Page) =>
  page.evaluate(() =>
    (window as unknown as { __enjinDebug: Debug }).__enjinDebug.api
      .getSceneElements()
      .filter((e) => e.customData?.role === "frame")
      .map((e) => {
        const f = e as unknown as { x: number; y: number; width: number; height: number; locked: boolean };
        return { cardId: e.customData!.cardId!, x: f.x, y: f.y, width: f.width, height: f.height, locked: f.locked };
      }),
  );

test("handshake then root portal renders its cards", async ({ page }) => {
  await ready(page);
  const log = await page.evaluate(() => (window as unknown as { __devLog: { method: string; params: { protocolVersion?: number } }[] }).__devLog);
  expect(log[0]).toMatchObject({ method: "canvas.ready", params: { protocolVersion: 1 } });
  const frames = await page.evaluate(() =>
    (window as unknown as { __enjinDebug: Debug }).__enjinDebug.api.getSceneElements().filter((e) => e.customData?.role === "frame").map((e) => e.customData!.cardId),
  );
  expect(frames.sort()).toEqual(["c-emperors", "c-fall", "c-legions", "c-roads"]);
  await page.screenshot({ path: "test-results/root.png" });
});

test("double-tap dives through three levels, zoom-out exits", async ({ page }) => {
  await ready(page);
  for (const [card, portal] of [["c-legions", "p-legions"], ["c-why-won", "p-why-won"], ["c-logistics", "p-logistics"]] as const) {
    await doubleTap(page, await cardCenter(page, card));
    await expect.poll(() => portalId(page)).toBe(portal);
    await page.waitForTimeout(350);
  }
  await page.screenshot({ path: "test-results/depth3.png" });

  // Pinch-out equivalent: drop the zoom well below the fitted zoom.
  await page.evaluate(() => {
    const { api } = (window as unknown as { __enjinDebug: Debug }).__enjinDebug;
    const s = api.getAppState();
    api.updateScene({ appState: { zoom: { value: s.zoom.value * 0.3 } } });
  });
  await expect.poll(() => portalId(page)).toBe("p-why-won");
});

test("ink.commit lands where the pencil drew, at any zoom", async ({ page }) => {
  await ready(page);
  await page.evaluate(() => {
    const { api } = (window as unknown as { __enjinDebug: Debug }).__enjinDebug;
    api.updateScene({ appState: { zoom: { value: 2 }, scrollX: -50, scrollY: 30 } });
  });
  const res = await page.evaluate(() =>
    window.enjin!.handle({
      v: 1, id: "t1", method: "ink.commit",
      params: { strokeId: "s1", tool: "pen", color: "#1e1e1e", width: 4, points: [[100, 100], [200, 150], [260, 120]], pressures: [0.5, 0.6, 0.4] },
    }),
  );
  expect(res).toMatchObject({ id: "t1", result: { strokeId: "s1" } });
  const el = await page.evaluate(() =>
    (window as unknown as { __enjinDebug: Debug }).__enjinDebug.api.getSceneElements().find((e) => e.type === "freedraw") as unknown as {
      x: number; y: number; points: [number, number][];
    },
  );
  // view = (scene + scroll) * zoom  =>  scene = view / zoom - scroll
  expect(el.x).toBeCloseTo(100 / 2 + 50, 3);
  expect(el.y).toBeCloseTo(100 / 2 - 30, 3);
  expect(el.points[1]).toEqual([50, 25]);
});

test("bridge rejects unknown methods and wrong versions with clean errors", async ({ page }) => {
  await ready(page);
  const unknown = await page.evaluate(() => window.enjin!.handle({ v: 1, id: "x", method: "nope", params: {} }));
  expect(unknown).toMatchObject({ id: "x", error: { code: -32601 } });
  const version = await page.evaluate(() => window.enjin!.handle({ v: 99, id: "y", method: "canvas.flash", params: { cardId: "c" } }));
  expect(version).toMatchObject({ id: "y", error: { code: -32000 } });
  const bad = await page.evaluate(() => window.enjin!.handle({ v: 1, id: "z", method: "ink.commit", params: { strokeId: 3 } }));
  expect(bad).toMatchObject({ id: "z", error: { code: -32602 } });
});

test("ink.lock blocks finger panning", async ({ page }) => {
  await ready(page);
  // Mobile WebKit has no mouse wheel; dispatch the event Excalidraw pans on.
  const wheel = () =>
    page.evaluate(() =>
      document.querySelector("canvas.interactive")!.dispatchEvent(new WheelEvent("wheel", { deltaX: 300, bubbles: true, cancelable: true })),
    );
  const scroll = () => page.evaluate(() => (window as unknown as { __enjinDebug: Debug }).__enjinDebug.api.getAppState().scrollX);
  await page.evaluate(() => window.enjin!.handle({ v: 1, id: "l", method: "ink.lock", params: { locked: true } }));
  const before = await scroll();
  await wheel();
  await page.waitForTimeout(100);
  expect(await scroll()).toBe(before);
  await page.evaluate(() => window.enjin!.handle({ v: 1, id: "u", method: "ink.lock", params: { locked: false } }));
  await wheel();
  await expect.poll(scroll).not.toBe(before);
});

test("changes made just before a dive are saved to the portal they belong to", async ({ page }) => {
  await ready(page);
  await page.evaluate(() =>
    window.enjin!.handle({ v: 1, id: "i", method: "ink.commit", params: { strokeId: "q", tool: "pen", color: "#000", width: 3, points: [[300, 900], [400, 950]], pressures: [] } }),
  );
  await doubleTap(page, await cardCenter(page, "c-legions")); // well inside the 500ms debounce
  await expect.poll(() => portalId(page)).toBe("p-legions");
  const saved = await page.evaluate(() =>
    (window as unknown as { __devLog: { method: string; params: { portalId: string; elements: { type: string }[] } }[] }).__devLog
      .filter((r) => r.method === "canvas.changed")
      .map((r) => ({ portalId: r.params.portalId, ink: r.params.elements.filter((e) => e.type === "freedraw").length })),
  );
  expect(saved).toContainEqual({ portalId: "p-root", ink: 1 });
});

test("pencil pointer events never reach Excalidraw", async ({ page }) => {
  await ready(page);
  const reached = await page.evaluate(() => {
    let n = 0;
    const canvas = document.querySelector("canvas.interactive")!;
    // Count at the target, then stop it: a synthetic pointer can't be captured,
    // so letting it reach Excalidraw's setPointerCapture would throw.
    canvas.addEventListener("pointerdown", (e) => {
      n++;
      e.stopPropagation();
    });
    canvas.dispatchEvent(new PointerEvent("pointerdown", { pointerType: "pen", bubbles: true, clientX: 200, clientY: 200 }));
    canvas.dispatchEvent(new PointerEvent("pointerdown", { pointerType: "touch", bubbles: true, clientX: 200, clientY: 200 }));
    return n;
  });
  expect(reached).toBe(1);
});

test("double-tap on a card dives and never starts text editing", async ({ page }) => {
  await ready(page);
  await doubleTap(page, await cardCenter(page, "c-roads"));
  // Roads has no portal yet in the demo notebook: no dive, but also no editor.
  await page.waitForTimeout(300);
  const editing = await page.evaluate(() => (window as unknown as { __enjinDebug: { api: { getAppState(): { editingTextElement: unknown } } } }).__enjinDebug.api.getAppState().editingTextElement);
  expect(editing).toBeNull();
  expect(await page.locator("textarea.excalidraw-wysiwyg").count()).toBe(0);
});

test("mouse double-click dives too", async ({ page }) => {
  await ready(page);
  const p = await cardCenter(page, "c-legions");
  await page.mouse.dblclick(p.x, p.y);
  await expect.poll(() => portalId(page)).toBe("p-legions");
});

test("cards are movable (unlocked) and grouped", async ({ page }) => {
  await ready(page);
  const f = await frames(page);
  expect(f.every((c) => !c.locked)).toBe(true);
});

test("applyOps: new cards avoid others, updates keep position, deletes remove", async ({ page }) => {
  await ready(page);
  const before = await frames(page);
  const legions = before.find((c) => c.cardId === "c-legions")!;

  const res = (await call(page, "canvas.applyOps", {
    portalId: "p-root",
    ops: [
      { op: "upsert", card: { id: "c-new", type: "topic", title: "Aqueducts", summary: "Water by gravity.", state: "filling", childCount: 0 } },
      { op: "upsert", card: { id: "c-legions", type: "topic", title: "Legions (updated)", summary: "Changed.", state: "filled", childCount: 3 } },
      { op: "delete", cardId: "c-fall" },
    ],
  })) as { result: { placed: { cardId: string; x: number; y: number; width: number; height: number }[] } };

  const after = await frames(page);
  expect(after.map((c) => c.cardId).sort()).toEqual(["c-emperors", "c-legions", "c-new", "c-roads"]);
  const l2 = after.find((c) => c.cardId === "c-legions")!;
  expect([l2.x, l2.y]).toEqual([legions.x, legions.y]);
  const n = after.find((c) => c.cardId === "c-new")!;
  for (const o of after.filter((c) => c.cardId !== "c-new")) {
    const overlap = n.x < o.x + o.width && o.x < n.x + n.width && n.y < o.y + o.height && o.y < n.y + n.height;
    expect(overlap, `c-new overlaps ${o.cardId}`).toBe(false);
  }
  expect(res.result.placed.find((p) => p.cardId === "c-new")).toMatchObject({ x: n.x, y: n.y });

  const label = await page.evaluate(() =>
    (window as unknown as { __enjinDebug: { api: { getSceneElements(): { text?: string; customData?: Record<string, string> }[] } } }).__enjinDebug.api
      .getSceneElements()
      .find((e) => e.customData?.cardId === "c-legions" && e.customData?.role === "label")?.text,
  );
  expect(label).toContain("Legions (updated)");

  // Ops for a portal that isn't on screen are ignored.
  const other = (await call(page, "canvas.applyOps", { portalId: "p-legions", ops: [{ op: "delete", cardId: "c-roads" }] })) as { result: { placed: unknown[] } };
  expect(other.result.placed).toEqual([]);
  expect((await frames(page)).some((c) => c.cardId === "c-roads")).toBe(true);
});

test("a moved card keeps its new position after re-render", async ({ page }) => {
  await ready(page);
  await page.evaluate(() => {
    const { api } = (window as unknown as { __enjinDebug: { api: { getSceneElementsIncludingDeleted(): { customData?: Record<string, string> }[]; updateScene(u: unknown): void } } }).__enjinDebug;
    api.updateScene({
      elements: api.getSceneElementsIncludingDeleted().map((e) =>
        e.customData?.cardId === "c-roads" ? { ...e, x: (e as unknown as { x: number }).x + 500, version: (e as unknown as { version: number }).version + 1 } : e,
      ),
    });
  });
  const moved = (await frames(page)).find((c) => c.cardId === "c-roads")!;
  await call(page, "canvas.applyOps", {
    portalId: "p-root",
    ops: [{ op: "upsert", card: { id: "c-roads", type: "topic", title: "Roads", summary: "Now filled.", state: "filled", childCount: 0 } }],
  });
  const after = (await frames(page)).find((c) => c.cardId === "c-roads")!;
  expect([after.x, after.y]).toEqual([moved.x, moved.y]);
});

test("selecting a card tells native which card it is", async ({ page }) => {
  await ready(page);
  const p = await cardCenter(page, "c-roads");
  await page.touchscreen.tap(p.x, p.y);
  await expect
    .poll(() =>
      page.evaluate(() =>
        (window as unknown as { __devLog: { method: string; params: { cardIds: string[] } }[] }).__devLog
          .filter((r) => r.method === "selection.changed")
          .map((r) => r.params.cardIds.join(",")),
      ),
    )
    .toContain("c-roads");
});
