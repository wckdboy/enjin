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

test("ops for the portal being dived into are applied once it lands", async ({ page }) => {
  await ready(page);
  const scene = await page.evaluate(() => (window as unknown as { __devScene(id: string): unknown }).__devScene("p-legions"));
  // Start the dive and send ops for the destination while it's still animating.
  const [, ops] = await Promise.all([
    call(page, "portal.load", { scene, transition: "dive" }),
    (async () => {
      await page.waitForTimeout(50);
      return call(page, "canvas.applyOps", {
        portalId: "p-legions",
        ops: [{ op: "upsert", card: { id: "c-early", type: "topic", title: "Arrived early", summary: "x", state: "stub", childCount: 0 } }],
      });
    })(),
  ]);
  expect((ops as { result: { placed: { cardId: string }[] } }).result.placed.map((p) => p.cardId)).toEqual(["c-early"]);
  expect((await frames(page)).some((c) => c.cardId === "c-early")).toBe(true);
});

test("canvas.frame eases onto a card without diving", async ({ page }) => {
  await ready(page);
  const before = await page.evaluate(() => (window as unknown as { __enjinDebug: Debug }).__enjinDebug.api.getAppState().zoom.value);
  const res = (await call(page, "canvas.frame", { cardId: "c-fall" })) as { result: { framed: boolean } };
  expect(res.result.framed).toBe(true);
  await page.waitForTimeout(600);
  const c = await cardCenter(page, "c-fall");
  const vp = page.viewportSize()!;
  expect(Math.abs(c.x - vp.width / 2)).toBeLessThan(5);
  expect(Math.abs(c.y - vp.height / 2)).toBeLessThan(5);
  expect(await portalId(page)).toBe("p-root");
  const after = await page.evaluate(() => (window as unknown as { __enjinDebug: Debug }).__enjinDebug.api.getAppState().zoom.value);
  expect(after).toBeLessThanOrEqual(before * 1.2 + 1e-6);
});

test("selecting a card shows Open and Dive in right on the card", async ({ page }) => {
  await ready(page);
  const p = await cardCenter(page, "c-legions");
  await page.touchscreen.tap(p.x, p.y);
  const pill = page.locator("[data-enjin=card-actions]");
  await expect(pill).toBeVisible();
  const box = (await pill.boundingBox())!;
  expect(Math.abs(box.x + box.width / 2 - p.x)).toBeLessThan(200); // over the card, not somewhere else

  await pill.getByRole("button", { name: "Open" }).dispatchEvent("pointerup");
  await expect
    .poll(() => page.evaluate(() => (window as unknown as { __devLog: { method: string; params: { cardId?: string } }[] }).__devLog.filter((r) => r.method === "card.open").map((r) => r.params.cardId)))
    .toEqual(["c-legions"]);

  await pill.getByRole("button", { name: "Dive in" }).dispatchEvent("pointerup");
  await expect.poll(() => portalId(page)).toBe("p-legions");
  await expect(pill).toBeHidden();
});

test("notes get Open but no Dive in", async ({ page }) => {
  await ready(page);
  await call(page, "canvas.applyOps", { portalId: "p-root", ops: [{ op: "upsert", card: { id: "c-note", type: "note", title: "My note", summary: "hi", state: "filled", childCount: 0 } }] });
  const p = await cardCenter(page, "c-note");
  await page.touchscreen.tap(p.x, p.y);
  const pill = page.locator("[data-enjin=card-actions]");
  await expect(pill.getByRole("button", { name: "Open" })).toBeVisible();
  await expect(pill.getByRole("button", { name: "Dive in" })).toBeHidden();
});

test("Excalidraw's own UI never shows; ENJIN's tools drive it", async ({ page }) => {
  await ready(page);
  await expect(page.locator(".excalidraw .layer-ui__wrapper")).toBeHidden();
  const state = () =>
    page.evaluate(() => {
      const s = (window as unknown as { __enjinDebug: { api: { getAppState(): { activeTool: { type: string }; currentItemStrokeColor: string; currentItemOpacity: number } } } }).__enjinDebug.api.getAppState();
      return { tool: s.activeTool.type, color: s.currentItemStrokeColor, opacity: s.currentItemOpacity };
    });
  await call(page, "canvas.setTool", { tool: "highlighter", color: "#e8590c" });
  expect(await state()).toEqual({ tool: "freedraw", color: "#e8590c", opacity: 35 });
  await call(page, "canvas.setTool", { tool: "rectangle", color: "#1971c2" });
  expect(await state()).toEqual({ tool: "rectangle", color: "#1971c2", opacity: 100 });
});

test("with a non-ink tool, Pencil acts on the canvas (select, erase, shapes)", async ({ page }) => {
  await ready(page);
  const penReaches = () =>
    page.evaluate(() => {
      let n = 0;
      const canvas = document.querySelector("canvas.interactive")!;
      const f = (e: Event) => { n++; e.stopPropagation(); };
      canvas.addEventListener("pointerdown", f);
      canvas.dispatchEvent(new PointerEvent("pointerdown", { pointerType: "pen", bubbles: true, clientX: 200, clientY: 200 }));
      canvas.removeEventListener("pointerdown", f);
      return n;
    });
  await call(page, "canvas.setTool", { tool: "freedraw", color: "#2a2a3c" });
  expect(await penReaches()).toBe(0); // ink tools: Pencil belongs to PencilKit
  await call(page, "canvas.setTool", { tool: "selection", color: "#2a2a3c" });
  expect(await penReaches()).toBe(1);
});

test("undo and redo from the tool rail", async ({ page }) => {
  await ready(page);
  const inkCount = () =>
    page.evaluate(() => (window as unknown as { __enjinDebug: Debug }).__enjinDebug.api.getSceneElements().filter((e) => e.type === "freedraw").length);
  await call(page, "ink.commit", { strokeId: "u", tool: "pen", color: "#000", width: 3, points: [[300, 900], [400, 950]], pressures: [] });
  expect(await inkCount()).toBe(1);
  await call(page, "canvas.history", { action: "undo" });
  await expect.poll(inkCount).toBe(0);
  await call(page, "canvas.history", { action: "redo" });
  await expect.poll(inkCount).toBe(1);
});

test("picture cards: placeholder reserves space, image arrives in place without distortion", async ({ page }) => {
  await ready(page);
  const card = { id: "c-pic", type: "topic", title: "Testudo", summary: "Shields locked like a tortoise shell.", state: "filled", childCount: 0 };
  await call(page, "canvas.applyOps", { portalId: "p-root", ops: [{ op: "upsert", card: { ...card, imagePending: true } }] });
  const before = (await frames(page)).find((c) => c.cardId === "c-pic")!;
  expect(before.height).toBe(386);
  const roles = () =>
    page.evaluate(() =>
      (window as unknown as { __enjinDebug: Debug }).__enjinDebug.api
        .getSceneElements()
        .filter((e) => e.customData?.cardId === "c-pic")
        .map((e) => e.customData!.role),
    );
  expect(await roles()).toContain("placeholder");

  // A 2:1 image, made in the page.
  const dataURL = await page.evaluate(() => {
    const c = document.createElement("canvas");
    c.width = 400;
    c.height = 200;
    const g = c.getContext("2d")!;
    g.fillStyle = "#c92a2a";
    g.fillRect(0, 0, 400, 200);
    return c.toDataURL("image/png");
  });
  await call(page, "canvas.addFiles", { files: [{ id: "img-test", mimeType: "image/png", dataURL }] });
  await call(page, "canvas.applyOps", { portalId: "p-root", ops: [{ op: "upsert", card: { ...card, image: { fileId: "img-test", width: 400, height: 200 } } }] });

  const after = (await frames(page)).find((c) => c.cardId === "c-pic")!;
  expect([after.x, after.y, after.height]).toEqual([before.x, before.y, 386]);
  const img = await page.evaluate(() =>
    (window as unknown as { __enjinDebug: Debug }).__enjinDebug.api.getSceneElements().find((e) => e.type === "image") as unknown as {
      width: number; height: number; fileId: string; x: number;
    },
  );
  expect(img.fileId).toBe("img-test");
  // Fills the picture area (cropped to fit, not stretched).
  expect([img.width, img.height]).toEqual([300, 180]);
  const crop = (img as unknown as { crop: { width: number; height: number } }).crop;
  expect(crop.width / crop.height).toBeCloseTo(300 / 180);
  expect(await roles()).not.toContain("placeholder");
  // Actually drawn: sample the canvas at the image's center, it should be the image's red.
  const center = await page.evaluate(() => {
    const { api } = (window as unknown as { __enjinDebug: Debug }).__enjinDebug;
    const e = api.getSceneElements().find((el) => el.type === "image") as unknown as { x: number; y: number; width: number; height: number };
    const s = api.getAppState();
    return { x: (e.x + e.width / 2 + s.scrollX) * s.zoom.value, y: (e.y + e.height / 2 + s.scrollY) * s.zoom.value };
  });
  await expect
    .poll(() =>
      page.evaluate(({ x, y }) => {
        const c = document.querySelector("canvas.excalidraw__canvas.static") as HTMLCanvasElement;
        const dpr = c.width / c.clientWidth;
        return Array.from(c.getContext("2d")!.getImageData(Math.round(x * dpr), Math.round(y * dpr), 1, 1).data.slice(0, 3));
      }, center),
    )
    .toEqual([201, 42, 42]);
  // Text is visible too (dark pixels in the text area).
  await page.screenshot({ path: "test-results/picture-card.png" });
});

test("new cards never overlap tall picture cards", async ({ page }) => {
  await ready(page);
  const ops = Array.from({ length: 6 }, (_, i) => ({
    op: "upsert",
    card: { id: `c-m${i}`, type: "topic", title: `M${i}`, summary: "x", state: "filled", childCount: 0, ...(i % 2 ? {} : { imagePending: true }) },
  }));
  await call(page, "canvas.applyOps", { portalId: "p-root", ops });
  const all = await frames(page);
  for (let i = 0; i < all.length; i++)
    for (let j = i + 1; j < all.length; j++) {
      const a = all[i]!;
      const b = all[j]!;
      const overlap = a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;
      expect(overlap, `${a.cardId} overlaps ${b.cardId}`).toBe(false);
    }
});

test("card text is actually drawn (not transparent)", async ({ page }) => {
  await ready(page);
  const label = await page.evaluate(() =>
    (window as unknown as { __enjinDebug: { api: { getSceneElements(): { strokeColor: string; customData?: Record<string, string> }[] } } }).__enjinDebug.api
      .getSceneElements()
      .filter((e) => e.customData?.role === "label")
      .map((e) => e.strokeColor),
  );
  expect(label.length).toBeGreaterThan(0);
  expect(label.every((c) => c !== "transparent")).toBe(true);
});

test("the canvas speaks Danish when told to", async ({ page }) => {
  await ready(page);
  await call(page, "canvas.setLanguage", { language: "da" });
  const texts = await page.evaluate(() =>
    (window as unknown as { __enjinDebug: { api: { getSceneElements(): { text?: string; customData?: Record<string, string> }[] } } }).__enjinDebug.api
      .getSceneElements()
      .filter((e) => e.customData?.role === "cue" || e.customData?.role === "badge")
      .map((e) => e.text),
  );
  expect(texts).toContain("dyk ind →");
  expect(texts).toContain("3 indeni →");
  const p = await cardCenter(page, "c-legions");
  await page.touchscreen.tap(p.x, p.y);
  await expect(page.locator("[data-enjin=card-actions]").getByRole("button", { name: "Dyk ind" })).toBeVisible();
});

test("an image pasted onto the canvas is sent for ENJIN styling and swapped in", async ({ page }) => {
  await ready(page);
  // What Excalidraw does on paste: add a file, then an image element using it.
  await page.evaluate(() => {
    const { api } = (window as unknown as { __enjinDebug: { api: {
      addFiles(f: unknown[]): void; updateScene(u: unknown): void; getSceneElementsIncludingDeleted(): unknown[] } } }).__enjinDebug;
    const c = document.createElement("canvas"); c.width = 40; c.height = 40;
    c.getContext("2d")!.fillRect(0, 0, 40, 40);
    api.addFiles([{ id: "pasted-1", mimeType: "image/png", dataURL: c.toDataURL("image/png"), created: Date.now() }]);
    api.updateScene({ elements: [...api.getSceneElementsIncludingDeleted(), {
      type: "image", id: "img-el", x: 700, y: 700, width: 40, height: 40, angle: 0, fileId: "pasted-1", status: "saved", scale: [1, 1],
      strokeColor: "transparent", backgroundColor: "transparent", fillStyle: "solid", strokeWidth: 1, strokeStyle: "solid", roughness: 0, opacity: 100,
      groupIds: [], frameId: null, roundness: null, seed: 1, version: 1, versionNonce: 1, isDeleted: false, boundElements: null, updated: 1, link: null, locked: false,
      index: "a9", crop: null,
    }] });
  });
  await expect.poll(() =>
    page.evaluate(() => (window as unknown as { __devLog: { method: string }[] }).__devLog.filter((r) => r.method === "media.stylize").length),
  ).toBe(1);
  await expect.poll(() =>
    page.evaluate(() => ((window as unknown as { __enjinDebug: Debug }).__enjinDebug.api.getSceneElements().find((e) => e.id === "img-el") as unknown as { fileId: string }).fileId),
  ).toMatch(/^img-k-/);
});
