import * as THREE from "three";
import { CSS3DSprite } from "three/examples/jsm/renderers/CSS3DRenderer.js";
import type { Card } from "../bridge/schema";
import { t } from "../i18n";
import { COLOR_ONLY } from "./Look";
import { geometry, material, moleculeParts, vec, type V3 } from "./library";
import { PX_PER_UNIT } from "./Panels";

type Motion = { axis: string; rpm: number; center: THREE.Vector3 } | null;
const motion = (m: any): Motion =>
  m ? { axis: String(m.axis ?? "y"), rpm: Math.max(-600, Math.min(600, Number(m.rpm) || 10)), center: new THREE.Vector3(...vec(m.center, [0, 0, 0])) } : null;
const AXIS: Record<string, THREE.Vector3> = { x: new THREE.Vector3(1, 0, 0), y: new THREE.Vector3(0, 1, 0), z: new THREE.Vector3(0, 0, 1) };

interface Part {
  mesh: THREE.Mesh;
  base: THREE.Vector3;
  baseRot: THREE.Euler;
  explode: THREE.Vector3;
  spin: Motion;
  orbit: Motion;
  group: string | null;
  label: string | null;
  detail: string | null;
}

/**
 * The 3D side of a world: the centrepiece (a model in the model3d vocabulary,
 * sized to fill the middle of the room), and the doors around it. Labels are
 * CSS3D sprites so they stay crisp and always face you.
 */
export class WorldView {
  readonly root = new THREE.Group();
  readonly labels = new THREE.Group();
  private parts: Part[] = [];
  private groups = new Map<string, { pivot: THREE.Vector3; spin: Motion; orbit: Motion }>();
  private doors = new Map<string, THREE.Object3D>();
  private exploded = 0;
  explodeTarget = 0;
  hasExplode = false;
  hasMotion = false;
  private scale = 1;
  private offset = new THREE.Vector3();

  constructor(scene: THREE.Scene, labelScene: THREE.Scene) {
    scene.add(this.root);
    labelScene.add(this.labels);
  }

  clear(): void {
    this.root.clear();
    this.labels.clear();
    this.parts = [];
    this.groups.clear();
    this.doors.clear();
    this.exploded = this.explodeTarget = 0;
  }

  // ---------- the centrepiece ----------

  buildCenterpiece(spec: any): void {
    const raw: any[] = [...(Array.isArray(spec?.parts) ? spec.parts : []).slice(0, 120), ...moleculeParts(spec)];
    for (const [name, g] of Object.entries(spec?.groups ?? {})) {
      const gg = g as any;
      this.groups.set(name, { pivot: new THREE.Vector3(...vec(gg?.pivot, [0, 0, 0])), spin: motion(gg?.spin), orbit: motion(gg?.orbit) });
    }
    const model = new THREE.Group();
    for (const p of raw) {
      const mesh = new THREE.Mesh(geometry(p), material(p.color));
      const pos = vec(p.position, [0, 0, 0]);
      const rot = vec(p.rotation, [0, 0, 0]).map((d) => (d * Math.PI) / 180) as V3;
      mesh.position.set(...pos);
      mesh.rotation.set(...rot);
      mesh.userData = { kind: "part", index: this.parts.length };
      model.add(mesh);
      this.parts.push({
        mesh, base: mesh.position.clone(), baseRot: mesh.rotation.clone(), explode: new THREE.Vector3(...vec(p.explode, [0, 0, 0])),
        spin: motion(p.spin), orbit: motion(p.orbit), group: p.group ? String(p.group) : null,
        label: p.label ? String(p.label).slice(0, 32) : null, detail: p.detail ? String(p.detail).slice(0, 220) : null,
      });
    }
    this.hasExplode = this.parts.some((p) => p.explode.lengthSq() > 0);
    this.hasMotion = this.parts.some((p) => p.spin || p.orbit) || [...this.groups.values()].some((g) => g.spin || g.orbit);
    // Fit: the model fills a sphere of radius 2.4 at the centre of the room, resting just above the floor.
    const box = new THREE.Box3().setFromObject(model);
    const size = box.getSize(new THREE.Vector3());
    this.scale = 4.8 / Math.max(size.x, size.y, size.z, 0.001);
    this.offset.copy(box.getCenter(new THREE.Vector3())).multiplyScalar(-1);
    model.position.copy(this.offset).multiplyScalar(this.scale);
    model.scale.setScalar(this.scale);
    model.position.y += 0.4;
    this.root.add(model);
    const fp = box.getSize(new THREE.Vector3()).multiplyScalar(this.scale);
    this.root.add(contactShadow(0, 0, Math.max(fp.x, fp.z) * 0.62, 0.22));
    // Labels float just above their part.
    this.parts.forEach((p, i) => {
      if (!p.label) return;
      const el = document.createElement("div");
      el.className = "plabel";
      el.textContent = p.label;
      el.dataset.part = String(i);
      const sprite = new CSS3DSprite(el);
      sprite.userData = { part: i };
      this.labels.add(sprite);
    });
  }

  /** No model yet (the agent hasn't made one): a glass orb on an ink plinth, the title floating above. */
  buildPlaceholder(title: string): void {
    const orb = new THREE.Mesh(new THREE.SphereGeometry(1.5, 64, 40), material("glass"));
    orb.position.y = 0.4;
    const core = new THREE.Mesh(new THREE.TorusGeometry(1.05, 0.06, 20, 96), material("black"));
    core.position.y = 0.4;
    core.rotation.x = Math.PI / 2.4;
    const plinth = new THREE.Mesh(new THREE.CylinderGeometry(1.3, 1.45, 0.35, 64), material("white"));
    plinth.position.y = -1.3;
    for (const m of [orb, core, plinth]) this.root.add(m);
    this.root.add(contactShadow(0, 0, 1.9, 0.24));
    this.parts.push({ mesh: core, base: core.position.clone(), baseRot: core.rotation.clone(), explode: new THREE.Vector3(), spin: { axis: "y", rpm: 4, center: new THREE.Vector3() }, orbit: null, group: null, label: null, detail: null });
    this.hasMotion = true;
    void title;
  }

  /** Labels hidden behind something (the centrepiece, another door) fade back, so they never float through it. */
  private raycaster = new THREE.Raycaster();
  occlude(camera: THREE.Camera): void {
    const anchor = new THREE.Vector3();
    for (const s of this.labels.children) {
      anchor.copy(s.position).divideScalar(PX_PER_UNIT);
      const door = (s as CSS3DSprite).element.dataset.door;
      const own: THREE.Object3D | undefined = door ? this.doors.get(door) : this.parts[s.userData.part]?.mesh;
      const dir = anchor.clone().sub(camera.position);
      const dist = dir.length();
      this.raycaster.set(camera.position, dir.normalize());
      this.raycaster.far = dist - 0.4;
      const hit = this.raycaster.intersectObjects(this.root.children, true).find((h) => {
        let o: THREE.Object3D | null = h.object;
        while (o) { if (o === own) return false; o = o.parent; }
        // You can see through glass, so it hides nothing.
        const m = (h.object as THREE.Mesh).material as THREE.MeshPhysicalMaterial | undefined;
        return !m || (m.name !== "hole" && !(m.transmission > 0));
      });
      (s as CSS3DSprite).element.style.opacity = hit ? "0.12" : "1";
    }
  }

  partInfo(i: number): { label: string | null; detail: string | null } | null {
    const p = this.parts[i];
    return p ? { label: p.label, detail: p.detail } : null;
  }

  highlight(i: number | null): void {
    this.parts.forEach((p, k) => {
      const m = p.mesh.material as THREE.MeshStandardMaterial;
      if (k === i) {
        if (!p.mesh.userData.own) { p.mesh.material = m.clone(); p.mesh.userData.own = true; }
        (p.mesh.material as THREE.MeshStandardMaterial).emissive?.set(0xe8590c);
        (p.mesh.material as THREE.MeshStandardMaterial).emissiveIntensity = 0.35;
      } else if (p.mesh.userData.own) {
        (p.mesh.material as THREE.MeshStandardMaterial).emissiveIntensity = 0;
      }
    });
    for (const s of this.labels.children) (s as CSS3DSprite).element.classList.toggle("on", s.userData.part === i);
  }

  // ---------- doors ----------

  buildDoors(cards: Card[], places: { x: number; y: number; z: number }[]): void {
    cards.forEach((card, i) => {
      const at = places[i]!;
      const door = new THREE.Group();
      door.position.set(at.x, at.y, at.z);
      door.lookAt(0, at.y, 0);
      // A glass ring standing upright, a dark core for doors already explored.
      const ring = new THREE.Mesh(new THREE.TorusGeometry(0.9, 0.09, 24, 64), material(card.state === "stub" ? "grey" : "black"));
      const pane = new THREE.Mesh(new THREE.CircleGeometry(0.82, 48), material("glass"));
      ring.userData = pane.userData = { kind: "door", cardId: card.id };
      door.add(ring, pane);
      if (card.childCount > 0) {
        const core = new THREE.Mesh(new THREE.SphereGeometry(0.22, 32, 20), material("black"));
        core.userData = { kind: "door", cardId: card.id };
        door.add(core);
      }
      door.userData = { kind: "door", cardId: card.id, bob: i * 0.7 };
      this.root.add(door);
      this.root.add(contactShadow(at.x, at.z, 0.9, 0.08));
      this.doors.set(card.id, door);
      // Its title under it, always facing you.
      const el = document.createElement("div");
      el.className = `dlabel${card.state === "stub" ? " stub" : ""}`;
      const title = document.createElement("b");
      title.textContent = card.title;
      const sub = document.createElement("span");
      sub.textContent = card.childCount > 0 ? t.inside(card.childCount).toUpperCase() : t.diveIn().toUpperCase();
      el.append(title, sub);
      el.dataset.door = card.id;
      const sprite = new CSS3DSprite(el);
      sprite.position.set(at.x, at.y - 1.35, at.z).multiplyScalar(PX_PER_UNIT);
      this.labels.add(sprite);
    });
  }

  door(cardId: string): THREE.Object3D | undefined {
    return this.doors.get(cardId);
  }

  // ---------- animation ----------

  update(time: number): void {
    this.exploded += (this.explodeTarget - this.exploded) * 0.1;
    const q = new THREE.Quaternion();
    for (const p of this.parts) {
      const pos = p.base.clone().addScaledVector(p.explode, this.exploded);
      p.mesh.rotation.copy(p.baseRot);
      if (p.spin) p.mesh.rotateOnWorldAxis(AXIS[p.spin.axis] ?? AXIS.y!, (time * p.spin.rpm * 2 * Math.PI) / 60);
      if (p.orbit) pos.sub(p.orbit.center).applyAxisAngle(AXIS.y!, (time * p.orbit.rpm * 2 * Math.PI) / 60).add(p.orbit.center);
      const g = p.group ? this.groups.get(p.group) : undefined;
      if (g?.spin) {
        q.setFromAxisAngle(AXIS[g.spin.axis] ?? AXIS.y!, (time * g.spin.rpm * 2 * Math.PI) / 60);
        pos.sub(g.pivot).applyQuaternion(q).add(g.pivot);
        p.mesh.quaternion.premultiply(q);
      }
      if (g?.orbit) pos.sub(g.orbit.center).applyAxisAngle(AXIS.y!, (time * g.orbit.rpm * 2 * Math.PI) / 60).add(g.orbit.center);
      p.mesh.position.copy(pos);
    }
    // Labels follow their parts.
    const world = new THREE.Vector3();
    for (const s of this.labels.children) {
      const i = s.userData.part;
      if (i === undefined) continue;
      this.parts[i]!.mesh.getWorldPosition(world);
      s.position.set(world.x, world.y + 0.35, world.z).multiplyScalar(PX_PER_UNIT);
    }
    for (const d of this.doors.values()) d.position.y += Math.sin(time * 1.1 + d.userData.bob) * 0.0016;
  }
}

/** A soft round shadow on the floor (y −2.2) under something: steadier than shadow maps, nearly free. */
let shadowTexture: THREE.Texture | null = null;
function contactShadow(x: number, z: number, r: number, opacity: number): THREE.Mesh {
  if (!shadowTexture) {
    const c = document.createElement("canvas");
    c.width = c.height = 128;
    const g = c.getContext("2d")!;
    const grad = g.createRadialGradient(64, 64, 0, 64, 64, 64);
    grad.addColorStop(0, "rgba(0,0,0,1)");
    grad.addColorStop(0.45, "rgba(0,0,0,0.55)");
    grad.addColorStop(1, "rgba(0,0,0,0)");
    g.fillStyle = grad;
    g.fillRect(0, 0, 128, 128);
    shadowTexture = new THREE.CanvasTexture(c);
  }
  const m = new THREE.Mesh(
    new THREE.PlaneGeometry(r * 2, r * 2),
    new THREE.MeshBasicMaterial({ map: shadowTexture, transparent: true, opacity, depthWrite: false, color: 0x000000 }),
  );
  m.rotation.x = -Math.PI / 2;
  m.position.set(x, -2.2, z);
  m.layers.set(COLOR_ONLY);
  m.renderOrder = -1;
  return m;
}
