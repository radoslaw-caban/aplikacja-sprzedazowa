/**
 * Test parserów importu skanu — uruchamiany na Node (type stripping).
 * Generuje pliki w formatach, które realnie eksportują apki LiDAR,
 * i sprawdza, czy parser odczytuje właściwe punkty, kolory i bbox.
 */
import { parsePly, parsePcd, parseXyz, detectFormat, guessUnit, parsePointCloud } from '../src/engine/scanFormats.ts';
import { writeFileSync, mkdirSync } from 'node:fs';

const OUT = new URL('./fixtures/', import.meta.url).pathname;
mkdirSync(OUT, { recursive: true });

let fails = 0;
const check = (name: string, cond: boolean, extra = '') => {
  console.log(`${cond ? 'OK  ' : 'FAIL'} ${name} ${extra}`);
  if (!cond) fails++;
};

// ---------------------------------------------------------------------------
// 1. PLY binary_little_endian: float x,y,z + uchar red,green,blue (typowy Polycam)
// ---------------------------------------------------------------------------
{
  const n = 1000;
  const header =
    'ply\nformat binary_little_endian 1.0\nelement vertex ' + n + '\n' +
    'property float x\nproperty float y\nproperty float z\n' +
    'property uchar red\nproperty uchar green\nproperty uchar blue\nend_header\n';
  const body = new Uint8Array(n * 15);
  const dv = new DataView(body.buffer);
  for (let i = 0; i < n; i++) {
    const o = i * 15;
    dv.setFloat32(o, i * 0.001, true);
    dv.setFloat32(o + 4, Math.sin(i * 0.01) * 0.8, true);
    dv.setFloat32(o + 8, i * 0.002, true);
    body[o + 12] = 10;
    body[o + 13] = 20;
    body[o + 14] = 30;
  }
  const file = Buffer.concat([Buffer.from(header, 'latin1'), Buffer.from(body)]);
  writeFileSync(OUT + 'scan-polycam.ply', file);

  const buf = file.buffer.slice(file.byteOffset, file.byteOffset + file.byteLength);
  const c = parsePly(buf as ArrayBuffer);
  check('PLY binary: liczba punktów', c.pointCount === n, `${c.pointCount}/${n}`);
  check('PLY binary: kolor', !!c.colors && c.colors[0] === 10 && c.colors[1] === 20 && c.colors[2] === 30);
  check('PLY binary: bbox x', Math.abs(c.bboxMin[0]) < 1e-6 && Math.abs(c.bboxMax[0] - 0.999) < 1e-4, `${c.bboxMin[0]}..${c.bboxMax[0]}`);
}

// ---------------------------------------------------------------------------
// 2. PLY z nagłówkiem > 64 kB (długi komentarz) — stary parser się na tym gubił
// ---------------------------------------------------------------------------
{
  const pad = 'comment ' + 'x'.repeat(70 * 1024) + '\n';
  const header = 'ply\nformat ascii 1.0\n' + pad + 'element vertex 3\nproperty float x\nproperty float y\nproperty float z\nend_header\n';
  const rows = '1 2 3\n4 5 6\n7 8 9\n';
  const file = Buffer.from(header + rows, 'latin1');
  writeFileSync(OUT + 'scan-longheader.ply', file);
  const c = parsePly(file.buffer.slice(file.byteOffset, file.byteOffset + file.byteLength) as ArrayBuffer);
  check('PLY duży nagłówek: 3 pkt', c.pointCount === 3, `${c.pointCount}`);
  check('PLY duży nagłówek: współrzędne', c.positions[0] === 1 && c.positions[4] === 5 && c.positions[8] === 9);
}

// ---------------------------------------------------------------------------
// 3. PLY ascii z kolorami float 0..1 (3D Scanner App bywa tak)
// ---------------------------------------------------------------------------
{
  const header = 'ply\nformat ascii 1.0\nelement vertex 2\nproperty float x\nproperty float y\nproperty float z\nproperty float red\nproperty float green\nproperty float blue\nend_header\n';
  const rows = '0 0 0 1 0.5 0\n1 1 1 0 0 1\n';
  const file = Buffer.from(header + rows, 'latin1');
  writeFileSync(OUT + 'scan-ascii-floatcol.ply', file);
  const c = parsePly(file.buffer.slice(file.byteOffset, file.byteOffset + file.byteLength) as ArrayBuffer);
  check('PLY ascii float color: pkt', c.pointCount === 2);
  check('PLY ascii float color: 255/128/0', c.colors![0] === 255 && c.colors![1] === 128 && c.colors![2] === 0, `${c.colors![0]},${c.colors![1]},${c.colors![2]}`);
}

// ---------------------------------------------------------------------------
// 4. PLY z elementami list (twarze) i double xyz — eksport z meshem, nie może się wysypać
// ---------------------------------------------------------------------------
{
  const header =
    'ply\nformat binary_little_endian 1.0\nelement vertex 2\nproperty double x\nproperty double y\nproperty double z\n' +
    'element face 0\nproperty list uchar int vertex_indices\nend_header\n';
  const body = Buffer.alloc(2 * 24);
  const dv = new DataView(body.buffer, body.byteOffset);
  for (let i = 0; i < 2; i++) {
    dv.setFloat64(i * 24, i * 1000, true);
    dv.setFloat64(i * 24 + 8, 0, true);
    dv.setFloat64(i * 24 + 16, 0, true);
  }
  const file = Buffer.concat([Buffer.from(header, 'latin1'), body]);
  writeFileSync(OUT + 'scan-double.ply', file);
  const c = parsePly(file.buffer.slice(file.byteOffset, file.byteOffset + file.byteLength) as ArrayBuffer);
  check('PLY double + face list: czyta wierzchołki', c.pointCount === 2, `${c.pointCount}`);
  check('PLY double: bbox 1000 mm', Math.abs(c.bboxMax[0] - 1000) < 1e-6, `${c.bboxMax[0]}`);
}

// ---------------------------------------------------------------------------
// 5. PCD binary: x,y,z float + rgb float (Polycam PCD)
// ---------------------------------------------------------------------------
{
  const n = 500;
  const header = `# .PCD v0.7\nVERSION 0.7\nFIELDS x y z rgb\nSIZE 4 4 4 4\nTYPE F F F F\nCOUNT 1 1 1 1\nWIDTH ${n}\nHEIGHT 1\nVIEWPOINT 0 0 0 1 0 0 0\nPOINTS ${n}\nDATA binary\n`;
  const body = Buffer.alloc(n * 16);
  const dv = new DataView(body.buffer, body.byteOffset);
  for (let i = 0; i < n; i++) {
    const o = i * 16;
    dv.setFloat32(o, i * 0.01, true);
    dv.setFloat32(o + 4, 0.5, true);
    dv.setFloat32(o + 8, -i * 0.01, true);
    // rgb zapakowany jako float (uint32 bitcast)
    dv.setUint32(o + 12, (200 << 16) | (100 << 8) | 50, true);
  }
  const file = Buffer.concat([Buffer.from(header, 'latin1'), body]);
  writeFileSync(OUT + 'scan-polycam.pcd', file);
  const c = parsePcd(file.buffer.slice(file.byteOffset, file.byteOffset + file.byteLength) as ArrayBuffer);
  check('PCD binary: 500 pkt', c.pointCount === n, `${c.pointCount}`);
  check('PCD binary: rgb', c.colors![0] === 200 && c.colors![1] === 100 && c.colors![2] === 50, `${c.colors![0]},${c.colors![1]},${c.colors![2]}`);
  check('PCD binary: z ujemne', c.bboxMin[2] < -4, `${c.bboxMin[2]}`);
}

// ---------------------------------------------------------------------------
// 6. XYZ z kolorami 0..255
// ---------------------------------------------------------------------------
{
  const lines = ['# x y z r g b', '0 0 0 255 0 0', '1 0 0 0 255 0', '1 1 0 0 0 255', '1 1 1 128 128 128'];
  const file = Buffer.from(lines.join('\n'), 'latin1');
  writeFileSync(OUT + 'scan.xyz', file);
  const c = parseXyz(file.buffer.slice(file.byteOffset, file.byteOffset + file.byteLength) as ArrayBuffer);
  check('XYZ: 4 pkt', c.pointCount === 4, `${c.pointCount}`);
  check('XYZ: kolory', c.colors![0] === 255 && c.colors![4] === 255 && c.colors![9] === 128, `${c.colors![0]},${c.colors![4]},${c.colors![9]}`);
  check('XYZ: bbox', c.bboxMax[0] === 1 && c.bboxMax[2] === 1);
}

// ---------------------------------------------------------------------------
// 7. Decymacja i weryfikacja formatu
// ---------------------------------------------------------------------------
{
  const n = 100_000;
  const header = `ply\nformat binary_little_endian 1.0\nelement vertex ${n}\nproperty float x\nproperty float y\nproperty float z\nproperty uchar red\nproperty uchar green\nproperty uchar blue\nend_header\n`;
  const body = Buffer.alloc(n * 15);
  const file = Buffer.concat([Buffer.from(header, 'latin1'), body]);
  const c = parsePly(file.buffer.slice(file.byteOffset, file.byteOffset + file.byteLength) as ArrayBuffer, { maxPoints: 10_000 });
  check('PLY decymacja: ~10k z 100k', c.pointCount > 9_000 && c.pointCount <= 10_001, `${c.pointCount}`);
  check('PLY decymacja: rawCount', c.rawCount === n, `${c.rawCount}`);
  check('PLY decymacja: krok', c.stride === 10, `${c.stride}`);
}

check('detectFormat ply', detectFormat('Skan.PLY') === 'ply');
check('detectFormat csv', detectFormat('scan.csv') === 'xyz');
check('detectFormat glb', detectFormat('model.glb') === 'glb');
check('detectFormat nieznany', detectFormat('foto.jpg') === null);

check('guessUnit mm', guessUnit([0, 0, 0], [5000, 2500, 4000]).unit === 'mm');
check('guessUnit m', guessUnit([0, 0, 0], [5, 2.5, 4]).unit === 'm');

// ---------------------------------------------------------------------------
// 8. parsePointCloud: zły format siatki → czytelny błąd
// ---------------------------------------------------------------------------
{
  let msg = '';
  try {
    parsePointCloud('glb', new ArrayBuffer(8));
  } catch (e) {
    msg = e instanceof Error ? e.message : String(e);
  }
  check('parsePointCloud: GLB → błąd opisowy', msg.includes('siatka'), msg);
}

console.log(fails === 0 ? '\nWSZYSTKIE TESTY OK' : `\n${fails} TEST(ÓW) NIE PRZESZŁO`);
process.exit(fails === 0 ? 0 : 1);