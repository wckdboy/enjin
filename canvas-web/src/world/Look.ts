import * as THREE from "three";
import { RoomEnvironment } from "three/examples/jsm/environments/RoomEnvironment.js";

/** Things drawn in colour but left out of the ink pass (contact shadows, panel holes). */
export const COLOR_ONLY = 1;

/**
 * ENJIN's look in 3D: a white studio (soft room light, a shadow catcher, a
 * pale gradient, soft contact shadows), matte whites and greys, real glass, and ink: every
 * silhouette and crease gets a fine black line, found from depth and normal
 * edges in a second pass. A touch of grain, like the print shader on pictures.
 *
 * Per frame: colour pass (MSAA) -> normal+depth pass -> composite to screen.
 */
export class Look {
  readonly renderer: THREE.WebGLRenderer;
  private color: THREE.WebGLRenderTarget;
  private normals: THREE.WebGLRenderTarget;
  private normalMaterial = new THREE.MeshNormalMaterial();
  private quad: THREE.Mesh<THREE.PlaneGeometry, THREE.ShaderMaterial>;
  private post = new THREE.Scene();
  private postCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);

  constructor(private canvas: HTMLCanvasElement, scene: THREE.Scene) {
    // Transparent: the backdrop and the glass panels (CSS, under this canvas) show through,
    // and 3D things in front of a panel still cover it (see Panels' holes).
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: false, alpha: true, powerPreference: "high-performance" });
    this.renderer.setClearColor(0x000000, 0);
    this.renderer.setPixelRatio(Math.min(2, devicePixelRatio || 1));
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.05;

    // Studio light: a soft room for reflections, a key light, a gentle fill. No shadow maps:
    // contact shadows (WorldView) are steadier across GPUs and cheaper on the battery.
    const pmrem = new THREE.PMREMGenerator(this.renderer);
    scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
    scene.environmentIntensity = 0.85;
    const key = new THREE.DirectionalLight(0xffffff, 1.6);
    key.position.set(-6, 12, 8);
    scene.add(key, new THREE.HemisphereLight(0xffffff, 0xe7e7e3, 0.6));

    // The pale backdrop is CSS, behind everything (world.css).

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
    const pr = this.renderer.getPixelRatio();
    this.renderer.setSize(w, h, false);
    this.color.setSize(Math.round(w * pr), Math.round(h * pr));
    this.normals.setSize(Math.round(w * pr), Math.round(h * pr));
    this.quad.material.uniforms.texel!.value.set(1 / (w * pr), 1 / (h * pr));
  }

  render(scene: THREE.Scene, camera: THREE.PerspectiveCamera, t: number): void {
    const r = this.renderer;
    const u = this.quad.material.uniforms;
    u.near!.value = camera.near; u.far!.value = camera.far; u.time!.value = t % 10;
    // 1. colour (tone mapped later on screen; keep linear here).
    camera.layers.enable(COLOR_ONLY);
    r.toneMapping = THREE.NoToneMapping;
    r.setRenderTarget(this.color);
    r.setClearColor(0x000000, 0);
    r.clear();
    r.render(scene, camera);
    // 2. normals + depth for the ink, without the colour-only things.
    camera.layers.disable(COLOR_ONLY);
    scene.overrideMaterial = this.normalMaterial;
    r.setRenderTarget(this.normals);
    r.setClearColor(0x000000, 0);
    r.clear();
    r.render(scene, camera);
    scene.overrideMaterial = null;
    // 3. composite to the screen, tone mapped.
    r.toneMapping = THREE.ACESFilmicToneMapping;
    r.setRenderTarget(null);
    r.setClearColor(0x000000, 0);
    r.clear();
    r.render(this.post, this.postCam);
  }
}
