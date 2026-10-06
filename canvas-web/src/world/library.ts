import * as THREE from "three";

/**
 * The world's library: materials in ENJIN's white, black and glass, and the
 * shapes entities are built from. Shapes accept the same vocabulary as the
 * model3d skill (engine3d.ts), so a 3D figure can become a world's centrepiece.
 */

export type V3 = [number, number, number];
const num = (x: unknown, d: number) => (Number.isFinite(Number(x)) ? Number(x) : d);
export const vec = (x: unknown, d: V3): V3 => (Array.isArray(x) && x.length === 3 ? [num(x[0], d[0]), num(x[1], d[1]), num(x[2], d[2])] : d);

// ---------- materials ----------

const SWATCH: Record<string, number> = {
  white: 0xf4f4f2, light: 0xdcdcd9, grey: 0xa6a6ab, dark: 0x4a4a4f, black: 0x161618, accent: 0xe8590c,
  red: 0xd64545, blue: 0x2f6fbf, green: 0x2f9e44, yellow: 0xd9a82b,
};

const cache = new Map<string, THREE.Material>();

/** A material by name: a swatch (matte, satin), "glass", "metal", "clay", "ink", "glow", or a #hex. */
export function material(name: unknown): THREE.Material {
  const key = String(name ?? "white");
  const hit = cache.get(key);
  if (hit) return hit;
  let m: THREE.Material;
  if (key === "glass") {
    m = new THREE.MeshPhysicalMaterial({ color: 0xffffff, transmission: 1, roughness: 0.12, thickness: 0.6, ior: 1.45, metalness: 0, transparent: true });
  } else if (key === "metal") {
    m = new THREE.MeshStandardMaterial({ color: 0xc9c9cc, metalness: 0.9, roughness: 0.28 });
  } else if (key === "clay") {
    m = new THREE.MeshStandardMaterial({ color: 0xe9e3da, metalness: 0, roughness: 0.95 });
  } else if (key === "ink") {
    m = new THREE.MeshStandardMaterial({ color: 0x111113, metalness: 0.1, roughness: 0.55 });
  } else if (key === "glow") {
    m = new THREE.MeshStandardMaterial({ color: 0xe8590c, emissive: 0xe8590c, emissiveIntensity: 1.2, roughness: 0.4 });
  } else {
    const hex = /^#?([0-9a-f]{6})$/i.exec(key);
    const color = hex ? parseInt(hex[1]!, 16) : (SWATCH[key] ?? SWATCH.white!);
    m = new THREE.MeshStandardMaterial({ color, metalness: 0.02, roughness: key === "black" || key === "dark" ? 0.45 : 0.62 });
  }
  cache.set(key, m);
  return m;
}

// ---------- shapes ----------

const pairs = (x: unknown): [number, number][] =>
  Array.isArray(x) ? x.filter((q) => Array.isArray(q) && q.length >= 2).map((q: any) => [num(q[0], 0), num(q[1], 0)] as [number, number]) : [];

/** Geometry for a part, from the model3d vocabulary. */
export function geometry(p: any): THREE.BufferGeometry {
  const s = vec(p.size, [1, 1, 1]);
  const r = Math.max(0.001, num(p.radius, s[0] / 2));
  const h = num(p.height, s[1]);
  switch (p.shape) {
    case "sphere": return new THREE.SphereGeometry(r, 40, 28);
    case "cylinder": return new THREE.CylinderGeometry(r, r, h, 48);
    case "cone": return new THREE.ConeGeometry(r, h, 48);
    case "capsule": return new THREE.CapsuleGeometry(r, Math.max(0, h - 2 * r), 8, 24);
    case "torus": return new THREE.TorusGeometry(num(p.radius, 1), num(p.tube, 0.25), 24, 64).rotateX(Math.PI / 2);
    case "ring": {
      const inner = num(p.inner, r * 0.7);
      const prof = [new THREE.Vector2(inner, -h / 2), new THREE.Vector2(r, -h / 2), new THREE.Vector2(r, h / 2), new THREE.Vector2(inner, h / 2), new THREE.Vector2(inner, -h / 2)];
      return new THREE.LatheGeometry(prof, 64);
    }
    case "lathe": {
      const prof = pairs(p.profile).slice(0, 60).map(([a, b]) => new THREE.Vector2(Math.max(0, a), b));
      return prof.length >= 2 ? new THREE.LatheGeometry(prof, 48) : new THREE.SphereGeometry(0.3);
    }
    case "extrude": {
      const pts = pairs(p.outline).slice(0, 200);
      if (pts.length < 3) return new THREE.BoxGeometry(0.3, 0.3, 0.3);
      const shape = new THREE.Shape(pts.map(([x, y]) => new THREE.Vector2(x, y)));
      const depth = num(p.depth, 0.2);
      return new THREE.ExtrudeGeometry(shape, { depth, bevelEnabled: true, bevelSize: depth * 0.08, bevelThickness: depth * 0.08, bevelSegments: 2 }).translate(0, 0, -depth / 2);
    }
    case "tube": {
      const pts = (Array.isArray(p.points) ? p.points : []).slice(0, 80).map((q: unknown) => new THREE.Vector3(...vec(q, [0, 0, 0])));
      if (pts.length < 2) return new THREE.SphereGeometry(0.05);
      const path = new THREE.CurvePath<THREE.Vector3>();
      for (let i = 0; i < pts.length - 1; i++) path.add(new THREE.LineCurve3(pts[i], pts[i + 1]));
      return new THREE.TubeGeometry(path, Math.max(2, (pts.length - 1) * 4), Math.max(0.005, num(p.radius, 0.05)), 12, false);
    }
    default: return new THREE.BoxGeometry(s[0], s[1], s[2]);
  }
}

// ---------- molecules ----------

export const ELEMENTS: Record<string, { color: string; r: number }> = {
  H: { color: "white", r: 0.24 }, C: { color: "#3a3a3e", r: 0.36 }, N: { color: "blue", r: 0.35 }, O: { color: "red", r: 0.34 },
  S: { color: "yellow", r: 0.42 }, P: { color: "accent", r: 0.42 }, Cl: { color: "green", r: 0.42 }, F: { color: "#79c27a", r: 0.3 },
  Na: { color: "#8e6fc6", r: 0.5 }, Fe: { color: "#a65b3a", r: 0.46 },
};

/** model3d atoms + bonds as parts (ball-and-stick). */
export function moleculeParts(spec: any): any[] {
  const out: any[] = [];
  const byId = new Map<string, V3>();
  for (const a of (Array.isArray(spec?.atoms) ? spec.atoms : []).slice(0, 150)) {
    const pos = vec(a.position, [0, 0, 0]);
    const el = ELEMENTS[String(a.element ?? "C")] ?? { color: "grey", r: 0.38 };
    byId.set(String(a.id ?? ""), pos);
    out.push({ shape: "sphere", radius: el.r, position: pos, color: el.color, label: a.label, detail: a.detail, group: a.group });
  }
  for (const b of (Array.isArray(spec?.bonds) ? spec.bonds : []).slice(0, 250)) {
    const pa = byId.get(String(b?.[0])), pb = byId.get(String(b?.[1]));
    if (!pa || !pb) continue;
    const order = Math.max(1, Math.min(3, num(b?.[2], 1)));
    const d = new THREE.Vector3(...pb).sub(new THREE.Vector3(...pa)).normalize();
    const off = new THREE.Vector3().crossVectors(d, Math.abs(d.y) < 0.9 ? new THREE.Vector3(0, 1, 0) : new THREE.Vector3(1, 0, 0)).normalize();
    for (let k = 0; k < order; k++) {
      const sh = off.clone().multiplyScalar((k - (order - 1) / 2) * 0.12);
      out.push({ shape: "tube", points: [[pa[0] + sh.x, pa[1] + sh.y, pa[2] + sh.z], [pb[0] + sh.x, pb[1] + sh.y, pb[2] + sh.z]], radius: 0.055, color: "grey" });
    }
  }
  return out;
}
