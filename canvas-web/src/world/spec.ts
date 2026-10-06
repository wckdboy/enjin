import type { Card, PortalScene } from "../bridge/schema";

/**
 * A world: what one portal looks like as a place. Phase 1 builds it from the
 * portal's cards, so every notebook (old or new) is already a world:
 * - the centrepiece: the portal's first 3D model (a model3d figure), at full size;
 * - doors: its topic cards, glass portals you fly into;
 * - panels: everything else (notes, figures, widgets, live models), glass in space.
 */
export interface WorldSpec {
  portalId: string;
  title: string;
  subtitle?: string;
  centerpiece: { cardId: string; spec: Record<string, unknown> } | null;
  doors: Card[];
  panels: Card[];
}

export function worldFromScene(scene: Pick<PortalScene, "portalId" | "title" | "subtitle" | "cards">): WorldSpec {
  const cards = scene.cards;
  const model = cards.find((c) => c.visual?.kind === "model3d" && c.visual.spec);
  return {
    portalId: scene.portalId,
    title: scene.title,
    subtitle: scene.subtitle,
    centerpiece: model ? { cardId: model.id, spec: model.visual!.spec as Record<string, unknown> } : null,
    doors: cards.filter((c) => c.type === "topic" && !c.visual),
    panels: cards.filter((c) => c !== model && !(c.type === "topic" && !c.visual)),
  };
}

/**
 * Where things go, around a centrepiece at the origin, seen first from the front
 * (+z). The front stays open between you and the centrepiece; doors stand around
 * the sides and back; panels hang higher, in a gallery ring behind them. Pure, so
 * it's unit-testable. Angles are measured round from the front (+z).
 */
export function layoutWorld(doors: number, panels: number): { doors: { x: number; y: number; z: number }[]; panels: { x: number; y: number; z: number }[] } {
  const at = (az: number, r: number, y: number) => ({ x: Math.sin(az) * r, y, z: Math.cos(az) * r });
  const spread = (n: number, from: number, to: number) =>
    Array.from({ length: n }, (_, i) => (n === 1 ? (from + to) / 2 : from + ((to - from) * i) / (n - 1)));
  const deg = Math.PI / 180;
  // Doors: from the right side round the back to the left (70°..290°), alternating heights.
  const doorAz = spread(doors, doors > 2 ? 70 * deg : 120 * deg, doors > 2 ? 290 * deg : 240 * deg);
  // Panels: centred behind, ~30° apart, as wide as they need (never into the front 100°).
  const step = 38 * deg;
  const half = Math.min(((panels - 1) * step) / 2, 130 * deg);
  const panelAz = spread(panels, Math.PI - half, Math.PI + half);
  return {
    doors: doorAz.map((a, i) => at(a, 6.5, 0.2 + (i % 2 ? 0.7 : -0.2))),
    panels: panelAz.map((a) => at(a, 13.5, 3.1)),
  };
}
