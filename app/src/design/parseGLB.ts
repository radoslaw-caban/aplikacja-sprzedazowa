import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { parseCabinetParts, type ParsedCabinet, type RawPart } from './parseModel';

/**
 * Rozczytuje plik GLB/GLTF i zamienia go na listę brył w milimetrach,
 * a następnie klasyfikuje je parserem konstrukcji (parseModel.ts).
 *
 * Jednostki: glTF jest w metrach, więc wymiary mnożymy przez 1000.
 * Jeśli model jest w centymetrach, wykrywamy to po skali obrysu
 * (szafka nie ma 30 m ani 7 mm wysokości).
 */

export interface GlbParseResult {
  parsed: ParsedCabinet;
  clusters: Cluster[];
  /** oryginalne bryły w mm — do podglądu w UI */
  parts: RawPart[];
  /** czy wykryto nietypowe jednostki */
  unitNote?: string;
}

export async function parseGlb(buffer: ArrayBuffer): Promise<GlbParseResult> {
  const loader = new GLTFLoader();
  const gltf = await loader.parseAsync(buffer, '');

  const root = gltf.scene;
  root.updateMatrixWorld(true);

  const parts: RawPart[] = [];
  root.traverse((obj) => {
    const mesh = obj as THREE.Mesh;
    if (!mesh.isMesh || !mesh.geometry) return;
    mesh.geometry.computeBoundingBox();
    const bb = mesh.geometry.boundingBox;
    if (!bb) return;

    // wymiary i środek po transformacji (macierz świata)
    const size = new THREE.Vector3().subVectors(bb.max, bb.min);
    const center = new THREE.Vector3().addVectors(bb.min, bb.max).multiplyScalar(0.5);
    center.applyMatrix4(mesh.matrixWorld);

    // obrót: bierzemy wartości bezwzględne rozmiaru po skali świata
    const scale = new THREE.Vector3();
    mesh.matrixWorld.decompose(new THREE.Vector3(), new THREE.Quaternion(), scale);

    parts.push({
      name: mesh.name || undefined,
      size: [
        Math.abs(size.x * scale.x) * 1000,
        Math.abs(size.y * scale.y) * 1000,
        Math.abs(size.z * scale.z) * 1000,
      ],
      center: [center.x * 1000, center.y * 1000, center.z * 1000],
    });
  });

  if (!parts.length) {
    throw new Error('Model nie zawiera siatek (mesh) — nic do rozczytania');
  }

  // detekcja jednostek: obrys w metrach
  const maxDim = Math.max(
    ...parts.map((p) => Math.max(p.size[0], p.size[1], p.size[2])),
  );

  let unitNote: string | undefined;
  let scaled = parts;
  if (maxDim < 5) {
    // model w metrach, ale bez przeliczenia
    scaled = parts.map((p) => ({
      ...p,
      size: p.size.map((v) => v * 1000) as [number, number, number],
      center: p.center.map((v) => v * 1000) as [number, number, number],
    }));
    unitNote = 'Model był w metrach — przeliczono na mm';
  } else if (maxDim > 40000) {
    scaled = parts.map((p) => ({
      ...p,
      size: p.size.map((v) => v / 10) as [number, number, number],
      center: p.center.map((v) => v / 10) as [number, number, number],
    }));
    unitNote = 'Model prawdopodobnie w centymetrach ×10 — przeliczono na mm';
  }

  // normalizacja jednostek do realnej skali mebla (600–2400 mm wysokości)
  let guard = 0;
  while (guard++ < 4) {
    const hs = scaled.map((p) => p.size[1]);
    const h = Math.max(...hs);
    if (h > 2600) {
      scaled = scaled.map((p) => ({
        ...p,
        size: p.size.map((v) => v / 10) as [number, number, number],
        center: p.center.map((v) => v / 10) as [number, number, number],
      }));
      unitNote = 'Skala modelu przeliczona (÷10) do wymiarów mebla';
    } else if (h < 400) {
      scaled = scaled.map((p) => ({
        ...p,
        size: p.size.map((v) => v * 10) as [number, number, number],
        center: p.center.map((v) => v * 10) as [number, number, number],
      }));
      unitNote = 'Skala modelu przeliczona (×10) do wymiarów mebla';
    } else break;
  }

  // orientacja: jeśli Y nie jest największą osią przy szafce, próbujemy Z-do-góry
  const parsedY = parseCabinetParts(scaled, { up: 'y' });
  const parsedZ = parseCabinetParts(scaled, { up: 'z' });
  const parsed = parsedY.height >= parsedZ.height ? parsedY : parsedZ;

  return { parsed, parts: scaled, unitNote, clusters: clusterParts(scaled) };
}

export interface Cluster {
  id: number;
  parts: RawPart[];
  min: [number, number, number];
  max: [number, number, number];
  size: [number, number, number];
  label: string;
}

/**
 * Grupuje bryły w szafki: łączy części, których środki są bliżej niż `cell` mm.
 * Pozwala wybrać pojedynczą szafkę z modelu całej kuchni.
 */
export function clusterParts(parts: RawPart[], cell = 750): Cluster[] {
  const n = parts.length;
  const parent = Array.from({ length: n }, (_, i) => i);
  const find = (a: number): number => (parent[a] === a ? a : (parent[a] = find(parent[a])));
  const union = (a: number, b: number) => {
    const ra = find(a);
    const rb = find(b);
    if (ra !== rb) parent[rb] = ra;
  };

  for (let i = 0; i < n; i++) {
    for (let j = i + 1; j < n; j++) {
      const a = parts[i].center;
      const b = parts[j].center;
      const d = Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]);
      if (d < cell) union(i, j);
    }
  }

  const groups = new Map<number, RawPart[]>();
  for (let i = 0; i < n; i++) {
    const r = find(i);
    const arr = groups.get(r) ?? [];
    arr.push(parts[i]);
    groups.set(r, arr);
  }

  const out: Cluster[] = [];
  let idx = 0;
  for (const arr of groups.values()) {
    if (arr.length < 3) continue; // pojedyncze drobiazgi pomijamy
    const min: [number, number, number] = [Infinity, Infinity, Infinity];
    const max: [number, number, number] = [-Infinity, -Infinity, -Infinity];
    for (const p of arr) {
      for (let a = 0; a < 3; a++) {
        min[a] = Math.min(min[a], p.center[a] - p.size[a] / 2);
        max[a] = Math.max(max[a], p.center[a] + p.size[a] / 2);
      }
    }
    const size: [number, number, number] = [max[0] - min[0], max[1] - min[1], max[2] - min[2]];
    out.push({
      id: idx++,
      parts: arr,
      min,
      max,
      size,
      label: `${Math.round(size[0])}×${Math.round(size[1])}×${Math.round(size[2])} mm · ${arr.length} brył`,
    });
  }
  // największe (najbardziej kompletne) na górze
  out.sort((a, b) => b.parts.length - a.parts.length);
  return out;
}

/** Wczytuje plik z input[type=file] jako ArrayBuffer. */
export function readFileBuffer(file: File): Promise<ArrayBuffer> {
  return file.arrayBuffer();
}
