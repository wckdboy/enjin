import { FONT_FAMILY, convertToExcalidrawElements } from "@excalidraw/excalidraw";
import type { ExcalidrawElement } from "@excalidraw/excalidraw/element/types";
import type { Card, PortalScene } from "../bridge/schema";
import { t } from "../i18n";
import { CARD_H, CARD_W, COLUMNS, GAP, HEADER_H, IMAGE_H, type Rect, coverCrop, placeCards, union } from "./layout";

export type CardRole = "frame" | "image" | "placeholder" | "textbox" | "title" | "summary" | "label" | "badge" | "cue"
  | "header" | "subtitle" | "hero";
export interface EnjinData {
  cardId?: string;
  role: CardRole;
}

// The ENJIN palette, monochrome like the motor icon (same values as the native Theme).
const STYLE: Record<Card["state"], { bg: string; stroke: "solid" | "dashed" }> = {
  stub: { bg: "#f2f2f2", stroke: "dashed" },
  filling: { bg: "#e9e9e9", stroke: "solid" },
  filled: { bg: "#ffffff", stroke: "solid" },
  error: { bg: "#f6e3e3", stroke: "solid" },
};

const INK = "#0b0b0c";
const MUTED = "#6a6a70";
const ACCENT = INK;
/** Clean, neutral type on cards (matches the native SF Pro): Helvetica for titles and text. */
const DISPLAY = FONT_FAMILY.Helvetica;
const READING = FONT_FAMILY.Helvetica;
const INSET = 10;
const TITLE_PX = 24;
const SUMMARY_PX = 17;
/** Width of the three-column card area; portal banners span it. */
export const CONTENT_W = COLUMNS * CARD_W + (COLUMNS - 1) * GAP;
const HERO_H = 300;
const HEADER_ROLES = new Set<CardRole>(["header", "subtitle", "hero"]);

export function enjinData(el: { customData?: Record<string, unknown> }): EnjinData | null {
  const d = el.customData as EnjinData | undefined;
  return d && typeof d.role === "string" ? d : null;
}

/** Bounds of each card in the scene, read from its frame element. */
export function cardRects(elements: readonly ExcalidrawElement[]): { cardId: string; rect: Rect }[] {
  return elements
    .filter((e) => !e.isDeleted && enjinData(e)?.role === "frame")
    .map((e) => ({ cardId: enjinData(e)!.cardId!, rect: { x: e.x, y: e.y, width: e.width, height: e.height } }));
}

export function hasPicture(card: Card): boolean {
  return !!card.image || !!card.imagePending;
}

export function cardSize(card: Card, width = CARD_W): { width: number; height: number } {
  return { width, height: hasPicture(card) ? IMAGE_H + CARD_H : CARD_H };
}

/** Rough line count for Excalifont at `px` in `width` (avg glyph ≈ 0.53em). */
export function estimateLines(text: string, px: number, width: number, em = 0.53): number {
  const perLine = Math.max(8, Math.floor(width / (px * em)));
  return text.split("\n").reduce((n, para) => n + Math.max(1, Math.ceil(para.length / perLine)), 0);
}

type Skeleton = NonNullable<Parameters<typeof convertToExcalidrawElements>[0]>[number];

/**
 * A card is a group: frame → picture (or placeholder while one is found) →
 * title → summary, plus a "dive in" cue on stubs and a count of what's inside.
 * Content is owned by native and regenerated from it; the kid moves the card
 * as one piece.
 */
function cardSkeletons(card: Card, at: Rect): Skeleton[] {
  const style = STYLE[card.state];
  const common = { groupIds: [`g:${card.id}`], strokeColor: INK, roughness: 0 } as const;
  const clear = { strokeColor: "transparent", backgroundColor: "transparent" } as const;
  const picture = hasPicture(card);
  const textTop = (picture ? at.y + IMAGE_H : at.y) + 6;
  const textW = at.width - 2 * INSET;
  const out: Skeleton[] = [
    {
      ...common,
      type: "rectangle",
      id: `${card.id}:frame`,
      x: at.x,
      y: at.y,
      width: at.width,
      height: at.height,
      backgroundColor: style.bg,
      fillStyle: "solid",
      strokeStyle: style.stroke,
      strokeWidth: 2,
      roundness: { type: 3 },
      customData: { cardId: card.id, role: "frame" },
    },
  ];
  if (picture) {
    const box = { x: at.x + INSET, y: at.y + INSET, width: at.width - 2 * INSET, height: IMAGE_H - INSET };
    if (card.image) {
      const { width: w, height: h } = card.image;
      out.push({
        ...common,
        type: "image",
        id: `${card.id}:image`,
        ...box,
        fileId: card.image.fileId as never,
        status: "saved",
        crop: { ...coverCrop(w, h, box.width / box.height), naturalWidth: w, naturalHeight: h },
        customData: { cardId: card.id, role: "image" },
      });
    } else {
      out.push({
        ...common,
        type: "rectangle",
        id: `${card.id}:placeholder`,
        ...box,
        backgroundColor: "#e9ecef",
        fillStyle: "solid",
        strokeColor: "transparent",
        roundness: { type: 3 },
        customData: { cardId: card.id, role: "placeholder" },
        label: { text: t.findingPicture(), fontSize: 16, fontFamily: READING, strokeColor: "#868e96", customData: { cardId: card.id, role: "label" } } as never,
      });
    }
  }

  // Title, then summary under it: two sizes so the eye finds the title first.
  const titleLines = Math.min(3, estimateLines(card.title, TITLE_PX, textW - 10, 0.56));
  const titleH = titleLines * TITLE_PX * 1.25 + 6;
  out.push({
    ...common,
    ...clear,
    type: "rectangle",
    id: `${card.id}:title`,
    x: at.x + INSET - 4,
    y: textTop,
    width: textW + 8,
    height: titleH,
    customData: { cardId: card.id, role: "title" },
    label: { text: card.title, strokeColor: INK, fontSize: TITLE_PX, fontFamily: DISPLAY, textAlign: "left", verticalAlign: "top", customData: { cardId: card.id, role: "label" } } as never,
  });
  if (card.summary) {
    const top = textTop + titleH + 2;
    out.push({
      ...common,
      ...clear,
      type: "rectangle",
      id: `${card.id}:summary`,
      x: at.x + INSET - 4,
      y: top,
      width: textW + 8,
      height: Math.max(30, at.y + at.height - top - 34),
      customData: { cardId: card.id, role: "summary" },
      label: { text: card.summary, strokeColor: MUTED, fontSize: SUMMARY_PX, fontFamily: READING, textAlign: "left", verticalAlign: "top", customData: { cardId: card.id, role: "label" } } as never,
    });
  }

  // Bottom line: what you can do with it.
  const bottom = at.y + at.height - 30;
  if (card.type === "topic" && (card.state === "stub" || card.childCount === 0)) {
    out.push({
      ...common,
      type: "text",
      id: `${card.id}:cue`,
      x: at.x + INSET,
      y: bottom,
      text: card.state === "stub" ? t.diveIn() : "",
      fontSize: 16,
      fontFamily: READING,
      strokeColor: ACCENT,
      customData: { cardId: card.id, role: "cue" },
    });
  }
  if (card.childCount > 0) {
    const label = t.inside(card.childCount);
    out.push({
      ...common,
      type: "text",
      id: `${card.id}:badge`,
      x: at.x + at.width - INSET - label.length * 16 * 0.55,
      y: bottom,
      text: label,
      fontSize: 16,
      fontFamily: READING,
      strokeColor: ACCENT,
      customData: { cardId: card.id, role: "badge" },
    });
  }
  return out.filter((s) => !(s.type === "text" && "text" in s && s.text === ""));
}

export interface Header {
  title: string;
  subtitle?: string;
  hero?: Card["image"];
}

/** Portal header: title at the top-left, the owner card's summary under it, its picture as a banner above. */
function headerSkeletons(h: Header): Skeleton[] {
  const out: Skeleton[] = [
    { type: "text", id: "header", x: 0, y: 0, text: h.title, fontSize: 48, fontFamily: DISPLAY, strokeColor: INK, locked: true, customData: { role: "header" } },
  ];
  if (h.subtitle) {
    out.push({
      type: "rectangle", id: "header:subtitle", x: -4, y: 58, width: CONTENT_W, height: 44, strokeColor: "transparent",
      backgroundColor: "transparent", locked: true, customData: { role: "subtitle" },
      label: { text: h.subtitle, strokeColor: MUTED, fontSize: 20, fontFamily: READING, textAlign: "left", verticalAlign: "top", customData: { role: "subtitle" } } as never,
    });
  }
  if (h.hero) {
    const box = { x: 0, y: -HERO_H - 24, width: CONTENT_W, height: HERO_H };
    out.push({
      type: "image", id: "header:hero", ...box, fileId: h.hero.fileId as never, status: "saved", locked: true,
      crop: { ...coverCrop(h.hero.width, h.hero.height, box.width / box.height), naturalWidth: h.hero.width, naturalHeight: h.hero.height },
      customData: { role: "hero" },
    });
  }
  return out;
}

/** Replace the header block (title/subtitle/hero) in a scene. */
export function withHeader(current: readonly ExcalidrawElement[], header: Header): ExcalidrawElement[] {
  const rest = current.filter((e) => !HEADER_ROLES.has(enjinData(e)?.role as CardRole));
  return [...convertToExcalidrawElements(headerSkeletons(header), { regenerateIds: false }), ...rest];
}

/** Where new cards may start: below the title/subtitle (the banner sits above the title). */
function cardsTop(elements: readonly ExcalidrawElement[]): number {
  const header = elements.filter((e) => !e.isDeleted && ["header", "subtitle"].includes(enjinData(e)?.role ?? ""));
  const b = union(header.map((e) => ({ x: e.x, y: e.y, width: e.width, height: e.height })));
  return Math.max(HEADER_H, b ? b.y + b.height + 24 : 0);
}

export interface RenderResult {
  elements: ExcalidrawElement[];
  placed: { cardId: string; rect: Rect }[];
}

/**
 * Apply card upserts/deletes to a scene. Existing cards are regenerated in
 * place (same position and width, same z-order slot; height follows the
 * content); new cards are placed in free space. Everything that isn't a card
 * (kid ink, shapes) is untouched.
 */
export function renderCards(current: readonly ExcalidrawElement[], upserts: Card[], deletes: string[]): RenderResult {
  const existing = new Map(cardRects(current).map((c) => [c.cardId, c.rect]));
  const replaced = new Set([...upserts.map((c) => c.id), ...deletes]);
  const cardOf = (e: ExcalidrawElement) => enjinData(e)?.cardId;

  const rects = new Map<string, Rect>();
  for (const c of upserts) {
    const old = existing.get(c.id);
    if (old) rects.set(c.id, { x: old.x, y: old.y, width: old.width, height: cardSize(c, old.width).height });
  }
  const kept = current.filter((e) => !(cardOf(e) && replaced.has(cardOf(e)!)));
  const fresh = upserts.filter((c) => !rects.has(c.id));
  // Updated cards keep their spot, so it stays occupied; deleted cards free theirs.
  const occupied = [...kept.filter((e) => !e.isDeleted).map((e) => ({ x: e.x, y: e.y, width: e.width, height: e.height })), ...rects.values()];
  const slots = placeCards(fresh.map((c) => cardSize(c)), occupied, cardsTop(current));
  fresh.forEach((c, i) => rects.set(c.id, slots[i]!));

  const versionOf = new Map(current.map((e) => [e.id, e.version]));
  const generated = new Map<string, ExcalidrawElement[]>();
  for (const card of upserts) {
    const els = convertToExcalidrawElements(cardSkeletons(card, rects.get(card.id)!), { regenerateIds: false }).map(
      // Bump past the old version so reconcilers and caches treat it as newer.
      (e) => ({ ...e, version: Math.max(e.version, (versionOf.get(e.id) ?? 0) + 1) }) as ExcalidrawElement,
    );
    generated.set(card.id, els);
  }

  const out: ExcalidrawElement[] = [];
  const emitted = new Set<string>();
  for (const e of current) {
    const id = cardOf(e);
    if (!id || !replaced.has(id)) {
      out.push(e);
    } else if (generated.has(id) && !emitted.has(id)) {
      out.push(...generated.get(id)!); // first slot of the old card keeps its z-order
      emitted.add(id);
    }
  }
  for (const [id, els] of generated) if (!emitted.has(id)) out.push(...els);

  return { elements: out, placed: upserts.map((c) => ({ cardId: c.id, rect: rects.get(c.id)! })) };
}

/** Full portal build: header, every card, and no card elements whose card no longer exists. */
export function buildPortalElements(scene: Pick<PortalScene, "title" | "subtitle" | "hero" | "cards">, persisted: readonly ExcalidrawElement[]): ExcalidrawElement[] {
  const live = new Set(scene.cards.map((c) => c.id));
  const stale = [...new Set(persisted.map((e) => enjinData(e)?.cardId).filter((id): id is string => !!id && !live.has(id)))];
  const headed = withHeader(persisted, { title: scene.title, subtitle: scene.subtitle, hero: scene.hero });
  return renderCards(headed, scene.cards, stale).elements;
}

export { CARD_W, CARD_H };
