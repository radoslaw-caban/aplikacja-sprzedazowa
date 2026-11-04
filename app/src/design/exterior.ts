import type { SceneBox } from './types';
import type { Room } from './room';

/**
 * Otoczenie domu: podjazd z ulicy, kostka brukowa, trawa, taras, drzewa, dach.
 * Wszystko jako neutralne bryły (SceneBox) — renderer ich nie interpretuje.
 */

function box(
  id: string,
  size: [number, number, number],
  position: [number, number, number],
  color: string,
  extra: Partial<SceneBox> = {},
): SceneBox {
  return {
    id,
    kind: 'scene',
    cabinetId: 'scene',
    size,
    position,
    color,
    outline: false,
    ...extra,
  };
}

/**
 * Otoczenie wokół pomieszczenia `room` (mm).
 * Północ = -Z (za ścianą z oknem), południe = +Z (wejście).
 */
export function exteriorBoxes(room: Room, opts: { roof?: boolean } = {}): SceneBox[] {
  const out: SceneBox[] = [];
  const W = room.width;
  const D = room.depth;

  // --- trawnik wokół całego domu ---
  out.push(box('grass', [W + 16000, 20, D + 16000], [0, -10, 0], '#4a7c3f'));

  // --- taras przed domem (południe) ---
  out.push(box('terrace', [W + 1200, 60, 3000], [0, 30, D / 2 + 1600], '#8a6f4e'));
  // deski tarasu (rowki)
  for (let i = 0; i < 10; i++) {
    out.push(
      box(
        `terrace-plank-${i}`,
        [W + 1100, 8, 240],
        [0, 62, D / 2 + 200 + i * 300],
        i % 2 ? '#94795a' : '#82684a',
      ),
    );
  }

  // --- podjazd z ulicy (od południa, wzdłuż -Z na zewnątrz) ---
  const driveW = 3500;
  const driveLen = 9000;
  const driveZ = D / 2 + 3200 + driveLen / 2;
  out.push(box('driveway', [driveW, 40, driveLen], [W / 2 - 1200, 20, driveZ], '#6b6b6b'));

  // --- kostka brukowa: siatka kostek na podjeździe ---
  const cw = 700;
  const cl = 350;
  for (let row = 0; row < Math.floor(driveLen / cl); row++) {
    for (let col = 0; col < Math.floor(driveW / cw); col++) {
      const shade = (row + col) % 3;
      const color = shade === 0 ? '#8d8d8d' : shade === 1 ? '#7a7a7a' : '#9a9a9a';
      const x = W / 2 - 1200 - driveW / 2 + cw / 2 + col * cw;
      const z = driveZ - driveLen / 2 + cl / 2 + row * cl;
      out.push(box(`paver-${row}-${col}`, [cw - 12, 12, cl - 12], [x, 46, z], color));
    }
  }

  // --- opaska z kostki wokół tarasu ---
  out.push(box('curb-n', [W + 1600, 100, 200], [0, 50, D / 2 + 120], '#9c9c9c'));

  // --- drzewa ---
  const trees: [number, number, number][] = [
    [-W / 2 - 3000, -D / 2 - 2000, 5200],
    [W / 2 + 3400, -D / 2 - 1200, 6000],
    [-W / 2 - 4200, D / 2 + 2600, 4400],
    [W / 2 + 3000, D / 2 + 3200, 5000],
  ];
  trees.forEach(([x, z, h], i) => {
    // pień
    out.push(box(`tree-${i}-trunk`, [260, h * 0.45, 260], [x, h * 0.225, z], '#5a3f2b', { shape: 'cylinder' }));
    // korona — trzy cylindry/kule o różnych zieleniach
    out.push(box(`tree-${i}-crown-a`, [h * 0.62, h * 0.34, h * 0.62], [x, h * 0.5, z], '#3f6b34'));
    out.push(box(`tree-${i}-crown-b`, [h * 0.5, h * 0.3, h * 0.5], [x, h * 0.68, z], '#4a7c3f'));
    out.push(box(`tree-${i}-crown-c`, [h * 0.34, h * 0.24, h * 0.34], [x, h * 0.84, z], '#578a48'));
  });

  // --- dach (opcjonalny: domyślnie off, żeby nie zasłaniał wnętrza) ---
  if (!opts.roof) return out;

  const roofY = room.wallHeight;
  const over = 600;
  // dwie połacie jako cienkie, obrócone bryły
  const slabW = Math.sqrt((D / 2 + over) ** 2 + 900 ** 2);
  out.push(
    box('roof-s', [W + over * 2, 120, slabW], [0, roofY + 450, (D / 2 + over) / 2], '#7a2f2a', {
      rotationY: 0,
    }),
  );
  out.push(
    box('roof-n', [W + over * 2, 120, slabW], [0, roofY + 450, -(D / 2 + over) / 2], '#7a2f2a', {
      rotationY: 0,
    }),
  );
  // kalenica
  out.push(box('ridge', [W + over * 2 + 100, 160, 260], [0, roofY + 900, 0], '#5e211d'));
  // okap / rynna
  out.push(box('gutter-s', [W + over * 2, 120, 140], [0, roofY + 40, D / 2 + over], '#4a4a4a'));
  out.push(box('gutter-n', [W + over * 2, 120, 140], [0, roofY + 40, -(D / 2 + over)], '#4a4a4a'));

  // --- ładne okno w ścianie północnej (ramy + szyba + szprosy) ---
  const win = room.window;
  if (win && win.w > 0) {
    const wx = win.x - room.width / 2;
    const wy = win.y + win.h / 2;
    const winW = win.w;
    const winH = win.h;
    const wz = -D / 2 - 40;
    // rama zewnętrzna
    out.push(box('win-frame', [winW + 120, winH + 120, 80], [wx, wy, wz], '#2f3237'));
    // szyba
    out.push(box('win-glass', [winW, winH, 24], [wx, wy, wz - 10], '#a8d4e6', { opacity: 0.55 }));
    // szprosy: pion + poziom
    out.push(box('win-mullion', [60, winH, 50], [wx, wy, wz - 30], '#3a3f45'));
    out.push(box('win-transom', [winW, 50, 50], [wx, wy + winH * 0.15, wz - 30], '#3a3f45'));
    // parapet
    out.push(box('win-sill', [winW + 240, 60, 220], [wx, wy - winH / 2 - 90, wz - 60], '#d8d8d8'));
  }

  // --- drzwi wejściowe (ściana południowa) ---
  const dr = room.door;
  if (dr && dr.w > 0) {
    const dx = dr.x - room.width / 2;
    const dz = D / 2 + 70;
    const dh = dr.h;
    const drW = dr.w;
    // ościeżnica
    out.push(box('door-frame', [drW + 140, dh + 80, 120], [dx, dh / 2, dz], '#3a2a1e'));
    // skrzydło
    out.push(box('door-leaf', [drW, dh, 70], [dx, dh / 2, dz + 20], '#6b4a2f'));
    // płyciny
    out.push(box('door-panel-a', [drW - 220, dh * 0.34, 30], [dx, dh * 0.68, dz + 60], '#5d3f27'));
    out.push(box('door-panel-b', [drW - 220, dh * 0.34, 30], [dx, dh * 0.28, dz + 60], '#5d3f27'));
    // klamka
    out.push(box('door-handle', [70, 70, 140], [dx + drW / 2 - 140, dh * 0.46, dz + 90], '#c9a227', { shape: 'cylinder' }));
    // daszek nad wejściem
    out.push(box('porch-canopy', [drW + 900, 90, 1200], [dx, dh + 300, dz + 400], '#5e211d'));
    // schodek
    out.push(box('door-step', [drW + 500, 160, 500], [dx, -80, dz + 300], '#a8a8a8'));
  }

  return out;
}
