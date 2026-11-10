import type { SceneBox } from './types';
import type { Room } from './room';

/**
 * Stylizacja wnętrza w duchu „soft minimal" (beż, dąb, trawertyn, bouclé).
 * Wszystko w mm, skala 1:1, proporcje mebli z katalogów (sofa 2200, stolik Ø900/420).
 */

const B = (
  id: string,
  kind: SceneBox['kind'],
  size: [number, number, number],
  position: [number, number, number],
  color: string,
  mat: SceneBox['mat'],
  extra: Partial<SceneBox> = {},
): SceneBox => ({ id, kind, cabinetId: 'styling', size, position, color, mat, outline: false, ...extra });

export function stylingBoxes(room: Room): SceneBox[] {
  const out: SceneBox[] = [];
  const W = room.width;
  const D = room.depth;
  const floorY = 0;

  // ---------- dywan 2800 × 2000 ----------
  const rugW = 2800;
  const rugD = 2000;
  const rugZ = D / 2 - 1500;
  out.push(B('rug', 'panel', [rugW, 12, rugD], [0, floorY + 6, rugZ], '#e9e2d6', 'rug'));

  // ---------- sofa 2200 × 950, pod ścianą ----------
  const sofaW = 2200;
  const sofaD = 950;
  const sofaZ = D / 2 - 400;
  out.push(B('sofa-base', 'panel', [sofaW, 320, sofaD], [0, floorY + 160, sofaZ], '#efe9df', 'fabric', { bevel: 110 }));
  out.push(B('sofa-seat', 'panel', [sofaW - 200, 170, sofaD - 160], [0, floorY + 405, sofaZ + 40], '#f4efe6', 'fabric', { bevel: 120 }));
  out.push(B('sofa-back', 'panel', [sofaW, 420, 200], [0, floorY + 530, sofaZ + sofaD / 2 - 100], '#efe9df', 'fabric', { bevel: 130 }));
  out.push(B('sofa-arm-l', 'panel', [200, 360, sofaD], [-sofaW / 2 + 100, floorY + 500, sofaZ], '#efe9df', 'fabric', { bevel: 150 }));
  out.push(B('sofa-arm-r', 'panel', [200, 360, sofaD], [sofaW / 2 - 100, floorY + 500, sofaZ], '#efe9df', 'fabric', { bevel: 150 }));
  // poduszki
  out.push(B('cushion-1', 'panel', [480, 420, 160], [-520, floorY + 560, sofaZ + 120], '#e3d9c8', 'fabric', { bevel: 70, rotationZ: -6 }));
  out.push(B('cushion-2', 'panel', [480, 420, 160], [0, floorY + 570, sofaZ + 120], '#efe9df', 'fabric', { bevel: 150 }));
  out.push(B('cushion-3', 'panel', [480, 420, 160], [520, floorY + 560, sofaZ + 120], '#dcd2c1', 'fabric', { bevel: 70, rotationZ: 6 }));

  // ---------- stolik kawowy: blat Ø900 trawertyn + żłobkowany cokół ----------
  const tX = 0;
  const tZ = rugZ - 950;
  out.push(B('coffee-top', 'panel', [900, 60, 900], [tX, floorY + 400, tZ], '#d8cbb8', 'travertine', { shape: 'cylinder', detail: 48 }));
  out.push(B('coffee-base', 'panel', [420, 370, 420], [tX, floorY + 185, tZ], '#c8b39a', 'wood', { shape: 'cylinder', detail: 40 }));
  // żłobkowanie cokołu
  for (let i = 0; i < 16; i++) {
    const a = (i / 16) * Math.PI * 2;
    out.push(
      B(`coffee-flute-${i}`, 'panel', [34, 360, 46], [tX + Math.cos(a) * 205, floorY + 180, tZ + Math.sin(a) * 205], '#bfa88f', 'wood', {
        rotationY: (a * 180) / Math.PI,
      }),
    );
  }

  // ---------- lampa łukowa ----------
  const lampX = -1500;
  const lampZ = D / 2 - 700;
  out.push(B('lamp-base', 'panel', [380, 40, 380], [lampX, floorY + 20, lampZ], '#b9b3a8', 'metal', { shape: 'cylinder', detail: 32 }));
  out.push(B('lamp-post', 'panel', [28, 1900, 28], [lampX, floorY + 950, lampZ], '#c9a86a', 'metal', { shape: 'cylinder', detail: 14 }));
  out.push(B('lamp-arc', 'panel', [28, 700, 28], [lampX + 320, floorY + 1850, lampZ], '#c9a86a', 'metal', { shape: 'cylinder', detail: 14, rotationZ: 62 }));
  out.push(B('lamp-shade', 'panel', [420, 420, 420], [lampX + 640, floorY + 1660, lampZ], '#f8f5ee', 'ceramic', { shape: 'sphere', scaleY: 0.55 }));

  // ---------- oliwka w kamiennej donicy ----------
  const pX = -W / 2 + 900;
  const pZ = D / 2 - 800;
  out.push(B('pot', 'panel', [420, 460, 420], [pX, floorY + 230, pZ], '#c2bba9', 'stone', { shape: 'cylinder', detail: 26 }));
  out.push(B('olive-trunk', 'panel', [70, 900, 70], [pX, floorY + 900, pZ], '#6b5a45', 'wood-dark', { shape: 'cylinder', detail: 12 }));
  let seed = 7;
  const rnd2 = () => {
    seed = (seed * 16807) % 2147483647;
    return (seed - 1) / 2147483646;
  };
  for (let i = 0; i < 22; i++) {
    const a = rnd2() * Math.PI * 2;
    const rad = 120 + rnd2() * 300;
    const y = 1250 + rnd2() * 780;
    const sz = 150 + rnd2() * 190;
    out.push(
      B(
        `olive-leaf-${i}`,
        'panel',
        [sz, sz * 0.72, sz],
        [pX + Math.cos(a) * rad, floorY + y, pZ + Math.sin(a) * rad],
        `rgb(${92 + Math.round(rnd2() * 28)},${108 + Math.round(rnd2() * 30)},${68 + Math.round(rnd2() * 22)})`,
        'foliage',
        { shape: 'sphere' },
      ),
    );
  }

  // ---------- komoda pod ścianą + obraz ----------
  const sbW = 2200;
  const sbZ = -D / 2 + 300;
  out.push(B('sideboard', 'panel', [sbW, 700, 450], [0, floorY + 350, sbZ], '#cbb69b', 'wood', { bevel: 6 }));
  for (let i = 0; i < 4; i++) {
    out.push(B(`sideboard-drawer-${i}`, 'front', [sbW / 4 - 20, 620, 20], [-sbW / 2 + (sbW / 4) * i + sbW / 8, floorY + 360, sbZ + 235], '#d3bfa5', 'wood', { bevel: 3 }));
  }
  out.push(B('art', 'panel', [1600, 1100, 40], [0, floorY + 1750, -D / 2 + 40], '#e6dccd', 'plaster'));

  return out;
}
