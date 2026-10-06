import { convertToExcalidrawElements } from "@excalidraw/excalidraw";
import type { ExcalidrawElement } from "@excalidraw/excalidraw/element/types";
import type { Card } from "../bridge/schema";
import { CARD_H, CARD_W, IMAGE_H, type Rect, coverCrop, placeCards } from "./layout";

export type CardRole = "frame" | "image" | "placeholder" | "textbox" | "label" | "badge" | "header";
export interface EnjinData {
  cardId?: string;
  role: CardRole;
}

const STYLE: Record<Card["state"], { bg: string; stroke: "solid" | "dashed" }> = {
  stub: { bg: "#f1f3f5", stroke: "dashed" },
  filling: { bg: "#e7f5ff", stroke: "solid" },
  filled: { bg: "#fff4e6", stroke: "solid" },
  error: { bg: "#ffe3e3", stroke: "solid" },
};

const INSET = 10;

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

type Skeleton = NonNullable<Parameters<typeof convertToExcalidrawElements>[0]>[number];


/**
 * A card is a group: frame (background + border) → picture area (image or a
 * placeholder while one is found) → text. Text and pictures are owned by
 * native and regenerated from it; the kid moves the card as one piece.
 */
function cardSkeletons(card: Card, at: Rect): Skeleton[] {
  const style = STYLE[card.state];
  const common = { groupIds: [`g:${card.id}`], strokeColor: "#343a40", roughness: 0 } as const;
  const picture = hasPicture(card);
  const textTop = picture ? at.y + IMAGE_H : at.y;
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
        label: { text: "finding a picture…", fontSize: 16, strokeColor: "#868e96", customData: { cardId: card.id, role: "label" } } as never,
      });
    }
  }
  out.push({
    ...common,
    type: "rectangle",
    id: `${card.id}:text`,
    // A little air between the text and the card's border.
    x: at.x + 8,
    y: textTop + 4,
    width: at.width - 16,
    height: at.y + at.height - textTop - 8,
    strokeColor: "transparent",
    backgroundColor: "transparent",
    customData: { cardId: card.id, role: "textbox" },
    label: {
      text: card.summary ? `${card.title}\n\n${card.summary}` : card.title,
      // Labels inherit their container's stroke color, which is transparent here.
      strokeColor: "#1e1e1e",
      fontSize: 20,
      textAlign: "left",
      verticalAlign: "top",
      customData: { cardId: card.id, role: "label" },
    },
  });
  if (card.childCount > 0) {
    out.push({
      ...common,
      type: "text",
      id: `${card.id}:badge`,
      x: at.x + at.width - 56,
      y: at.y + at.height - 34,
      text: `▸ ${card.childCount}`,
      fontSize: 20,
      strokeColor: "#1971c2",
      customData: { cardId: card.id, role: "badge" },
    });
  }
  return out;
}

function headerSkeleton(title: string): Skeleton {
  return { type: "text", id: "header", x: 0, y: 0, text: title, fontSize: 44, locked: true, customData: { role: "header" } };
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
export function renderCards(current: readonly ExcalidrawElement[], upserts: Card[], deletes: string[], header?: string): RenderResult {
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
  const slots = placeCards(fresh.map((c) => cardSize(c)), occupied);
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
  if (header && !current.some((e) => enjinData(e)?.role === "header")) {
    out.push(...convertToExcalidrawElements([headerSkeleton(header)], { regenerateIds: false }));
  }
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

/** Full portal build: render every card, drop card elements whose card no longer exists. */
export function buildPortalElements(title: string, cards: Card[], persisted: readonly ExcalidrawElement[]): ExcalidrawElement[] {
  const live = new Set(cards.map((c) => c.id));
  const stale = [...new Set(persisted.map((e) => enjinData(e)?.cardId).filter((id): id is string => !!id && !live.has(id)))];
  return renderCards(persisted, cards, stale, title).elements;
}

export { CARD_W, CARD_H };
