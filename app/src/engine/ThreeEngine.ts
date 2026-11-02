import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { TransformControls } from 'three/addons/controls/TransformControls.js';
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
  private modelHolder?: THREE.Group;
  private pointCloud?: THREE.Points;
  private gizmo?: TransformControls;
  private designGroup = new THREE.Group();
  private config: ProductConfig = {};
  /** true, gdy użytkownik ręcznie nadpisuje materiał modelu (demo kolorów) */
  forceColor = false;

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
    this.scene.add(this.designGroup);

    this.resize();
    window.addEventListener('resize', this.resize);
    this.loop();
  }

  async loadPointCloud(data: import('./RenderEngine').PointCloudData) {
    if (!this.scene) throw new Error('Engine not initialized');
    const firstCloud = !this.pointCloud;
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
    this.pointCloud.frustumCulled = false;
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
    this.setPointSize(Math.max(r / 1500, 0.002));
    if (firstCloud) {
      this.camera!.position.set(c.x + r, c.y + r * 0.6, c.z + r);
      this.controls!.target.copy(c);
      this.controls!.update();
    }
    return () => this.pointCloud?.removeFromParent();
  }

  /**
   * Wczytuje model GLB/GLTF i pozycjonuje go w chmurze punktów.
   * Model NIE jest skalowany do jednostek — zachowuje realny rozmiar w metrach,
   * żeby pasował do skanu (skan X9 jest w metrach). Kadrowanie zależy od tego,
   * czy jest już chmura: bez chmury dopasowujemy kamerę do modelu,
   * z chmurą zostawiamy widok i wstawiamy model w środek chmury.
   */
  async loadModel(url: string) {
    if (!this.scene) throw new Error('Engine not initialized');
    const gltf = await new GLTFLoader().loadAsync(url);
    return this.setModel(gltf.scene);
  }

  /** Wstawia gotowy obiekt (np. przeciągnięty plik .glb z dysku). */
  setModel(root: THREE.Object3D) {
    if (!this.scene) throw new Error('Engine not initialized');
    this.model?.removeFromParent();
    this.model = root;

    // sanityzacja bbox modelu — zły model nie może rozsypać sceny
    const box = new THREE.Box3().setFromObject(this.model);
    const size = box.getSize(new THREE.Vector3());
    const center = box.getCenter(new THREE.Vector3());
    const sane = (v: number) => Number.isFinite(v);
    if (!sane(size.x) || !sane(size.y) || !sane(size.z) || !sane(center.x) || !sane(center.y) || !sane(center.z)) {
      throw new Error('Model ma nieprawidłowe wymiary (uszkodzony plik GLB?)');
    }
    // wyśrodkuj geometrię modelu w jego własnym układzie
    this.model.position.sub(center);
    const holder = new THREE.Group();
    holder.add(this.model);
    holder.name = 'glb-holder';

    // rozmiar: jeśli jest chmura, wstaw model w jej środek; inaczej dopasuj kamerę
    if (this.pointCloud) {
      const cloudBox = this.cloudBounds();
      const cc = cloudBox.getCenter(new THREE.Vector3());
      const cloudSize = cloudBox.getSize(new THREE.Vector3());
      holder.position.copy(cc);
      // dopasuj jednostki: jeśli model jest >100× większy/mniejszy od pomieszczenia,
      // prawdopodobnie jest w mm/cm — przeskaluj do ~1/3 pomieszczenia
      const modelMax = Math.max(size.x, size.y, size.z) || 1;
      const roomMax = Math.max(cloudSize.x, cloudSize.y, cloudSize.z) || 1;
      if (modelMax / roomMax > 100) {
        holder.scale.setScalar(0.001 * 100); // mm → cm skala skanu
      } else if (roomMax / modelMax > 100) {
        holder.scale.setScalar(1000);
      }
      this.scene.add(holder);
    } else {
      this.scene.add(holder);
      const radius = (Math.max(size.x, size.y, size.z) || 1) * 1.6;
      this.camera!.position.set(radius, radius * 0.6, radius);
      this.controls!.target.set(0, 0, 0);
      this.controls!.update();
    }

    this.modelHolder = holder;
    this.attachGizmo();
    this.applyConfig(this.config);
    return () => {
      this.detachGizmo();
      holder.removeFromParent();
      this.modelHolder = undefined;
      this.model = undefined;
    };
  }

  /** Włącza gizmo (przesuwanie/obrót/skala) na wstawionym modelu. */
  setGizmoMode(mode: 'translate' | 'rotate' | 'scale' | null) {
    if (!this.gizmo) return;
    if (!mode || !this.modelHolder) {
      this.gizmo.detach();
      return;
    }
    this.gizmo.setMode(mode);
    this.gizmo.attach(this.modelHolder);
  }

  /** Ustawia rozmiar punktów chmury (w metrach) i próg culling-u dla Points. */
  private setPointSize(size: number) {
    const mat = this.pointCloud?.material as THREE.PointsMaterial | undefined;
    if (mat) mat.size = size;
  }

  /** Rozmiar chmury liczony odpornie (bez outlierów i NaN). */
  private cloudBounds(): THREE.Box3 {
    const fallback = new THREE.Box3(new THREE.Vector3(-1, -1, -1), new THREE.Vector3(1, 1, 1));
    const attr = this.pointCloud?.geometry.getAttribute('position');
    if (!attr || !attr.count) return fallback;
    const BOUND = 1e5; // skan pomieszczenia nie przekracza 100 km
    const xs: number[] = [], ys: number[] = [], zs: number[] = [];
    const step = Math.max(1, Math.floor(attr.count / 20000));
    for (let i = 0; i < attr.count; i += step) {
      const x = attr.getX(i), y = attr.getY(i), z = attr.getZ(i);
      if (Number.isFinite(x) && Number.isFinite(y) && Number.isFinite(z) &&
          Math.abs(x) < BOUND && Math.abs(y) < BOUND && Math.abs(z) < BOUND) {
        xs.push(x); ys.push(y); zs.push(z);
      }
    }
    if (!xs.length) return fallback;
    // percentyle 2%–98% odcinają pojedyncze punkty odstające (szum skanera)
    const pct = (arr: number[], p: number) => arr[Math.min(arr.length - 1, Math.floor(arr.length * p))];
    xs.sort((a, b) => a - b); ys.sort((a, b) => a - b); zs.sort((a, b) => a - b);
    const box = new THREE.Box3().set(
      new THREE.Vector3(pct(xs, 0.02), pct(ys, 0.02), pct(zs, 0.02)),
      new THREE.Vector3(pct(xs, 0.98), pct(ys, 0.98), pct(zs, 0.98)),
    );
    // ostatnia bariera: nigdy nie zwracaj zepsutego bboxa
    const s = box.getSize(new THREE.Vector3());
    const c = box.getCenter(new THREE.Vector3());
    if (!Number.isFinite(s.x + s.y + s.z) || !Number.isFinite(c.x + c.y + c.z) || s.x + s.y + s.z <= 0) {
      return fallback;
    }
    return box;
  }

  /** Ustawia kamerę na projekt (szafki), a nie na chmurę. */
  frameDesign() {
    if (!this.camera || !this.controls) return;
    const box = new THREE.Box3().setFromObject(this.designGroup);
    if (box.isEmpty()) return;
    const size = box.getSize(new THREE.Vector3());
    const center = box.getCenter(new THREE.Vector3());
    const radius = Math.max(size.x, size.y, size.z) * 0.9 || 1;
    this.camera.position.set(center.x + radius * 1.1, center.y + radius * 0.55, center.z + radius * 1.4);
    this.controls.target.copy(center);
    this.controls.update();
  }

  /** Buduje/podmienia całą scenę z listy brył (mm → metry). */
  renderBoxes(boxes: import('./RenderEngine').SceneBox[], cabinetsOrigin: { x: number; z: number } = { x: 0, z: 0 }) {
    if (!this.scene) throw new Error('Engine not initialized');
    // usuń poprzednie bryły
    for (const o of [...this.designGroup.children]) {
      o.removeFromParent();
      (o as THREE.Mesh).geometry?.dispose?.();
    }
    const mm = 0.001;
    for (const b of boxes) {
      const [sx, sy, sz] = b.size;
      const geom =
        b.shape === 'cylinder'
          ? new THREE.CylinderGeometry((sx * mm) / 2, (sx * mm) / 2, sy * mm, 16)
          : new THREE.BoxGeometry(sx * mm, sy * mm, sz * mm);
      const baseColor = new THREE.Color(b.color ?? '#c9a06a');
      const isPanel = b.kind === 'panel';
      const isFront = b.kind === 'front';
      const mat = new THREE.MeshStandardMaterial({
        color: baseColor,
        roughness: isPanel ? 0.65 : 0.45,
        metalness: b.kind === 'handle' ? 0.6 : 0.05,
        // fronty półprzezroczyste — widać wnętrze (i da się w nie kliknąć)
        transparent: isFront || (b.opacity ?? 1) < 1,
        opacity: isFront ? 0.35 : b.opacity ?? 1,
        depthWrite: !isFront,
      });
      const mesh = new THREE.Mesh(geom, mat);
      mesh.position.set(
        (b.position[0] + cabinetsOrigin.x) * mm,
        b.position[1] * mm,
        (b.position[2] + cabinetsOrigin.z) * mm,
      );
      if (b.rotationY) mesh.rotation.y = (b.rotationY * Math.PI) / 180;
      mesh.userData = { cabinetId: b.cabinetId, elementId: b.elementId, kind: b.kind, boxId: b.id };
      mesh.castShadow = false;
      mesh.receiveShadow = false;
      this.designGroup.add(mesh);
    }
    this.renderer!.render(this.scene, this.camera!);
  }

  /** Raycast: co kliknął użytkownik (cabinetId / elementId). */
  pickAt(clientX: number, clientY: number) {
    if (!this.renderer || !this.camera) return null;
    const rect = this.renderer.domElement.getBoundingClientRect();
    const ndc = new THREE.Vector2(
      ((clientX - rect.left) / rect.width) * 2 - 1,
      -((clientY - rect.top) / rect.height) * 2 + 1,
    );
    const ray = new THREE.Raycaster();
    ray.setFromCamera(ndc, this.camera);
    const hits = ray.intersectObjects(this.designGroup.children, false);
    if (!hits.length) return null;
    // pomiń fronty, jeśli pod nimi jest element wnętrza (klik ma trafiać w środek)
    const solid = hits.find((h) => {
      const k = (h.object.userData as { kind?: string }).kind;
      const hasElement = (h.object.userData as { elementId?: string }).elementId;
      return k !== 'front' || hasElement;
    });
    const hit = solid ?? hits[0];
    if (!hit) return null;
    const ud = hit.object.userData as {
      cabinetId?: string;
      elementId?: string;
      kind?: string;
    };
    return {
      cabinetId: ud.cabinetId,
      elementId: ud.elementId,
      kind: ud.kind,
      screen: { x: clientX, y: clientY },
      point: hit.point.toArray() as [number, number, number],
    };
  }

  /** Podświetla wybrany element (emissive). */
  highlightElement(elementId: string | null) {
    for (const o of this.designGroup.children) {
      const m = o as THREE.Mesh;
      const mat = m.material as THREE.MeshStandardMaterial;
      if (!mat || !mat.emissive) continue;
      const on = elementId !== null && m.userData.elementId === elementId;
      mat.emissive.setHex(on ? 0x334466 : 0x000000);
      mat.emissiveIntensity = on ? 1 : 0;
    }
  }

  disposeDesign() {
    for (const o of [...this.designGroup.children]) {
      o.removeFromParent();
      (o as THREE.Mesh).geometry?.dispose?.();
    }
  }

  /** Diagnostyka: co jest aktualnie w scenie (używane też przy testach). */
  getDebugInfo() {
    return {
      hasPointCloud: !!this.pointCloud,
      pointCloudVisible: this.pointCloud?.visible ?? false,
      hasModel: !!this.model,
      modelVisible: this.modelHolder?.visible ?? false,
      hasGizmo: !!this.gizmo,
      gizmoMode: this.config.gizmoMode,
      modelPosition: this.modelHolder
        ? [this.modelHolder.position.x, this.modelHolder.position.y, this.modelHolder.position.z]
        : null,
      modelScale: this.modelHolder?.scale.x ?? null,
      sceneChildren: this.scene?.children.length ?? 0,
    };
  }

  private attachGizmo() {
    if (!this.scene) return;
    if (!this.gizmo) {
      this.gizmo = new TransformControls(this.camera!, this.renderer!.domElement);
      this.gizmo.addEventListener('dragging-changed', (e) => {
        if (this.controls) this.controls.enabled = !(e as unknown as { value: boolean }).value;
      });
      this.scene.add(this.gizmo.getHelper());
    }
    const mode = this.config.gizmoMode ?? 'translate';
    this.gizmo.setMode(mode);
    if (this.modelHolder) this.gizmo.attach(this.modelHolder);
  }

  private detachGizmo() {
    this.gizmo?.detach();
    if (this.gizmo) this.gizmo.getHelper().removeFromParent();
    this.gizmo?.dispose();
    this.gizmo = undefined;
  }

  applyConfig(config: ProductConfig) {
    this.config = config;
    if (this.controls) this.controls.autoRotate = config.autoRotate ?? false;
    if (this.modelHolder) this.modelHolder.visible = config.showModel ?? true;
    if (config.pointSize !== undefined) this.setPointSize(config.pointSize);
    if (config.gizmoMode !== undefined && this.gizmo) this.setGizmoMode(config.gizmoMode);
    if (!this.model) return;
    this.model.traverse((obj) => {
      const mesh = obj as THREE.Mesh;
      if (!mesh.isMesh) return;
      const mat = (Array.isArray(mesh.material) ? mesh.material[0] : mesh.material) as THREE.MeshStandardMaterial;
      if (!mat) return;
      // kolory modelu zostawiamy (CabinetSense ma swoje materiały);
      // kolor z konfiguratora stosujemy tylko gdy użytkownik go zmieni
      if (config.color && this.forceColor) mat.color.set(config.color);
      if (config.metalness !== undefined && this.forceColor) mat.metalness = config.metalness;
      if (config.roughness !== undefined && this.forceColor) mat.roughness = config.roughness;
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
