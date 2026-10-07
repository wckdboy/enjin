import * as THREE from "three";
import { COLOR_ONLY } from "./Look";
import { geometry, material, moleculeParts, vec, type V3 } from "./library";

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
 * A 3D model standing on the plane: its own little studio (scene, lights,
 * camera), drawn by Look into the rectangle the plane gives it. A model3d spec
 * becomes meshes from the library; without one, a glass orb holds the place.
 * Turn it with a finger, tap a part to read it, explode it to see inside.
 */
export class ModelView {
  readonly scene = new THREE.Scene();
  readonly camera = new THREE.PerspectiveCamera(30, 4 / 3, 0.1, 100);
  private root = new THREE.Group();
  private parts: Part[] = [];
  private groups = new Map<string, { pivot: THREE.Vector3; spin: Motion; orbit: Motion }>();
  private exploded = 0;
  explodeTarget = 0;
  hasExplode = false;
  hasMotion = false;
  az = 0.55;
  el = 0.32;
  private target = new THREE.Vector3(0, 0.3, 0);
  private dist = 12.5;
  private raycaster = new THREE.Raycaster();

  constructor(spec: Record<string, unknown> | null, env: THREE.Texture) {
    this.scene.environment = env;
    this.scene.environmentIntensity = 0.85;
    const key = new THREE.DirectionalLight(0xffffff, 1.6);
    key.position.set(-6, 12, 8);
    this.scene.add(key, new THREE.HemisphereLight(0xffffff, 0xe7e7e3, 0.6), this.root);
    if (spec) this.build(spec);
    else this.placeholder();
  }

  // ---------- building ----------

  private build(spec: any): void {
    const raw: any[] = [...(Array.isArray(spec?.parts) ? spec.parts : []).slice(0, 120), ...moleculeParts(spec)];
    for (const [name, g] of Object.entries(spec?.groups ?? {})) {
      const gg = g as any;
      this.groups.set(name, { pivot: new THREE.Vector3(...vec(gg?.pivot, [0, 0, 0])), spin: motion(gg?.spin), orbit: motion(gg?.orbit) });
    }
    const model = new THREE.Group();
    for (const p of raw) {
      const mesh = new THREE.Mesh(geometry(p), material(p.color));
      mesh.position.set(...vec(p.position, [0, 0, 0]));
      mesh.rotation.set(...(vec(p.rotation, [0, 0, 0]).map((d) => (d * Math.PI) / 180) as V3));
      mesh.userData = { part: this.parts.length };
      model.add(mesh);
      this.parts.push({
        mesh, base: mesh.position.clone(), baseRot: mesh.rotation.clone(), explode: new THREE.Vector3(...vec(p.explode, [0, 0, 0])),
        spin: motion(p.spin), orbit: motion(p.orbit), group: p.group ? String(p.group) : null,
        label: p.label ? String(p.label).slice(0, 32) : null, detail: p.detail ? String(p.detail).slice(0, 220) : null,
      });
    }
    this.hasExplode = this.parts.some((p) => p.explode.lengthSq() > 0);
    this.hasMotion = this.parts.some((p) => p.spin || p.orbit) || [...this.groups.values()].some((g) => g.spin || g.orbit);
    // Fit: the model fills a sphere of radius 2.4 at the centre, resting just above the floor.
    const box = new THREE.Box3().setFromObject(model);
    const size = box.getSize(new THREE.Vector3());
    const scale = 4.8 / Math.max(size.x, size.y, size.z, 0.001);
    model.position.copy(box.getCenter(new THREE.Vector3())).multiplyScalar(-scale);
    model.scale.setScalar(scale);
    model.position.y += 0.4;
    this.root.add(model);
    this.root.add(contactShadow(Math.min(2.3, Math.max(size.x, size.z) * scale * 0.5), 0.22));
  }

  /** No model yet: a glass orb with a slowly turning ink ring, on a white plinth. */
  private placeholder(): void {
    const orb = new THREE.Mesh(new THREE.SphereGeometry(1.5, 64, 40), material("glass"));
    orb.position.y = 0.4;
    const core = new THREE.Mesh(new THREE.TorusGeometry(1.05, 0.06, 20, 96), material("black"));
    core.position.y = 0.4;
    core.rotation.x = Math.PI / 2.4;
    const plinth = new THREE.Mesh(new THREE.CylinderGeometry(1.3, 1.45, 0.35, 64), material("white"));
    plinth.position.y = -1.3;
    this.root.add(orb, core, plinth, contactShadow(1.6, 0.24));
    this.parts.push({ mesh: core, base: core.position.clone(), baseRot: core.rotation.clone(), explode: new THREE.Vector3(), spin: { axis: "y", rpm: 4, center: new THREE.Vector3() }, orbit: null, group: null, label: null, detail: null });
    this.hasMotion = true;
  }

  dispose(): void {
    this.scene.traverse((o) => {
      const m = o as THREE.Mesh;
      m.geometry?.dispose();
      const mats = Array.isArray(m.material) ? m.material : m.material ? [m.material] : [];
      // Library materials are shared; only dispose our own clones.
      for (const mat of mats) if (m.userData.own || mat.userData?.own) mat.dispose();
    });
  }

  // ---------- the camera ----------

  /** Aim the camera for a rectangle of this aspect. */
  aim(aspect: number): void {
    const c = this.camera;
    c.aspect = aspect;
    // Fit a sphere of radius ~3 around the target, whichever side is tighter.
    const vf = (c.fov * Math.PI) / 360;
    const hf = Math.atan(Math.tan(vf) * aspect);
    this.dist = 3.1 / Math.sin(Math.min(vf, hf));
    c.position.set(
      this.target.x + this.dist * Math.cos(this.el) * Math.sin(this.az),
      this.target.y + this.dist * Math.sin(this.el),
      this.target.z + this.dist * Math.cos(this.el) * Math.cos(this.az),
    );
    c.lookAt(this.target);
    c.updateMatrixWorld();
  }

  turn(dx: number, dy: number): void {
    this.az -= dx * 0.008;
    this.el = Math.max(-0.2, Math.min(1.3, this.el + dy * 0.006));
  }

  // ---------- parts ----------

  /** The labelled part under a point (NDC in the model's rectangle), or null. */
  pick(nx: number, ny: number): number | null {
    this.camera.clearViewOffset();
    this.raycaster.setFromCamera(new THREE.Vector2(nx, ny), this.camera);
    const hit = this.raycaster.intersectObjects(this.parts.map((p) => p.mesh), false)[0];
    const i = hit?.object.userData.part as number | undefined;
    return i === undefined ? null : i;
  }

  partInfo(i: number): { label: string | null; detail: string | null } | null {
    const p = this.parts[i];
    return p ? { label: p.label, detail: p.detail } : null;
  }

  /** Labelled parts, with where they are in the model's rectangle (0..1) and whether something hides them. */
  labels(occlusion: boolean): { i: number; label: string; u: number; v: number; hidden: boolean }[] {
    this.camera.clearViewOffset();
    const out: { i: number; label: string; u: number; v: number; hidden: boolean }[] = [];
    const at = new THREE.Vector3();
    this.parts.forEach((p, i) => {
      if (!p.label) return;
      p.mesh.getWorldPosition(at);
      let hidden = false;
      if (occlusion) {
        const dir = at.clone().sub(this.camera.position);
        const dist = dir.length();
        this.raycaster.set(this.camera.position, dir.normalize());
        this.raycaster.far = dist - 0.25;
        hidden = this.raycaster.intersectObjects(this.parts.map((q) => q.mesh), false).some((h) => {
          if (h.object === p.mesh) return false;
          const m = (h.object as THREE.Mesh).material as THREE.MeshPhysicalMaterial;
          return !(m.transmission > 0); // you can see through glass
        });
        this.raycaster.far = Infinity;
      }
      at.y += 0.3;
      at.project(this.camera);
      out.push({ i, label: p.label, u: (at.x + 1) / 2, v: (1 - at.y) / 2, hidden });
    });
    return out;
  }

  highlight(i: number | null): void {
    this.parts.forEach((p, k) => {
      if (k === i) {
        if (!p.mesh.userData.own) { p.mesh.material = (p.mesh.material as THREE.Material).clone(); p.mesh.userData.own = true; }
        (p.mesh.material as THREE.MeshStandardMaterial).emissive?.set(0xe8590c);
        (p.mesh.material as THREE.MeshStandardMaterial).emissiveIntensity = 0.35;
      } else if (p.mesh.userData.own) {
        (p.mesh.material as THREE.MeshStandardMaterial).emissiveIntensity = 0;
      }
    });
  }

  // ---------- animation ----------

  /** True while something is still settling (an explode in progress). */
  update(time: number): boolean {
    const settling = Math.abs(this.explodeTarget - this.exploded) > 0.001;
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
    return settling;
  }
}

/** A soft round shadow on the floor (y −2.2): steadier than shadow maps, nearly free. */
let shadowTexture: THREE.Texture | null = null;
function contactShadow(r: number, opacity: number): THREE.Mesh {
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
  m.material.userData.own = true;
  m.rotation.x = -Math.PI / 2;
  m.position.y = -2.2;
  m.layers.set(COLOR_ONLY);
  m.renderOrder = -1;
  return m;
}
