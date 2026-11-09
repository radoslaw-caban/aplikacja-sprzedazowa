/**
 * Import skanów z iPada / telefonu — parsery chmur punktów.
 *
 * Obsługiwane formaty (to, co realnie eksportują apki ARKit/LiDAR):
 *  - PLY: ascii, binary_little_endian, binary_big_endian — dowolne typy właściwości
 *    (Polycam, 3D Scanner App, Scaniverse, LiDAR Scanner 3D)
 *  - PCD: ascii + binary (Polycam „point cloud")
 *  - XYZ / TXT / CSV: tekstowe kolumny x y z [r g b]
 *
 * Formatów siatkowych (GLB/GLTF/OBJ/STL) nie parsujemy tutaj — robią to loadery
 * three.js w silniku, bo potrzebują sceny i materiałów.
 *
 * WAŻNE: skany mobilne są w METRACH (ARKit/ARCore), ale część apek eksportuje
 * milimetry. Parser nie zgaduje skali na siłę — zwraca surowe współrzędne
 * i bbox, a użytkownik wybiera jednostkę w UI (transformacja jest w silniku,
 * więc zmiana jednostki nie wymaga ponownego parsowania pliku).
 */

export interface ScanCloud {
  positions: Float32Array;
  colors?: Uint8Array;
  pointCount: number;
  /** liczba punktów w pliku przed decymacją */
  rawCount: number;
  /** krok decymacji (1 = bez decymacji) */
  stride: number;
  format: string;
  bboxMin: [number, number, number];
  bboxMax: [number, number, number];
}

export interface ParseOptions {
  /** maksymalna liczba punktów w wyniku (decymacja równomierna) */
  maxPoints?: number;
  /** postęp 0..1 (wywoływany rzadko, nie dla każdego punktu) */
  onProgress?: (fraction: number) => void;
}

export type ScanFormat = 'ply' | 'pcd' | 'xyz' | 'glb' | 'gltf' | 'obj' | 'stl';

export const POINT_FORMATS: ScanFormat[] = ['ply', 'pcd', 'xyz'];
export const MESH_FORMATS: ScanFormat[] = ['glb', 'gltf', 'obj', 'stl'];

/** Rozpoznaje format po rozszerzeniu pliku. */
export function detectFormat(fileName: string): ScanFormat | null {
  const ext = (fileName.split('.').pop() ?? '').toLowerCase();
  if (ext === 'ply' || ext === 'pcd' || ext === 'xyz' || ext === 'txt' || ext === 'csv') {
    return ext === 'txt' || ext === 'csv' ? 'xyz' : (ext as ScanFormat);
  }
  if (ext === 'glb' || ext === 'gltf' || ext === 'obj' || ext === 'stl') return ext as ScanFormat;
  return null;
}

export function isPointFormat(f: ScanFormat): boolean {
  return POINT_FORMATS.includes(f);
}

// ---------------------------------------------------------------------------
// czytniki liczb binarnych
// ---------------------------------------------------------------------------

interface TypeInfo {
  size: number;
  read: (dv: DataView, off: number, le: boolean) => number;
}

const TYPES: Record<string, TypeInfo> = {
  char: { size: 1, read: (dv, o) => dv.getInt8(o) },
  int8: { size: 1, read: (dv, o) => dv.getInt8(o) },
  uchar: { size: 1, read: (dv, o) => dv.getUint8(o) },
  uint8: { size: 1, read: (dv, o) => dv.getUint8(o) },
  short: { size: 2, read: (dv, o, le) => dv.getInt16(o, le) },
  int16: { size: 2, read: (dv, o, le) => dv.getInt16(o, le) },
  ushort: { size: 2, read: (dv, o, le) => dv.getUint16(o, le) },
  uint16: { size: 2, read: (dv, o, le) => dv.getUint16(o, le) },
  int: { size: 4, read: (dv, o, le) => dv.getInt32(o, le) },
  int32: { size: 4, read: (dv, o, le) => dv.getInt32(o, le) },
  uint: { size: 4, read: (dv, o, le) => dv.getUint32(o, le) },
  uint32: { size: 4, read: (dv, o, le) => dv.getUint32(o, le) },
  float: { size: 4, read: (dv, o, le) => dv.getFloat32(o, le) },
  float32: { size: 4, read: (dv, o, le) => dv.getFloat32(o, le) },
  double: { size: 8, read: (dv, o, le) => dv.getFloat64(o, le) },
  float64: { size: 8, read: (dv, o, le) => dv.getFloat64(o, le) },
};

/** Nazwa właściwości koloru → indeks składowej (0=R, 1=G, 2=B). */
const COLOR_KEYS: Record<string, number> = {
  red: 0, r: 0, diffuse_red: 0, diffusered: 0,
  green: 1, g: 1, diffuse_green: 1, diffusegreen: 1,
  blue: 2, b: 2, diffuse_blue: 2, diffuseblue: 2,
};

const LIMIT = 1e5; // skan pomieszczenia nie przekracza 100 km

// ---------------------------------------------------------------------------
// PLY
// ---------------------------------------------------------------------------

interface PlyProp {
  name: string;
  type: string;
  list?: { countType: string; itemType: string };
}

interface PlyElement {
  name: string;
  count: number;
  props: PlyProp[];
}

interface PlyHeader {
  format: 'ascii' | 'binary_little_endian' | 'binary_big_endian';
  dataStart: number;
  elements: PlyElement[];
}

/** Czyta nagłówek PLY bajt po bajcie — nie zakłada, że mieści się w 64 kB. */
function readPlyHeader(bytes: Uint8Array): PlyHeader {
  let text = '';
  let dataStart = -1;
  const cap = Math.min(bytes.length, 1024 * 1024); // nagłówek > 1 MB to błąd pliku
  for (let i = 0; i < cap; i++) {
    const c = bytes[i];
    text += String.fromCharCode(c);
    if (c === 10 && text.endsWith('end_header\n')) {
      dataStart = i + 1;
      break;
    }
  }
  if (dataStart < 0) throw new Error('PLY: brak zakończenia nagłówka (end_header)');

  const lines = text.slice(0, text.indexOf('end_header')).split(/\r?\n/);
  let format: PlyHeader['format'] = 'ascii';
  const elements: PlyElement[] = [];
  for (const raw of lines) {
    const line = raw.trim();
    if (!line) continue;
    const [kw, ...rest] = line.split(/\s+/);
    if (kw === 'format') {
      const f = rest[0];
      if (f === 'ascii' || f === 'binary_little_endian' || f === 'binary_big_endian') format = f;
      else throw new Error(`PLY: nieznany format ${f}`);
    } else if (kw === 'element') {
      elements.push({ name: rest[0], count: parseInt(rest[1], 10), props: [] });
    } else if (kw === 'property' && elements.length) {
      const el = elements[elements.length - 1];
      if (rest[0] === 'list') {
        el.props.push({
          name: rest[3] ?? 'list',
          type: rest[2],
          list: { countType: rest[1], itemType: rest[2] },
        });
      } else {
        el.props.push({ name: rest[1], type: rest[0] });
      }
    }
  }
  return { format, dataStart, elements };
}

/** Indeksy właściwości pozycji i koloru w elemencie vertex. */
function vertexMapping(el: PlyElement) {
  const lower = el.props.map((p) => p.name.toLowerCase());
  const ix = lower.indexOf('x');
  const iy = lower.indexOf('y');
  const iz = lower.indexOf('z');
  if (ix < 0 || iy < 0 || iz < 0) throw new Error('PLY: brak właściwości x/y/z');
  const color: Partial<Record<0 | 1 | 2, number>> = {};
  lower.forEach((n, i) => {
    const k = COLOR_KEYS[n];
    if (k !== undefined && color[k as 0 | 1 | 2] === undefined) color[k as 0 | 1 | 2] = i;
  });
  const hasColor = color[0] !== undefined && color[1] !== undefined && color[2] !== undefined;
  // skala koloru: float 0..1, ushort 0..65535, uchar 0..255
  let colorScale = 1;
  if (hasColor) {
    const t = el.props[color[0]!].type;
    if (t === 'float' || t === 'float32' || t === 'double' || t === 'float64') colorScale = 255;
    else if (t === 'ushort' || t === 'uint16') colorScale = 255 / 65535;
  }
  return { ix, iy, iz, color: hasColor ? (color as { 0: number; 1: number; 2: number }) : null, colorScale };
}

export function parsePly(buffer: ArrayBuffer, opts: ParseOptions = {}): ScanCloud {
  const bytes = new Uint8Array(buffer);
  const head = readPlyHeader(bytes);
  const vertex = head.elements.find((e) => e.name === 'vertex');
  if (!vertex) throw new Error('PLY: brak elementu vertex');
  if (!vertex.count) throw new Error('PLY: element vertex jest pusty');
  const map = vertexMapping(vertex);

  const maxPoints = opts.maxPoints ?? 6_000_000;
  const stride = Math.max(1, Math.ceil(vertex.count / maxPoints));
  const capacity = Math.ceil(vertex.count / stride);
  const positions = new Float32Array(capacity * 3);
  let colors: Uint8Array | undefined = map.color ? new Uint8Array(capacity * 3) : undefined;

  const bboxMin: [number, number, number] = [Infinity, Infinity, Infinity];
  const bboxMax: [number, number, number] = [-Infinity, -Infinity, -Infinity];
  let written = 0;

  const push = (x: number, y: number, z: number, cr: number, cg: number, cb: number) => {
    if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(z)) return;
    if (Math.abs(x) > LIMIT || Math.abs(y) > LIMIT || Math.abs(z) > LIMIT) return;
    if (written >= capacity) return;
    positions[written * 3] = x;
    positions[written * 3 + 1] = y;
    positions[written * 3 + 2] = z;
    if (x < bboxMin[0]) bboxMin[0] = x;
    if (y < bboxMin[1]) bboxMin[1] = y;
    if (z < bboxMin[2]) bboxMin[2] = z;
    if (x > bboxMax[0]) bboxMax[0] = x;
    if (y > bboxMax[1]) bboxMax[1] = y;
    if (z > bboxMax[2]) bboxMax[2] = z;
    if (colors) {
      colors[written * 3] = cr;
      colors[written * 3 + 1] = cg;
      colors[written * 3 + 2] = cb;
    }
    written++;
  };

  if (head.format === 'ascii') {
    const tail = new TextDecoder().decode(bytes.subarray(head.dataStart));
    const tokens = tail.trim().split(/[\s,]+/);
    const perVertex = vertex.props.length;
    let t = 0;
    for (let k = 0; k < vertex.count; k++) {
      const base = t;
      t += perVertex;
      if (k % stride !== 0) continue;
      const x = parseFloat(tokens[base + map.ix]);
      const y = parseFloat(tokens[base + map.iy]);
      const z = parseFloat(tokens[base + map.iz]);
      let cr = 255, cg = 255, cb = 255;
      if (map.color) {
        cr = Math.min(255, Math.max(0, Math.round(parseFloat(tokens[base + map.color[0]]) * map.colorScale)));
        cg = Math.min(255, Math.max(0, Math.round(parseFloat(tokens[base + map.color[1]]) * map.colorScale)));
        cb = Math.min(255, Math.max(0, Math.round(parseFloat(tokens[base + map.color[2]]) * map.colorScale)));
      }
      push(x, y, z, cr, cg, cb);
      if (k % 200_000 === 0) opts.onProgress?.(k / vertex.count);
    }
  } else {
    const le = head.format === 'binary_little_endian';
    const dv = new DataView(buffer, head.dataStart);
    // offsety stałe (element vertex nie może zawierać list — inaczej błąd pliku)
    if (vertex.props.some((p) => p.list)) throw new Error('PLY: lista właściwości w elemencie vertex');
    const offsets: number[] = [];
    let recSize = 0;
    for (const p of vertex.props) {
      const info = TYPES[p.type];
      if (!info) throw new Error(`PLY: nieznany typ właściwości ${p.type}`);
      offsets.push(recSize);
      recSize += info.size;
    }
    const readable = Math.floor((buffer.byteLength - head.dataStart) / recSize);
    const n = Math.min(vertex.count, readable);
    const rx = TYPES[vertex.props[map.ix].type].read;
    const ry = TYPES[vertex.props[map.iy].type].read;
    const rz = TYPES[vertex.props[map.iz].type].read;

    for (let k = 0; k < n; k++) {
      if (k % stride !== 0) continue;
      const base = k * recSize;
      const x = rx(dv, base + offsets[map.ix], le);
      const y = ry(dv, base + offsets[map.iy], le);
      const z = rz(dv, base + offsets[map.iz], le);
      let cr = 255, cg = 255, cb = 255;
      if (map.color) {
        const c0 = map.color[0], c1 = map.color[1], c2 = map.color[2];
        cr = Math.min(255, Math.max(0, Math.round(TYPES[vertex.props[c0].type].read(dv, base + offsets[c0], le) * map.colorScale)));
        cg = Math.min(255, Math.max(0, Math.round(TYPES[vertex.props[c1].type].read(dv, base + offsets[c1], le) * map.colorScale)));
        cb = Math.min(255, Math.max(0, Math.round(TYPES[vertex.props[c2].type].read(dv, base + offsets[c2], le) * map.colorScale)));
      }
      push(x, y, z, cr, cg, cb);
      if (k % 500_000 === 0) opts.onProgress?.(k / Math.max(1, n));
    }
  }

  if (!written) throw new Error('PLY: nie udało się odczytać żadnego punktu');
  return finish(positions, colors, written, vertex.count, stride, 'PLY');
}

// ---------------------------------------------------------------------------
// PCD
// ---------------------------------------------------------------------------

export function parsePcd(buffer: ArrayBuffer, opts: ParseOptions = {}): ScanCloud {
  const bytes = new Uint8Array(buffer);
  // nagłówek: linie tekstowe do DATA
  let headerEnd = -1;
  let text = '';
  const cap = Math.min(bytes.length, 256 * 1024);
  for (let i = 0; i < cap; i++) {
    text += String.fromCharCode(bytes[i]);
    if (bytes[i] === 10 && /DATA\s+\w+\s*\n$/i.test(text)) {
      headerEnd = i + 1;
      break;
    }
  }
  if (headerEnd < 0) throw new Error('PCD: brak nagłówka DATA');

  const head = text.slice(0, headerEnd);
  const fieldsLine = /FIELDS\s+(.+)/i.exec(head);
  const sizeLine = /SIZE\s+(.+)/i.exec(head);
  const typeLine = /TYPE\s+(.+)/i.exec(head);
  const countLine = /COUNT\s+(.+)/i.exec(head);
  const pointsLine = /POINTS\s+(\d+)/i.exec(head);
  const dataLine = /DATA\s+(\w+)/i.exec(head);
  if (!fieldsLine || !pointsLine || !dataLine) throw new Error('PCD: niepełny nagłówek');
  const fields = fieldsLine[1].trim().split(/\s+/);
  const sizes = (sizeLine?.[1].trim().split(/\s+/).map(Number)) ?? fields.map(() => 4);
  const ptypes = (typeLine?.[1].trim().split(/\s+/)) ?? fields.map(() => 'F');
  const counts = (countLine?.[1].trim().split(/\s+/).map(Number)) ?? fields.map(() => 1);
  const total = parseInt(pointsLine[1], 10);
  const dataMode = dataLine[1].toLowerCase();
  if (dataMode === 'binary_compressed') throw new Error('PCD: binary_compressed nieobsługiwany — wyeksportuj binary/ascii');

  const ix = fields.indexOf('x');
  const iy = fields.indexOf('y');
  const iz = fields.indexOf('z');
  if (ix < 0 || iy < 0 || iz < 0) throw new Error('PCD: brak pól x/y/z');
  const iRgb = fields.indexOf('rgb');
  const hasRgb = iRgb >= 0;

  const maxPoints = opts.maxPoints ?? 6_000_000;
  const stride = Math.max(1, Math.ceil(total / maxPoints));
  const capacity = Math.ceil(total / stride);
  const positions = new Float32Array(capacity * 3);
  let colors: Uint8Array | undefined = hasRgb ? new Uint8Array(capacity * 3) : undefined;
  const bboxMin: [number, number, number] = [Infinity, Infinity, Infinity];
  const bboxMax: [number, number, number] = [-Infinity, -Infinity, -Infinity];
  let written = 0;

  const push = (x: number, y: number, z: number, rgb: number) => {
    if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(z)) return;
    if (Math.abs(x) > LIMIT || Math.abs(y) > LIMIT || Math.abs(z) > LIMIT) return;
    if (written >= capacity) return;
    positions[written * 3] = x;
    positions[written * 3 + 1] = y;
    positions[written * 3 + 2] = z;
    if (x < bboxMin[0]) bboxMin[0] = x;
    if (y < bboxMin[1]) bboxMin[1] = y;
    if (z < bboxMin[2]) bboxMin[2] = z;
    if (x > bboxMax[0]) bboxMax[0] = x;
    if (y > bboxMax[1]) bboxMax[1] = y;
    if (z > bboxMax[2]) bboxMax[2] = z;
    if (colors) {
      colors[written * 3] = (rgb >> 16) & 255;
      colors[written * 3 + 1] = (rgb >> 8) & 255;
      colors[written * 3 + 2] = rgb & 255;
    }
    written++;
  };

  if (dataMode === 'ascii') {
    const tail = new TextDecoder().decode(bytes.subarray(headerEnd));
    const rows = tail.split(/\r?\n/).filter((l) => l.trim() && !l.startsWith('#'));
    const perRow = fields.reduce((a, _f, i) => a + (counts[i] ?? 1), 0);
    let idx = 0;
    const componentStart: number[] = [];
    let acc = 0;
    for (const c of counts) { componentStart.push(acc); acc += c; }

    for (const row of rows) {
      if (idx % stride === 0) {
        const t = row.trim().split(/\s+/);
        if (t.length >= perRow) {
          const x = parseFloat(t[componentStart[ix]]);
          const y = parseFloat(t[componentStart[iy]]);
          const z = parseFloat(t[componentStart[iz]]);
          let rgb = 0xffffff;
          if (hasRgb) {
            rgb = dataMode === 'ascii' ? parseFloat(t[componentStart[iRgb]]) || 0 : 0;
            // w ascii rgb bywa zapisany jako liczba całkowita albo jako 4 składowe r g b
            rgb = Math.round(rgb);
          }
          push(x, y, z, rgb);
        }
      }
      idx++;
      if (idx >= total) break;
      if (idx % 200_000 === 0) opts.onProgress?.(idx / total);
    }
  } else {
    // binary: offsety pól w rekordzie
    const offsets: number[] = [];
    let recSize = 0;
    const fieldReaders: TypeInfo[] = [];
    for (let i = 0; i < fields.length; i++) {
      const sz = sizes[i] ?? 4;
      const t = ptypes[i] ?? 'F';
      const key =
        t === 'F' ? (sz === 8 ? 'double' : 'float')
          : t === 'I' ? (sz === 1 ? 'int8' : sz === 2 ? 'int16' : 'int32')
            : (sz === 1 ? 'uint8' : sz === 2 ? 'uint16' : 'uint32');
      offsets.push(recSize);
      fieldReaders.push(TYPES[key]);
      recSize += sz * (counts[i] ?? 1);
    }
    const dv = new DataView(buffer, headerEnd);
    const readable = Math.floor((buffer.byteLength - headerEnd) / recSize);
    const n = Math.min(total, readable);
    for (let k = 0; k < n; k++) {
      if (k % stride !== 0) continue;
      const base = k * recSize;
      const x = fieldReaders[ix].read(dv, base + offsets[ix], true);
      const y = fieldReaders[iy].read(dv, base + offsets[iy], true);
      const z = fieldReaders[iz].read(dv, base + offsets[iz], true);
      let rgb = 0xffffff;
      if (hasRgb) {
        // rgb bywa floatem z zapakowanym uint32 (PCL/Polycam) — czytamy surowe bity,
        // bo getFloat32() dałoby ułamek i straciło składowe koloru
        const off = base + offsets[iRgb];
        rgb = sizes[iRgb] === 4 ? dv.getUint32(off, true) : dv.getUint8(off);
      }
      push(x, y, z, rgb);
      if (k % 500_000 === 0) opts.onProgress?.(k / Math.max(1, n));
    }
  }

  if (!written) throw new Error('PCD: nie udało się odczytać żadnego punktu');
  return finish(positions, colors, written, total, stride, `PCD (${dataMode})`);
}

// ---------------------------------------------------------------------------
// XYZ / TXT / CSV
// ---------------------------------------------------------------------------

export function parseXyz(buffer: ArrayBuffer, opts: ParseOptions = {}): ScanCloud {
  const text = new TextDecoder().decode(new Uint8Array(buffer));
  const lines = text.split(/\r?\n/);
  const maxPoints = opts.maxPoints ?? 6_000_000;

  // najpierw policz wiersze z liczbami, żeby dobrać krok decymacji
  let numeric = 0;
  for (const l of lines) {
    if (!l.trim() || l.startsWith('#') || l.startsWith('//')) continue;
    const first = l.trim()[0];
    if (!(first >= '0' && first <= '9') && first !== '-' && first !== '+' && first !== '.') continue;
    numeric++;
  }
  const stride = Math.max(1, Math.ceil(numeric / maxPoints));
  const capacity = Math.ceil(numeric / stride);
  const positions = new Float32Array(capacity * 3);
  const colors = new Uint8Array(capacity * 3);
  let hasColor = false;
  let written = 0;
  const bboxMin: [number, number, number] = [Infinity, Infinity, Infinity];
  const bboxMax: [number, number, number] = [-Infinity, -Infinity, -Infinity];
  let seen = 0;

  for (const line of lines) {
    const s = line.trim();
    if (!s || s.startsWith('#') || s.startsWith('//')) continue;
    const t = s.split(/[\s,;]+/);
    if (t.length < 3) continue;
    const x = parseFloat(t[0]);
    const y = parseFloat(t[1]);
    const z = parseFloat(t[2]);
    if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(z)) continue;
    const k = seen++;
    if (k % stride !== 0) continue;
    if (written >= capacity || Math.abs(x) > LIMIT || Math.abs(y) > LIMIT || Math.abs(z) > LIMIT) continue;
    positions[written * 3] = x;
    positions[written * 3 + 1] = y;
    positions[written * 3 + 2] = z;
    if (x < bboxMin[0]) bboxMin[0] = x;
    if (y < bboxMin[1]) bboxMin[1] = y;
    if (z < bboxMin[2]) bboxMin[2] = z;
    if (x > bboxMax[0]) bboxMax[0] = x;
    if (y > bboxMax[1]) bboxMax[1] = y;
    if (z > bboxMax[2]) bboxMax[2] = z;
    if (t.length >= 6) {
      const r = parseFloat(t[3]);
      const g = parseFloat(t[4]);
      const b = parseFloat(t[5]);
      if (Number.isFinite(r) && Number.isFinite(g) && Number.isFinite(b)) {
        hasColor = true;
        // kolory mogą być 0..1 lub 0..255
        const sc = r <= 1 && g <= 1 && b <= 1 ? 255 : 1;
        colors[written * 3] = Math.min(255, Math.max(0, Math.round(r * sc)));
        colors[written * 3 + 1] = Math.min(255, Math.max(0, Math.round(g * sc)));
        colors[written * 3 + 2] = Math.min(255, Math.max(0, Math.round(b * sc)));
      }
    }
    written++;
    if (seen % 200_000 === 0) opts.onProgress?.(seen / Math.max(1, numeric));
  }

  if (!written) throw new Error('XYZ: brak wierszy z liczbami (oczekiwane: x y z [r g b])');
  return finish(positions, hasColor ? colors : undefined, written, numeric === 0 ? written : numeric, stride, 'XYZ/CSV');
}

function finish(
  positions: Float32Array,
  colors: Uint8Array | undefined,
  written: number,
  rawCount: number,
  stride: number,
  format: string,
): ScanCloud {
  const p = positions.slice(0, written * 3);
  const c = colors ? colors.slice(0, written * 3) : undefined;
  let min: [number, number, number] = [Infinity, Infinity, Infinity];
  let max: [number, number, number] = [-Infinity, -Infinity, -Infinity];
  for (let i = 0; i < written; i++) {
    const x = p[i * 3], y = p[i * 3 + 1], z = p[i * 3 + 2];
    if (x < min[0]) min[0] = x;
    if (y < min[1]) min[1] = y;
    if (z < min[2]) min[2] = z;
    if (x > max[0]) max[0] = x;
    if (y > max[1]) max[1] = y;
    if (z > max[2]) max[2] = z;
  }
  if (!Number.isFinite(min[0])) min = [0, 0, 0];
  if (!Number.isFinite(max[0])) max = [0, 0, 0];
  return { positions: p, colors: c, pointCount: written, rawCount, stride, format, bboxMin: min, bboxMax: max };
}

/** Wspólne wejście: rozpoznaje format i parsuje chmurę punktów. */
export function parsePointCloud(
  format: ScanFormat,
  buffer: ArrayBuffer,
  opts: ParseOptions = {},
): ScanCloud {
  switch (format) {
    case 'ply':
      return parsePly(buffer, opts);
    case 'pcd':
      return parsePcd(buffer, opts);
    case 'xyz':
      return parseXyz(buffer, opts);
    default:
      throw new Error(`${format.toUpperCase()} nie jest formatem chmury punktów — to siatka`);
  }
}

/** Proponowana jednostka na podstawie rozmiaru (tylko podpowiedź dla UI). */
export function guessUnit(bboxMin: [number, number, number], bboxMax: [number, number, number]): {
  unit: 'm' | 'cm' | 'mm';
  scale: number;
  note: string;
} {
  const ext = Math.max(bboxMax[0] - bboxMin[0], bboxMax[1] - bboxMin[1], bboxMax[2] - bboxMin[2]);
  if (ext > 1500) return { unit: 'mm', scale: 0.001, note: 'plik wygląda na milimetry' };
  if (ext > 100) return { unit: 'cm', scale: 0.01, note: 'plik wygląda na centymetry' };
  return { unit: 'm', scale: 1, note: 'plik wygląda na metry (standard ARKit/ARCore)' };
}