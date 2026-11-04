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
  out.push(box('grass', [W + 16000, 60, D + 16000], [0, -170, 0], '#ffffff', { mat: 'grass' }));

  // --- taras przed domem (południe) ---
  out.push(box('terrace', [W + 1200, 60, 3000], [0, 30, D / 2 + 1600], '#ffffff', { mat: 'deck' }));
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
  out.push(box('driveway', [driveW, 40, driveLen], [W / 2 - 1200, 20, driveZ], '#ffffff', { mat: 'cobble' }));

  // (kostka jest teksturą na podjeździe — bez tysiąca osobnych brył)

  // --- opaska z kostki wokół tarasu ---
  out.push(box('curb-n', [W + 1600, 100, 200], [0, 50, D / 2 + 120], '#9c9c9c'));

  // --- drzewa ---
  // drzewa odsunięte od domu, żeby nie zasłaniały wnętrza w kadrze
  const trees: [number, number, number][] = [
    [-W / 2 - 9000, -D / 2 - 6500, 7000],
    [W / 2 + 9500, -D / 2 - 5000, 8200],
    [-W / 2 - 10500, D / 2 + 7000, 6400],
    [W / 2 + 11000, D / 2 + 8500, 7600],
  ];
  trees.forEach(([x, z, h], i) => {
    // pień
    out.push(box(`tree-${i}-trunk`, [260, h * 0.5, 260], [x, -170 + h * 0.25, z], '#6b4a30', { shape: 'cylinder', mat: 'wood-dark' }));
    // korona — trzy cylindry/kule o różnych zieleniach
    out.push(box(`tree-${i}-crown-a`, [h * 0.46, h * 0.3, h * 0.46], [x, -170 + h * 0.52, z], '#ffffff', { mat: 'foliage', shape: 'sphere' }));
    out.push(box(`tree-${i}-crown-b`, [h * 0.38, h * 0.26, h * 0.38], [x, -170 + h * 0.7, z], '#e8f5e0', { mat: 'foliage', shape: 'sphere' }));
    out.push(box(`tree-${i}-crown-c`, [h * 0.26, h * 0.2, h * 0.26], [x, -170 + h * 0.85, z], '#d8efcc', { mat: 'foliage', shape: 'sphere' }));
  });

  // --- dach (opcjonalny: domyślnie off, żeby nie zasłaniał wnętrza) ---
  if (!opts.roof) return out;

  const roofY = room.wallHeight;
  const over = 600;
  // dwie połacie jako cienkie, obrócone bryły
  const slabW = Math.sqrt((D / 2 + over) ** 2 + 900 ** 2);
  out.push(
    box('roof-s', [W + over * 2, 120, slabW], [0, roofY + 450, (D / 2 + over) / 2], '#ffffff', { mat: 'roof' }),
  );
  out.push(
    box('roof-n', [W + over * 2, 120, slabW], [0, roofY + 450, -(D / 2 + over) / 2], '#ffffff', { mat: 'roof' }),
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
    out.push(box('win-glass', [winW, winH, 24], [wx, wy, wz - 10], '#a8d4e6', { opacity: 0.35, mat: 'glass' }));
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
    out.push(box('door-leaf', [drW, dh, 70], [dx, dh / 2, dz + 20], '#6b4a2f', { mat: 'wood-dark' }));
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
