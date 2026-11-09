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
    const base = -170;
    // pień (stożkowy, węższy u góry)
    out.push(box(`tree-${i}-trunk`, [h * 0.055, h * 0.52, h * 0.055], [x, base + h * 0.26, z], '#5d4430', {
      shape: 'cylinder', mat: 'wood-dark',
    }));
    // korona: kilka nieregularnych brył, żeby nie wyglądała jak kula
    const blobs: [number, number, number, number, string][] = [
      [h * 0.46, h * 0.26, h * 0.46, 0.46, '#3f6f36'],
      [h * 0.34, h * 0.22, h * 0.34, 0.60, '#4a7d3e'],
      [h * 0.28, h * 0.20, h * 0.28, 0.74, '#548a47'],
      [h * 0.22, h * 0.17, h * 0.22, 0.86, '#5f9850'],
      [h * 0.18, h * 0.14, h * 0.18, 0.96, '#6aa65a'],
      [h * 0.20, h * 0.15, h * 0.20, 0.58, '#467a3b'],
    ];
    blobs.forEach(([sx, sy, sz, at, col], k) => {
      out.push(box(`tree-${i}-crown-${k}`, [sx, sy, sz], [
        x + (k % 2 ? h * 0.06 : -h * 0.05),
        base + h * at,
        z + (k % 3 === 0 ? h * 0.04 : -h * 0.03),
      ], col, { shape: 'sphere', mat: 'foliage' }));
    });
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
    // ościeżnica
    out.push(box('win-reveal-top', [winW + 160, 60, 120], [wx, wy + winH / 2 + 60, wz], '#e6e3dc', { mat: 'plaster' }));
    // rama zewnętrzna
    out.push(box('win-frame', [winW + 120, winH + 120, 80], [wx, wy, wz], '#2f3237', { mat: 'metal' }));
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
    const dz = D / 2 + 40;
    const dh = dr.h;
    const drW = dr.w;

    // ościeżnica: dwie pionowe opaski + nadproże
    out.push(box('door-jamb-l', [70, dh + 70, 140], [dx - drW / 2 - 35, dh / 2, dz], '#4a3626', { mat: 'wood-dark' }));
    out.push(box('door-jamb-r', [70, dh + 70, 140], [dx + drW / 2 + 35, dh / 2, dz], '#4a3626', { mat: 'wood-dark' }));
    out.push(box('door-head', [drW + 140, 70, 140], [dx, dh + 35, dz], '#4a3626', { mat: 'wood-dark' }));

    // skrzydło z drewna
    out.push(box('door-leaf', [drW - 10, dh - 10, 60], [dx, dh / 2, dz + 30], '#9c7550', { mat: 'wood' }));

    // płyciny (górna duża, dolna mała)
    out.push(box('door-panel-top', [drW - 260, dh * 0.46, 22], [dx, dh * 0.64, dz + 62], '#8a6544', { mat: 'wood' }));
    out.push(box('door-panel-bot', [drW - 260, dh * 0.24, 22], [dx, dh * 0.22, dz + 62], '#8a6544', { mat: 'wood' }));

    // przeszklenie w górnej płycinie
    out.push(box('door-glass', [drW - 320, dh * 0.3, 14], [dx, dh * 0.68, dz + 70], '#bcdcec', { mat: 'glass', opacity: 0.28 }));

    // klamka: szyld + pochwyt
    out.push(box('door-rose', [60, 160, 26], [dx + drW / 2 - 130, dh * 0.45, dz + 66], '#8d8d8d', { mat: 'metal' }));
    out.push(box('door-handle', [22, 22, 90], [dx + drW / 2 - 130, dh * 0.45, dz + 100], '#c9a227', { mat: 'metal', shape: 'cylinder', rotationX: 90 }));

    // próg i schodek
    out.push(box('door-sill', [drW + 60, 30, 160], [dx, 15, dz], '#9a9a9a'));
    out.push(box('door-step', [drW + 500, 150, 460], [dx, -75, dz + 300], '#a8a8a8', { mat: 'stone' }));

    // daszek nad wejściem
    out.push(box('porch-canopy', [drW + 900, 90, 1100], [dx, dh + 330, dz + 480], '#5e211d', { mat: 'roof' }));
    out.push(box('porch-lamp', [70, 70, 70], [dx - drW / 2 - 300, dh - 200, dz + 60], '#ffe9c4', {
      shape: 'sphere', emissive: '#ffe9c4', emissiveIntensity: 3,
      light: { color: '#ffe4b8', intensity: 1.2, distance: 1600, y: dh - 200 },
    }));
  }

  return out;
}
