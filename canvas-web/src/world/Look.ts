import * as THREE from "three";
import { RoomEnvironment } from "three/examples/jsm/environments/RoomEnvironment.js";

/** Things drawn in colour but left out of the ink pass (contact shadows). */
export const COLOR_ONLY = 1;

/**
 * ENJIN's look in 3D: soft studio light (each model carries its own), real
 * glass, matte whites and greys, and ink: every silhouette and crease gets a
 * fine black line, found from depth and normal edges in a second pass. A touch
 * of grain, like the print shader on pictures.
 *
 * One transparent canvas over the plane draws every model on screen into its
 * own rectangle (wherever the plane has put it, at any zoom), then inks them
 * all at once: colour pass (MSAA) -> normal+depth pass -> composite.
 */
export class Look {
  readonly renderer: THREE.WebGLRenderer;
  readonly environment: THREE.Texture;
  private color: THREE.WebGLRenderTarget;
  private normals: THREE.WebGLRenderTarget;
  private normalMaterial = new THREE.MeshNormalMaterial();
  private quad: THREE.Mesh<THREE.PlaneGeometry, THREE.ShaderMaterial>;
  private post = new THREE.Scene();
  private postCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  private size = { w: 1, h: 1 };

  constructor(canvas: HTMLCanvasElement) {
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: false, alpha: true, powerPreference: "high-performance" });
    this.renderer.setClearColor(0x000000, 0);
    this.renderer.setPixelRatio(Math.min(2, devicePixelRatio || 1));
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.05;
    this.renderer.autoClear = false;
    // A soft room for reflections, shared by every model.
    const pmrem = new THREE.PMREMGenerator(this.renderer);
    this.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;

    this.color = new THREE.WebGLRenderTarget(1, 1, { samples: 4, type: THREE.HalfFloatType });
    this.normals = new THREE.WebGLRenderTarget(1, 1, { depthTexture: new THREE.DepthTexture(1, 1) });
    this.quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), new THREE.ShaderMaterial({
      uniforms: {
        tColor: { value: this.color.texture }, tNormal: { value: this.normals.texture }, tDepth: { value: this.normals.depthTexture },
        texel: { value: new THREE.Vector2() }, near: { value: 0.1 }, far: { value: 200 }, time: { value: 0 },
      },
      transparent: true, premultipliedAlpha: true, blending: THREE.NoBlending,
      vertexShader: "varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }",
      fragmentShader: `
        uniform sampler2D tColor, tNormal, tDepth; uniform vec2 texel; uniform float near, far, time; varying vec2 vUv;
        float lin(float d){ float z = d * 2.0 - 1.0; return (2.0 * near * far) / (far + near - z * (far - near)); }
        float depthAt(vec2 uv){ return lin(texture2D(tDepth, uv).r); }
        vec3 normalAt(vec2 uv){ return texture2D(tNormal, uv).rgb; }
        float hash(vec2 p){ return fract(sin(dot(p, vec2(12.9898, 78.233)) + time) * 43758.5453); }
        void main(){
          vec4 col = texture2D(tColor, vUv); // premultiplied; alpha 0 where there's nothing (or a panel's hole)
          float d = depthAt(vUv); vec3 n = normalAt(vUv);
          float edge = 0.0;
          for (int i = 0; i < 4; i++) {
            vec2 o = (i == 0 ? vec2(1.0, 0.0) : i == 1 ? vec2(-1.0, 0.0) : i == 2 ? vec2(0.0, 1.0) : vec2(0.0, -1.0)) * texel * 1.25;
            float dd = abs(depthAt(vUv + o) - d) / max(d, 0.001);
            vec3 nn = normalAt(vUv + o);
            edge = max(edge, smoothstep(0.012, 0.03, dd));
            edge = max(edge, smoothstep(0.28, 0.5, length(nn - n)) * step(0.001, length(n)));
          }
          vec3 ink = vec3(0.043, 0.043, 0.047);
          float e = edge * 0.82;
          float a = col.a + e * (1.0 - col.a);
          vec3 c = col.rgb * (1.0 - e) + ink * e;
          c += (hash(vUv * 731.0) - 0.5) * 0.018 * a;
          gl_FragColor = vec4(c, a);
          #include <colorspace_fragment>
        }`,
    }));
    this.post.add(this.quad);
  }

  resize(w: number, h: number): void {
    this.size = { w, h };
    const pr = this.renderer.getPixelRatio();
    this.renderer.setSize(w, h, false);
    this.color.setSize(Math.round(w * pr), Math.round(h * pr));
    this.normals.setSize(Math.round(w * pr), Math.round(h * pr));
    this.quad.material.uniforms.texel!.value.set(1 / (w * pr), 1 / (h * pr));
  }

  /**
   * Draw these models, each into its screen rectangle (CSS px; it may reach
   * past the screen when zoomed in: only the visible part is drawn).
   */
  render(views: { scene: THREE.Scene; camera: THREE.PerspectiveCamera; rect: { x: number; y: number; w: number; h: number } }[], t: number): void {
    const r = this.renderer;
    const { w: W, h: H } = this.size;
    const u = this.quad.material.uniforms;
    u.time!.value = t % 10;
    const visible = views.flatMap((v) => {
      const x0 = Math.max(0, v.rect.x), y0 = Math.max(0, v.rect.y);
      const x1 = Math.min(W, v.rect.x + v.rect.w), y1 = Math.min(H, v.rect.y + v.rect.h);
      return x1 - x0 >= 2 && y1 - y0 >= 2 ? [{ ...v, vis: { x: x0, y: y0, w: x1 - x0, h: y1 - y0 } }] : [];
    });
    const pr = r.getPixelRatio();
    const pass = (target: THREE.WebGLRenderTarget, override: THREE.Material | null) => {
      target.viewport.set(0, 0, target.width, target.height);
      r.setRenderTarget(target);
      r.setClearColor(0x000000, 0);
      r.clear();
      for (const v of visible) {
        const c = v.camera;
        // The whole model is rect-sized; draw just the part on screen. The viewport lives on the
        // target (physical px), so three's glass (transmission) pass, which re-binds it, keeps it.
        // No scissor: it would also clip the MSAA resolve, leaving stale pixels outside it.
        c.setViewOffset(v.rect.w, v.rect.h, v.vis.x - v.rect.x, v.vis.y - v.rect.y, v.vis.w, v.vis.h);
        c.updateProjectionMatrix();
        if (override) c.layers.disable(COLOR_ONLY);
        else c.layers.enable(COLOR_ONLY);
        const x = Math.round(v.vis.x * pr), y = Math.round((H - v.vis.y - v.vis.h) * pr);
        const w = Math.round(v.vis.w * pr), h = Math.round(v.vis.h * pr);
        target.viewport.set(x, y, w, h);
        r.setRenderTarget(target);
        v.scene.overrideMaterial = override;
        r.render(v.scene, c);
        v.scene.overrideMaterial = null;
        c.clearViewOffset();
      }
      target.viewport.set(0, 0, target.width, target.height);
    };
    if (visible[0]) { u.near!.value = visible[0].camera.near; u.far!.value = visible[0].camera.far; }
    // 1. colour (tone mapped later on screen; keep linear here). 2. normals + depth for the ink.
    r.toneMapping = THREE.NoToneMapping;
    pass(this.color, null);
    pass(this.normals, this.normalMaterial);
    // 3. composite to the screen, tone mapped.
    r.toneMapping = THREE.ACESFilmicToneMapping;
    r.setRenderTarget(null);
    r.setViewport(0, 0, W, H);
    r.setClearColor(0x000000, 0);
    r.clear();
    if (visible.length) r.render(this.post, this.postCam);
  }
}
