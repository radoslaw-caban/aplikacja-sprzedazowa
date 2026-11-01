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
  private config: ProductConfig = {};
  private clock = new THREE.Clock();

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
    void this.clock.getDelta();
  };
}
