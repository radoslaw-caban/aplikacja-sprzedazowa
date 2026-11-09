import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { TransformControls } from 'three/addons/controls/TransformControls.js';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { PostFX } from './PostFX';
import { RGBELoader } from 'three/addons/loaders/RGBELoader.js';
import { texturesFor, materialProps, textureScale, matKindFor, bumpScale, normalMapFor, roughnessMapFor } from './textures';
import type { ProductConfig, RenderEngine } from './RenderEngine';

/**
 * Adapter domyślnego silnika: three.js
 * Jedyne miejsce w aplikacji, gdzie istnieje import three.js.
 */
export class ThreeEngine implements RenderEngine {
  id = 'three';
  capabilities = { maxTextureSize: 4096, supportsDraco: true };

  /** tryb renderowania: pełny PBR albo szkic techniczny (same krawędzie) */
  private renderMode: 'pbr' | 'wireframe';

  constructor(renderMode: 'pbr' | 'wireframe' = 'pbr') {
    this.renderMode = renderMode;
  }

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
  private roomGroup = new THREE.Group();
  private guideGroup = new THREE.Group();
  private config: ProductConfig = {};
  /** mnożnik oddalenia kamery (z ustawień programu) */
  private distanceMul = 1;
  private autoRotateDesign = false;
  private frontsVisible = true;
  /** true, gdy użytkownik ręcznie nadpisuje materiał modelu (demo kolorów) */
  forceColor = false;
  private matCache = new Map<string, THREE.Material>();
  private post?: PostFX;
  /** tryb materiałów: pbr (tekstury) / flat (płaskie) / wire (szkic) */
  private materialMode: 'pbr' | 'flat' | 'wire' = 'pbr';
  private sunLight?: THREE.DirectionalLight;
  private hemiLight?: THREE.HemisphereLight;
  /** 'low' | 'medium' | 'high' — wpływa na AO/bloom */
  private quality: 'low' | 'medium' | 'high' = 'high';
  private frameTimes: number[] = [];
  private lastFrame = 0;
  private degraded = 0;
  /** ściany półprzezroczyste — widok roboczy wnętrza */
  private wallGhost = true;

  /**
   * Niebo equirect: gradient zenitu, horyzont, ciepły pas przy horyzoncie
   * i rozbłysk słońca. Ta sama tekstura jest tłem i źródłem IBL (odbicia).
   */
  private skyTexture(): THREE.Texture {
    const w = 1024;
    const h = 512;
    const c = document.createElement('canvas');
    c.width = w;
    c.height = h;
    const ctx = c.getContext('2d')!;

    // gradient pionowy: zenit → horyzont → grunt
    const g = ctx.createLinearGradient(0, 0, 0, h);
    g.addColorStop(0.0, '#4f7fae');
    g.addColorStop(0.32, '#8fb4d2');
    g.addColorStop(0.5, '#dbe7ef');
    g.addColorStop(0.52, '#e8e3d6');
    g.addColorStop(0.75, '#a89b86');
    g.addColorStop(1.0, '#6b6355');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, w, h);

    // słońce: jasny dysk + poświata
    const sunX = w * 0.32;
    const sunY = h * 0.26;
    const glow = ctx.createRadialGradient(sunX, sunY, 1, sunX, sunY, h * 0.55);
    glow.addColorStop(0, 'rgba(255,252,240,1)');
    glow.addColorStop(0.035, 'rgba(255,246,214,0.95)');
    glow.addColorStop(0.12, 'rgba(255,238,196,0.35)');
    glow.addColorStop(0.4, 'rgba(255,235,190,0.10)');
    glow.addColorStop(1, 'rgba(255,235,190,0)');
    ctx.fillStyle = glow;
    ctx.fillRect(0, 0, w, h);

    // delikatne chmury — pasma o niskim kontraście
    for (let i = 0; i < 26; i++) {
      const cx = Math.random() * w;
      const cy = h * (0.18 + Math.random() * 0.26);
      const rw = 90 + Math.random() * 260;
      const rh = 14 + Math.random() * 34;
      const cg = ctx.createRadialGradient(cx, cy, 1, cx, cy, rw);
      cg.addColorStop(0, `rgba(255,255,255,${0.10 + Math.random() * 0.12})`);
      cg.addColorStop(1, 'rgba(255,255,255,0)');
      ctx.save();
      ctx.translate(cx, cy);
      ctx.scale(1, rh / rw);
      ctx.fillStyle = cg;
      ctx.beginPath();
      ctx.arc(0, 0, rw, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();
    }

    const t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.SRGBColorSpace;
    t.mapping = THREE.EquirectangularReflectionMapping;
    return t;
  }

  /**
   * Materiał PBR dla bryły: tekstura proceduralna w realnej skali (m),
   * odpowiednia chropowatość i metaliczność. Cache po rodzaju + kolorze.
   */
  private materialFor(b: import('./RenderEngine').SceneBox): THREE.Material {
    const wire = this.renderMode === 'wireframe' || this.materialMode === 'wire';
    if (wire) {
      return new THREE.MeshStandardMaterial({
        color: new THREE.Color(b.color ?? '#c9a06a'),
        roughness: 0.6,
        metalness: 0.02,
        transparent: true,
        opacity: 0.1,
      });
    }

    const kind = b.mat ?? matKindFor(b.kind);
    const key = `${kind}|${b.color ?? ''}|${b.opacity ?? 1}`;
    const cached = this.matCache.get(key);
    if (cached) return cached;

    // tryb techniczny: płaskie kolory bez tekstur
    if (this.materialMode === 'flat') {
      return new THREE.MeshStandardMaterial({
        color: new THREE.Color(b.color ?? '#d9d4c9'),
        roughness: 0.85,
        metalness: 0.02,
        flatShading: false,
      });
    }
    const props = materialProps(kind);
    const tex = texturesFor(kind);
    const [, sy, sz] = b.size;
    // skala tekstury: metry / metr-na-kafel
    const scaleM = textureScale(kind);
    const map = tex.map.clone();
    map.needsUpdate = true;
    map.repeat.set(
      Math.max(0.25, (Math.max(b.size[0], sz) / 1000) / scaleM),
      Math.max(0.25, (Math.max(sy, sz) / 1000) / scaleM),
    );
    const bump = tex.bump?.clone();
    if (bump) {
      bump.needsUpdate = true;
      bump.repeat.copy(map.repeat);
    }
    const normal = normalMapFor(kind);
    const rough = roughnessMapFor(kind);

    const useTex = kind !== 'glass' && kind !== 'metal';
    const mat = new THREE.MeshStandardMaterial({
      color: new THREE.Color(b.color ?? props.color),
      roughness: props.roughness,
      metalness: props.metalness,
      map: useTex ? map : undefined,
      bumpMap: useTex && bump ? bump : undefined,
      bumpScale: bumpScale(kind),
      normalMap: useTex ? normal.clone() : undefined,
      roughnessMap: useTex ? rough.clone() : undefined,
      normalScale: new THREE.Vector2(0.45, 0.45),
      envMapIntensity: 1.15,
      emissive: b.emissive ? new THREE.Color(b.emissive) : new THREE.Color('#000000'),
      emissiveIntensity: b.emissiveIntensity ?? (b.emissive ? 2 : 0),
    });
    // powtórzenia map faktury zgodne z mapą koloru
    if (mat.normalMap) mat.normalMap.repeat.copy(map.repeat);
    if (mat.roughnessMap) mat.roughnessMap.repeat.copy(map.repeat);
    this.matCache.set(key, mat);
    return mat;
  }

  async init(canvas: HTMLCanvasElement) {
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: false });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.06;
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;

    this.scene = new THREE.Scene();
    this.scene.background = this.skyTexture();
    this.scene.fog = new THREE.Fog('#dfe7ee', 70, 260);

    this.camera = new THREE.PerspectiveCamera(45, 1, 0.05, 200);
    this.camera.position.set(2.4, 1.6, 3.2);

    const pmrem = new THREE.PMREMGenerator(this.renderer);
    // IBL z tego samego nieba — odbicia odpowiadają scenerii (nie „studyjna szara puszka")
    const envSrc = this.skyTexture();
    this.scene.environment = pmrem.fromEquirectangular(envSrc).texture;
    this.scene.environmentIntensity = 1.0;

    // słońce z cieniami
    const sun = new THREE.DirectionalLight(0xfff6e8, 3.1);
    sun.position.set(-6, 15, 9);
    sun.castShadow = true;
    sun.shadow.mapSize.set(2048, 2048);
    sun.shadow.bias = -0.0006;
    sun.shadow.normalBias = 0.035;
    const cam = sun.shadow.camera;
    cam.left = -18; cam.right = 18; cam.top = 18; cam.bottom = -18;
    cam.near = 1; cam.far = 60;
    cam.updateProjectionMatrix();

    // światło niebios (góra chłodna, dół ciepły od gruntu)
    const hemi = new THREE.HemisphereLight(0xe8f2ff, 0x8a7f6a, 0.85);
    this.sunLight = sun;
    this.hemiLight = hemi;
    this.scene.add(sun, hemi, new THREE.AmbientLight(0xffffff, 0.12));

    this.controls = new OrbitControls(this.camera, canvas);
    this.controls.enableDamping = true;
    this.controls.autoRotateSpeed = 2.0;
    // przybliżanie pod kursorem — model nie wpada w ekran przy zoomie
    this.controls.zoomToCursor = true;
    this.controls.minDistance = 0.05;
    this.controls.maxDistance = 60;
    this.controls.zoomSpeed = 0.9;
    this.scene.add(this.designGroup);
    this.scene.add(this.roomGroup);
    this.scene.add(this.guideGroup);

    this.resize();
    // post-processing: AO + bloom + korekcja + SMAA
    try {
      this.post = new PostFX(this.renderer, this.scene, this.camera);
      this.post.setSize(this.renderer.domElement.clientWidth || 1, this.renderer.domElement.clientHeight || 1, this.renderer.getPixelRatio());
      // na softwarowym renderze (bez GPU) efekty ciężkie od razu wyłączone
      this.setQuality(this.isSoftRenderer() ? 'low' : 'high');
    } catch (e) {
      console.warn('PostFX niedostępny, render bezpośredni', e);
      this.post = undefined;
    }
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

  /**
   * Ustawienia widoku z panelu ustawień: oddalenie (mnożnik), FOV, obrót projektu,
   * widoczność frontów. Stosowane we wszystkich widokach (układ / wnętrze / szuflada).
   */
  setViewSettings(o: { distance?: number; fov?: number; autoRotate?: boolean; frontsVisible?: boolean }) {
    const prevDistance = this.distanceMul;
    if (o.distance !== undefined) this.distanceMul = o.distance;
    if (o.fov !== undefined && this.camera) {
      this.camera.fov = o.fov;
      this.camera.updateProjectionMatrix();
    }
    if (o.autoRotate !== undefined) {
      this.autoRotateDesign = o.autoRotate;
      if (this.controls) this.controls.autoRotate = o.autoRotate;
      if (this.controls) this.controls.autoRotateSpeed = 0.8;
    }
    if (o.frontsVisible !== undefined) this.frontsVisible = o.frontsVisible;
    // Kadrowanie TYLKO gdy użytkownik faktycznie zmienił oddalenie —
    // wcześniej każde odświeżenie sceny przestawiało kamerę ("przyciąganie do elementu").
    const distanceChanged = o.distance !== undefined && Math.abs(prevDistance - this.distanceMul) > 1e-6;
    if (distanceChanged) {
      // zmiana oddalenia = dolly kamery wzdłuż kierunku patrzenia, bez zmiany celu
      if (this.camera && this.controls) {
        const target = this.controls.target.clone();
        const dir = this.camera.position.clone().sub(target);
        const base = dir.length() / (prevDistance || 1);
        dir.setLength(base * this.distanceMul);
        this.camera.position.copy(target).add(dir);
        this.controls.update();
      }
    }
  }

  /** Ustawia kamerę na PROJEKT (szafki), pomijając otoczenie i pokój. */
  frameDesign() {
    if (!this.camera || !this.controls) return;
    const box = new THREE.Box3();
    // kadrujemy na bryły projektu (szafki); pokój i ogród zostają jako tło
    for (const obj of this.designGroup.children) {
      const k = obj.userData?.kind;
      if (k === 'scene' || k === 'light') continue;
      if (!obj.visible) continue;
      box.expandByObject(obj);
    }
    if (box.isEmpty()) box.setFromObject(this.designGroup);
    if (box.isEmpty()) return;
    const size = box.getSize(new THREE.Vector3());
    const center = box.getCenter(new THREE.Vector3());
    const radius = Math.max(size.x, size.y, size.z) * 0.9 || 1;
    this.camera.position.set(center.x + radius * 1.1, center.y + radius * 0.55, center.z + radius * 1.4);
    this.controls.target.copy(center);
    this.controls.update();
  }

  /**
   * Kamera do wnętrza: 'front' = przed szafką (widok na otwarty front),
   * 'drawer' = z góry do wybranej szuflady. Współrzędne w mm.
   */
  frameInterior(
    cabinet: { x: number; z: number; width: number; height: number; depth: number; rotation: number },
    view: 'front' | 'drawer',
    elementY?: number,
  ) {
    if (!this.camera || !this.controls) return;
    const mm = 0.001;
    const rad = (cabinet.rotation * Math.PI) / 180;
    const cx = cabinet.x * mm;
    const cz = cabinet.z * mm;
    const W = cabinet.width * mm;
    const H = cabinet.height * mm;
    const D = cabinet.depth * mm;
    const halfY = (elementY ?? 0) * mm;

    const local =
      view === 'front'
        ? new THREE.Vector3(0, H * 0.62, D * 1.75)
        : new THREE.Vector3(0, H * (elementY ? 1 : 0.95) + 0.25, D * 0.42);
    // obrót wokół osi szafki
    const wx = cx + local.x * Math.cos(rad) + local.z * Math.sin(rad);
    const wz = cz - local.x * Math.sin(rad) + local.z * Math.cos(rad);

    this.camera.position.set(wx, local.y + (view === 'drawer' ? halfY * 0.15 : 0), wz);
    this.controls.target.set(
      cx,
      view === 'drawer' ? H * 0.45 + halfY : H * 0.45,
      cz,
    );
    void W;
    this.controls.update();
  }

  /** Renderuje pomieszczenie testowe (podłoga, ściany, okno, drzwi). */
  renderRoom(boxes: import('./RenderEngine').RoomBox[], visible = true) {
    if (!this.scene) throw new Error('Engine not initialized');
    for (const o of [...this.roomGroup.children]) {
      o.removeFromParent();
      const m = o as THREE.Mesh;
      m.geometry?.dispose?.();
    }
    this.roomGroup.visible = visible;
    if (!visible) {
      this.draw();
      return;
    }
    const mm = 0.001;
    for (const b of boxes) {
      const geom = new THREE.BoxGeometry(b.size[0] * mm, b.size[1] * mm, b.size[2] * mm);
      // materiał wg rodzaju: podłoga z desek, ściany tynk, szyba szkło
      const kind =
        b.mat ??
        (b.kind === 'floor' ? 'deck' : b.kind === 'window' ? 'glass' : ('plaster' as const));
      // tryb techniczny: płaskie kolory bez tekstur
    if (this.materialMode === 'flat') {
      return new THREE.MeshStandardMaterial({
        color: new THREE.Color(b.color ?? '#d9d4c9'),
        roughness: 0.85,
        metalness: 0.02,
        flatShading: false,
      });
    }
    const props = materialProps(kind);
      const tex = texturesFor(kind);
      const scaleM = textureScale(kind);
      const map = tex.map.clone();
      map.needsUpdate = true;
      map.repeat.set(
        Math.max(0.5, (Math.max(b.size[0], b.size[2]) / 1000) / scaleM),
        Math.max(0.5, (Math.max(b.size[1], b.size[2]) / 1000) / scaleM),
      );
      const mat = new THREE.MeshStandardMaterial({
        color: new THREE.Color(b.color),
        roughness: props.roughness,
        metalness: props.metalness,
        map: kind === 'glass' ? undefined : map,
        bumpMap: kind === 'glass' ? undefined : tex.bump?.clone(),
        bumpScale: bumpScale(kind),
        transparent: props.transparent === true,
        opacity: props.opacity ?? b.opacity ?? 1,
        // ściany: tylko powierzchnie wewnętrzne (culling) — brak efektu szyby
        side: b.kind === 'wall' && this.wallGhost ? THREE.BackSide : THREE.FrontSide,
        envMapIntensity: 1.1,
      });
      const mesh = new THREE.Mesh(geom, mat);
      mesh.position.set(b.position[0] * mm, b.position[1] * mm, b.position[2] * mm);
      mesh.userData = { kind: 'room-' + b.kind };
      mesh.receiveShadow = b.kind !== 'wall';
      mesh.castShadow = b.kind === 'wall';
      this.roomGroup.add(mesh);
    }
    this.draw();
  }

  /** Punkt na podłodze (y=0) pod kursorem — do przesuwania szafek. */
  screenToFloor(clientX: number, clientY: number): { x: number; z: number } | null {
    if (!this.renderer || !this.camera) return null;
    const rect = this.renderer.domElement.getBoundingClientRect();
    const ndc = new THREE.Vector2(
      ((clientX - rect.left) / rect.width) * 2 - 1,
      -((clientY - rect.top) / rect.height) * 2 + 1,
    );
    const ray = new THREE.Raycaster();
    ray.setFromCamera(ndc, this.camera);
    const plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
    const hit = new THREE.Vector3();
    if (!ray.ray.intersectPlane(plane, hit)) return null;
    return { x: hit.x * 1000, z: hit.z * 1000 }; // mm
  }

  /** Rysuje linie dociągania (pomocnicze) na podłodze. */
  drawGuides(guides: { axis: 'x' | 'z'; value: number; from: number; to: number }[]) {
    if (!this.scene) return;
    for (const o of [...this.guideGroup.children]) {
      o.removeFromParent();
      (o as THREE.LineSegments).geometry?.dispose?.();
    }
    const mm = 0.001;
    for (const g of guides) {
      const pts: THREE.Vector3[] = [];
      if (g.axis === 'x') {
        pts.push(new THREE.Vector3(g.value * mm, 0.005, g.from * mm));
        pts.push(new THREE.Vector3(g.value * mm, 0.005, g.to * mm));
      } else {
        pts.push(new THREE.Vector3(g.from * mm, 0.005, g.value * mm));
        pts.push(new THREE.Vector3(g.to * mm, 0.005, g.value * mm));
      }
      const geom = new THREE.BufferGeometry().setFromPoints(pts);
      const line = new THREE.Line(
        geom,
        new THREE.LineBasicMaterial({ color: 0xc9a227, transparent: true, opacity: 0.9 }),
      );
      this.guideGroup.add(line);
    }
  }

  clearGuides() {
    for (const o of [...this.guideGroup.children]) {
      o.removeFromParent();
      (o as THREE.LineSegments).geometry?.dispose?.();
    }
  }

  /** Włącz/wyłącz sterowanie kamerą (przy przesuwaniu szafki kamera ma stać). */
  setControlsEnabled(on: boolean) {
    if (this.controls) this.controls.enabled = on;
  }

  /** Jakość renderu: low = bez AO i bloomu, medium = sam AO, high = wszystko. */
  setQuality(level: 'low' | 'medium' | 'high') {
    this.quality = level;
    if (!this.post) return;
    this.post.set({
      ao: level !== 'low',
      bloom: level === 'high',
      grade: true,
    });
  }

  /** Czy GPU jest sprzętowe — przy SwiftShader wyłączamy efekty ciężkie. */
  private isSoftRenderer(): boolean {
    try {
      const gl = this.renderer?.getContext();
      const ext = gl?.getExtension('WEBGL_debug_renderer_info');
      const name = ext ? String(gl!.getParameter(ext.UNMASKED_RENDERER_WEBGL)) : '';
      return /swiftshader|llvmpipe|software/i.test(name);
    } catch {
      return false;
    }
  }

  /** Wczytuje HDRI (equirect .hdr) jako tło i źródło odbić. */
  async loadHDRI(url: string) {
    if (!this.renderer || !this.scene) return;
    try {
      const tex = await new RGBELoader().loadAsync(url);
      tex.mapping = THREE.EquirectangularReflectionMapping;
      const pmrem = new THREE.PMREMGenerator(this.renderer);
      const env = pmrem.fromEquirectangular(tex).texture;
      this.scene.environment = env;
      this.scene.background = tex;
      this.scene.environmentIntensity = 1.0;
      tex.dispose();
    } catch (e) {
      console.warn('HDRI nie wczytane:', e);
    }
  }

  /** Ustawia słońce: wysokość i azymut w stopniach, kolor i moc. */
  setSun(elevationDeg: number, color = '#fff6e8', intensity = 3, azimuthDeg = 35) {
    if (!this.sunLight) return;
    const el = (Math.max(0.5, elevationDeg) * Math.PI) / 180;
    const az = (azimuthDeg * Math.PI) / 180;
    const r = 22;
    this.sunLight.position.set(
      Math.cos(el) * Math.sin(az) * r,
      Math.sin(el) * r,
      Math.cos(el) * Math.cos(az) * r,
    );
    this.sunLight.color = new THREE.Color(color);
    this.sunLight.intensity = intensity;
    this.sunLight.visible = intensity > 0.01;
    if (this.hemiLight) this.hemiLight.intensity = 0.5 + Math.min(1, intensity / 3) * 0.6;
    this.draw();
  }

  /** Styl widoku: materiały, cienie, AO, tło, ekspozycja. */
  applyStyle(spec: {
    materials: 'pbr' | 'flat' | 'wire';
    shadows: boolean;
    ao: boolean;
    bloom: boolean;
    background: string;
    sun: number;
    sunColor: string;
    sunElevation: number;
    exposure: number;
    skyTint: string;
  }) {
    this.materialMode = spec.materials;
    if (this.renderer) {
      this.renderer.shadowMap.enabled = spec.shadows;
      this.renderer.toneMappingExposure = spec.exposure;
    }
    if (this.scene) {
      if (!this.scene.background || !(this.scene.background as THREE.Texture).isTexture) {
        this.scene.background = new THREE.Color(spec.background);
      }
      const fog = this.scene.fog as THREE.Fog | null;
      if (fog) fog.color = new THREE.Color(spec.skyTint);
    }
    this.setSun(spec.sunElevation, spec.sunColor, spec.sun);
    this.setQuality(spec.ao ? (spec.bloom ? 'high' : 'medium') : 'low');
    // przebuduj materiały
    this.matCache.clear();
    if (this.lastBoxes) this.renderBoxes(this.lastBoxes);
    this.draw();
  }

  /** Ściany przezroczyste (widok roboczy) albo pełne. */
  setWallGhost(on: boolean) {
    // on = widok roboczy: ściany widoczne tylko od wewnątrz (nie zasłaniają, nie są przezroczyste)
    this.wallGhost = on;
    for (const o of this.roomGroup.children) {
      const m = o as THREE.Mesh;
      if (m.userData?.kind !== 'room-wall') continue;
      const mat = m.material as THREE.MeshStandardMaterial;
      mat.side = on ? THREE.BackSide : THREE.DoubleSide;
      mat.transparent = false;
      mat.opacity = 1;
      mat.depthWrite = true;
      mat.needsUpdate = true;
    }
    this.draw();
  }

  /** Pokaż/ukryj chmurę punktów. */
  setCloudVisible(visible: boolean) {
    if (this.pointCloud) this.pointCloud.visible = visible;
  }

  /** Podświetla całą szafkę (zaznaczenie). */
  highlightCabinet(cabinetId: string | null) {
    for (const o of this.designGroup.children) {
      if (!(o as THREE.Mesh).isMesh) continue;
      const m = o as THREE.Mesh;
      const mat = m.material as THREE.MeshStandardMaterial;
      if (!mat || !mat.emissive) continue;
      const on = cabinetId !== null && m.userData.cabinetId === cabinetId;
      mat.emissive.setHex(on ? 0x2a3a55 : 0x000000);
      mat.emissiveIntensity = on ? 1 : 0;
    }
  }

  /** Buduje/podmienia całą scenę z listy brył (mm → metry). */
  private lastBoxes?: import('./RenderEngine').SceneBox[];

  renderBoxes(boxes: import('./RenderEngine').SceneBox[], cabinetsOrigin: { x: number; z: number } = { x: 0, z: 0 }) {
    if (!this.scene) throw new Error('Engine not initialized');
    this.lastBoxes = boxes;
    // usuń poprzednie bryły
    for (const o of [...this.designGroup.children]) {
      o.removeFromParent();
      (o as THREE.Mesh).geometry?.dispose?.();
    }
    const mm = 0.001;
    for (const b of boxes) {
      // fronty ukrywane globalnie (klawisz D / ustawienia)
      if (b.kind === 'front' && !this.frontsVisible) continue;
      const [sx, sy, sz] = b.size;
      const geom =
        b.shape === 'cylinder'
          ? new THREE.CylinderGeometry((sx * mm) / 2, (sx * mm) / 2, sy * mm, 20)
          : b.shape === 'sphere'
          ? new THREE.SphereGeometry((sx * mm) / 2, 18, 14)
          : b.kind === 'front' || b.kind === 'panel' || b.kind === 'shelf' || b.kind === 'drawer'
          ? new RoundedBoxGeometry(sx * mm, sy * mm, sz * mm, 2, Math.min(0.0015, (Math.min(sx, sy, sz) * mm) / 6))
          : new THREE.BoxGeometry(sx * mm, sy * mm, sz * mm);
      const mat = this.materialFor(b);
      const mesh = new THREE.Mesh(geom, mat);
      mesh.position.set(
        (b.position[0] + cabinetsOrigin.x) * mm,
        b.position[1] * mm,
        (b.position[2] + cabinetsOrigin.z) * mm,
      );
      if (b.rotationY) mesh.rotation.y = (b.rotationY * Math.PI) / 180;
      if (b.rotationZ) mesh.rotation.z = (b.rotationZ * Math.PI) / 180;
      if (b.rotationX) mesh.rotation.x = (b.rotationX * Math.PI) / 180;
      mesh.userData = {
        cabinetId: b.cabinetId,
        elementId: b.elementId,
        frontId: b.frontId,
        kind: b.kind,
        boxId: b.id,
      };
      const solid = b.kind !== 'hole' && b.mat !== 'glass';
      mesh.castShadow = solid && b.kind !== 'scene' && !b.emissive;
      mesh.receiveShadow = solid;
      this.designGroup.add(mesh);

      // realne światło oprawy (lampy, LED)
      if (b.light) {
        const lp = new THREE.PointLight(
          new THREE.Color(b.light.color),
          b.light.intensity,
          (b.light.distance ?? 1200) * mm,
          2,
        );
        lp.position.set(
          (b.position[0] + cabinetsOrigin.x) * mm,
          (b.light.y ?? b.position[1]) * mm,
          (b.position[2] + cabinetsOrigin.z) * mm,
        );
        lp.userData = { kind: 'light' };
        this.designGroup.add(lp);
      }

      // kontur krawędzi — czytelność bryły (panel/front), pomijany dla drobnych elementów
      if (b.outline && b.kind !== 'hole' && b.kind !== 'handle') {
        const edges = new THREE.LineSegments(
          new THREE.EdgesGeometry(geom, 25),
          new THREE.LineBasicMaterial({
            color: b.kind === 'front' ? 0x2a2f38 : 0x1b2027,
            transparent: true,
            opacity: b.kind === 'front' ? 0.55 : 0.75,
          }),
        );
        edges.position.copy(mesh.position);
        edges.rotation.copy(mesh.rotation);
        edges.userData = { cabinetId: b.cabinetId, elementId: b.elementId, kind: 'outline' };
        this.designGroup.add(edges);
      }
    }
    this.draw();
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
    const meshes = this.designGroup.children.filter((o) => (o as THREE.Mesh).isMesh);
    const hits = ray.intersectObjects(meshes, false);
    if (!hits.length) return null;
    const ud = hits[0].object.userData as {
      cabinetId?: string;
      elementId?: string;
      frontId?: string;
      kind?: string;
    };
    return {
      cabinetId: ud.cabinetId,
      elementId: ud.elementId,
      frontId: ud.frontId,
      kind: ud.kind,
      screen: { x: clientX, y: clientY },
      point: hits[0].point.toArray() as [number, number, number],
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
    this.post?.dispose();
    this.renderer?.dispose();
  }

  private resize = () => {
    if (!this.renderer || !this.camera) return;
    const w = this.renderer.domElement.clientWidth || window.innerWidth;
    const h = this.renderer.domElement.clientHeight || window.innerHeight;
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
    this.post?.setSize(w, h, this.renderer.getPixelRatio());
  };

  /** Jeden punkt renderowania — zawsze przez pipeline, gdy dostępny. */
  private draw() {
    if (!this.renderer || !this.scene || !this.camera) return;
    if (this.post) this.post.render();
    else this.renderer.render(this.scene, this.camera);
  }

  private loop = () => {
    this.raf = requestAnimationFrame(this.loop);

    // pomiar płynności: przy klatkach > 45 ms obniżamy jakość (maks. 2 razy)
    const now = performance.now();
    if (this.lastFrame) {
      this.frameTimes.push(now - this.lastFrame);
      if (this.frameTimes.length > 30) {
        const avg = this.frameTimes.reduce((a, b) => a + b, 0) / this.frameTimes.length;
        this.frameTimes = [];
        if (avg > 45 && this.degraded < 2 && this.quality !== 'low') {
          this.setQuality(this.quality === 'high' ? 'medium' : 'low');
          this.degraded++;
        }
      }
    }
    this.lastFrame = now;

    this.controls?.update();
    // obrót projektu w tle (z ustawień) — obraca całą grupę szafek
    if (this.autoRotateDesign) this.designGroup.rotation.y += 0.0035;
    this.draw();
  };
}
