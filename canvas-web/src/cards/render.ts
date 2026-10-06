import { convertToExcalidrawElements } from "@excalidraw/excalidraw";
import type { ExcalidrawElement } from "@excalidraw/excalidraw/element/types";
import type { Card } from "../bridge/schema";
import { CARD_H, CARD_W, type Rect, placeCards } from "./layout";

export type CardRole = "frame" | "label" | "badge" | "header";
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

function cardSkeletons(card: Card, at: Rect) {
  const style = STYLE[card.state];
  const groupIds = [`g:${card.id}`];
  const common = { groupIds, locked: true, strokeColor: "#343a40", roughness: 0 } as const;
  const skeletons: Parameters<typeof convertToExcalidrawElements>[0] = [
    {
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
      label: {
        text: `${card.title}\n\n${card.summary}`,
        fontSize: 20,
        textAlign: "left",
        verticalAlign: "top",
        customData: { cardId: card.id, role: "label" },
      },
      ...common,
    },
  ];
  if (card.childCount > 0) {
    skeletons!.push({
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
  return skeletons!;
}

/**
 * Build the elements for a portal. Persisted elements win; any card without a
 * frame in `persisted` is laid out fresh, avoiding everything already there.
 */
export function buildPortalElements(title: string, cards: Card[], persisted: readonly ExcalidrawElement[]): ExcalidrawElement[] {
  const present = new Set(cardRects(persisted).map((c) => c.cardId));
  const missing = cards.filter((c) => !present.has(c.id));
  const occupied = persisted.filter((e) => !e.isDeleted).map((e) => ({ x: e.x, y: e.y, width: e.width, height: e.height }));
  const slots = placeCards(missing.length, occupied);

  const skeletons: Parameters<typeof convertToExcalidrawElements>[0] = [];
  if (!persisted.some((e) => enjinData(e)?.role === "header")) {
    skeletons!.push({
      type: "text",
      id: "header",
      x: 0,
      y: 0,
      text: title,
      fontSize: 44,
      locked: true,
      customData: { role: "header" },
    });
  }
  missing.forEach((card, i) => skeletons!.push(...cardSkeletons(card, slots[i]!)));
  return [...persisted, ...convertToExcalidrawElements(skeletons, { regenerateIds: false })];
}

export { CARD_W, CARD_H };
