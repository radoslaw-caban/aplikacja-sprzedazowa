/**
 * Parser binarnego PLY (little_endian, xyz + rgb) — działa w Web Workerze.
 * 491 tys. pkt = ~7 MB → parsowanie < 100 ms.
 */

export interface PlyCloud {
  positions: Float32Array;
  colors?: Uint8Array;
  pointCount: number;
  bboxMin: [number, number, number];
  bboxMax: [number, number, number];
}

export function parsePly(buffer: ArrayBuffer): PlyCloud {
  const bytes = new Uint8Array(buffer);
  // nagłówek: tekst do końca linii "end_header" (włącznie z \n)
  let text = '';
  let found = false;
  let nlAfter = -1;
  for (let i = 0; i < Math.min(bytes.length, 64 * 1024); i++) {
    text += String.fromCharCode(bytes[i]);
    if (!found && text.indexOf('end_header') >= 0) found = true;
    // po znalezieniu end_header czytaj dalej, aż pojawi się kończący \n —
    // przerwanie tuż po nagłówku gubiło ostatni bajt i przesuwało całą tablicę punktów
    if (found) {
      const nl = text.indexOf('\n', text.indexOf('end_header'));
      if (nl >= 0) { nlAfter = nl; break; }
    }
  }
  if (nlAfter < 0) throw new Error('PLY: brak zakończenia nagłówka (end_header\\n)');
  const dataStart = nlAfter + 1;

  const header = text.slice(0, nlAfter);
  const countMatch = /element vertex (\d+)/.exec(header);
  if (!countMatch) throw new Error('PLY: brak element vertex');
  const n = parseInt(countMatch[1], 10);

  // kolejność właściwości
  const props: string[] = [];
  const propRe = /property (\w+) (\w+)/g;
  let pm: RegExpExecArray | null;
  while ((pm = propRe.exec(header)) !== null) props.push(pm[2]);
  const ix = props.indexOf('x'), iy = props.indexOf('y'), iz = props.indexOf('z');
  const ir = props.indexOf('red'), ig = props.indexOf('green'), ib = props.indexOf('blue');
  if (ix < 0 || iy < 0 || iz < 0) throw new Error('PLY: brak x/y/z');
  const hasColor = ir >= 0 && ig >= 0 && ib >= 0;

  const fmt = /format binary_little_endian/.test(header) ? 'le' : 'be';
  if (fmt !== 'le') throw new Error('PLY: wspierany tylko binary_little_endian');
  const isAscii = /format ascii/.test(header);
  if (isAscii) throw new Error('PLY ascii niewspierany — użyj binary');

  // zakładamy: float x,y,z + uchar r,g,b (typowy eksport z chmury)
  const floats = props.filter((p) => ['x', 'y', 'z', 'nx', 'ny', 'nz', 'intensity'].includes(p)).length;
  const uchars = props.length - floats;
  if (floats + uchars !== props.length) throw new Error('PLY: niewspierane typy właściwości');

  // oblicz offsety
  const offsets: number[] = [];
  let o = 0;
  for (const p of props) {
    const isFloat = ['x', 'y', 'z', 'nx', 'ny', 'nz', 'intensity'].includes(p);
    offsets.push(o);
    o += isFloat ? 4 : 1;
  }
  const recSize = o;
  void recSize;

  const positions = new Float32Array(n * 3);
  let colors: Uint8Array | undefined = hasColor ? new Uint8Array(n * 3) : undefined;
  const dv = new DataView(buffer, dataStart);
  const bboxMin: [number, number, number] = [Infinity, Infinity, Infinity];
  const bboxMax: [number, number, number] = [-Infinity, -Infinity, -Infinity];
  // sensowne granice chmury (skan pomieszczenia: |x| < 100 km) — odsiewa śmieciowe wartości
  const LIMIT = 1e5;
  let written = 0;

  for (let k = 0; k < n; k++) {
    const base = k * recSize;
    const x = dv.getFloat32(base + offsets[ix], true);
    const y = dv.getFloat32(base + offsets[iy], true);
    const z = dv.getFloat32(base + offsets[iz], true);
    if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(z)) continue;
    if (Math.abs(x) > LIMIT || Math.abs(y) > LIMIT || Math.abs(z) > LIMIT) continue;
    positions[written * 3] = x;
    positions[written * 3 + 1] = y;
    positions[written * 3 + 2] = z;
    if (x < bboxMin[0]) bboxMin[0] = x; if (y < bboxMin[1]) bboxMin[1] = y; if (z < bboxMin[2]) bboxMin[2] = z;
    if (x > bboxMax[0]) bboxMax[0] = x; if (y > bboxMax[1]) bboxMax[1] = y; if (z > bboxMax[2]) bboxMax[2] = z;
    if (colors && ir >= 0) {
      colors[written * 3] = dv.getUint8(base + offsets[ir]);
      colors[written * 3 + 1] = dv.getUint8(base + offsets[ig]);
      colors[written * 3 + 2] = dv.getUint8(base + offsets[ib]);
    }
    written++;
  }
  return {
    positions: positions.slice(0, written * 3),
    colors: colors ? colors.slice(0, written * 3) : undefined,
    pointCount: written,
    bboxMin,
    bboxMax,
  };
}
