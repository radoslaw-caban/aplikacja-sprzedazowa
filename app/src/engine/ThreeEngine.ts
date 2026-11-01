import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import type { ProductConfig, RenderEngine } from './RenderEngine';

/**
 * Adapter domyślnego silnika: three.js
 * Jedyne miejsce w aplikacji, gdzie istnieje import three.js.
 */
export class ThreeEngine implements RenderEngine {
  id = 'three';
  capabilities = { maxTextureSize: 4096, supportsDraco: true };

  private renderer?: THREE.WebGLRenderer;
  private scene?: THREE.Scene;
  private camera?: THREE.PerspectiveCamera;
  private controls?: OrbitControls;
  private raf = 0;
  private model?: THREE.Object3D;
  private pointCloud?: THREE.Points;
  private config: ProductConfig = {};

  async init(canvas: HTMLCanvasElement) {
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: false });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;

    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color('#111318');

    this.camera = new THREE.PerspectiveCamera(45, 1, 0.1, 100);
    this.camera.position.set(2.4, 1.6, 3.2);

    const pmrem = new THREE.PMREMGenerator(this.renderer);
    this.scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;

    const dir = new THREE.DirectionalLight(0xffffff, 1.4);
    dir.position.set(4, 6, 4);
    this.scene.add(dir, new THREE.AmbientLight(0xffffff, 0.4));

    this.controls = new OrbitControls(this.camera, canvas);
    this.controls.enableDamping = true;
    this.controls.autoRotateSpeed = 2.0;

    this.resize();
    window.addEventListener('resize', this.resize);
    this.loop();
  }

  async loadPointCloud(data: import('./RenderEngine').PointCloudData) {
    if (!this.scene) throw new Error('Engine not initialized');
    this.pointCloud?.removeFromParent();
    // filtruj punkty z NaN/Inf (np. "invalid" z CloudCompare) — inaczej
    // computeBoundingSphere zwraca NaN i frustum culling się wysypuje
    let positions = data.positions;
    let colors = data.colors;
    let n = positions.length / 3;
    let bad = 0;
    for (let i = 0; i < n; i++) {
      if (!Number.isFinite(positions[i * 3]) || !Number.isFinite(positions[i * 3 + 1]) || !Number.isFinite(positions[i * 3 + 2])) bad++;
    }
    if (bad > 0) {
      const p2 = new Float32Array((n - bad) * 3);
      const c2 = colors ? new Uint8Array((n - bad) * 3) : undefined;
      let j = 0;
      for (let i = 0; i < n; i++) {
        const x = positions[i * 3], y = positions[i * 3 + 1], z = positions[i * 3 + 2];
        if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(z)) continue;
        p2[j * 3] = x; p2[j * 3 + 1] = y; p2[j * 3 + 2] = z;
        if (c2 && colors) { c2[j * 3] = colors[i * 3]; c2[j * 3 + 1] = colors[i * 3 + 1]; c2[j * 3 + 2] = colors[i * 3 + 2]; }
        j++;
      }
      positions = p2; colors = c2; n = j;
    }
    const geom = new THREE.BufferGeometry();
    geom.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    const mat = data.colors
      ? new THREE.PointsMaterial({ size: 0.01, vertexColors: true, sizeAttenuation: true })
      : new THREE.PointsMaterial({ size: 0.01, color: 0x9fd8ff, sizeAttenuation: true });
    if (colors) {
      const col = new Float32Array(colors.length);
      for (let i = 0; i < colors.length; i++) col[i] = colors[i] / 255;
      geom.setAttribute('color', new THREE.BufferAttribute(col, 3));
    }
    this.pointCloud = new THREE.Points(geom, mat);
    this.scene.add(this.pointCloud);
    // kamera na bbox — policzony z przefiltrowanych danych (bbox z pliku może być NaN)
    let m0 = Infinity, m1 = Infinity, m2 = Infinity, M0 = -Infinity, M1 = -Infinity, M2 = -Infinity;
    for (let i = 0; i < n; i++) {
      const x = positions[i * 3], y = positions[i * 3 + 1], z = positions[i * 3 + 2];
      if (x < m0) m0 = x; if (y < m1) m1 = y; if (z < m2) m2 = z;
      if (x > M0) M0 = x; if (y > M1) M1 = y; if (z > M2) M2 = z;
    }
    const c = new THREE.Vector3((m0 + M0) / 2, (m1 + M1) / 2, (m2 + M2) / 2);
    const r = Math.max(M0 - m0, M1 - m1, M2 - m2) || 1;
    this.camera!.position.set(c.x + r, c.y + r * 0.6, c.z + r);
    this.controls!.target.copy(c);
    this.controls!.update();
    return () => this.pointCloud?.removeFromParent();
  }

  async loadModel(url: string) {
    if (!this.scene) throw new Error('Engine not initialized');
    const gltf = await new GLTFLoader().loadAsync(url);
    this.model?.removeFromParent();
    this.model = gltf.scene;
    // normalizacja rozmiaru do ~1.5 jednostki
    const box = new THREE.Box3().setFromObject(this.model);
    const size = box.getSize(new THREE.Vector3()).length() || 1;
    this.model.scale.setScalar(1.5 / size);
    box.setFromObject(this.model);
    this.model.position.y -= box.getCenter(new THREE.Vector3()).y;
    this.scene.add(this.model);
    this.applyConfig(this.config);
    return () => this.model?.removeFromParent();
  }

  applyConfig(config: ProductConfig) {
    this.config = config;
    if (this.controls) this.controls.autoRotate = config.autoRotate ?? true;
    if (!this.model) return;
    this.model.traverse((obj) => {
      const mesh = obj as THREE.Mesh;
      if (!mesh.isMesh) return;
      const mat = (Array.isArray(mesh.material) ? mesh.material[0] : mesh.material) as THREE.MeshStandardMaterial;
      if (!mat) return;
      if (config.color) mat.color.set(config.color);
      if (config.metalness !== undefined) mat.metalness = config.metalness;
      if (config.roughness !== undefined) mat.roughness = config.roughness;
    });
  }

  async screenshot(): Promise<Blob> {
    return new Promise((resolve) =>
      this.renderer!.domElement.toBlob((b) => resolve(b!), 'image/png'),
    );
  }

  dispose() {
    cancelAnimationFrame(this.raf);
    window.removeEventListener('resize', this.resize);
    this.renderer?.dispose();
  }

  private resize = () => {
    if (!this.renderer || !this.camera) return;
    const w = this.renderer.domElement.clientWidth || window.innerWidth;
    const h = this.renderer.domElement.clientHeight || window.innerHeight;
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
  };

  private loop = () => {
    this.raf = requestAnimationFrame(this.loop);
    this.controls?.update();
    // delikatne "oddychanie" obiektu, gdy model istnieje
    if (this.model && this.config.autoRotate !== false) {
      // obrót sceny realizuje OrbitControls.autoRotate
    }
    this.renderer?.render(this.scene!, this.camera!);
  };
}
