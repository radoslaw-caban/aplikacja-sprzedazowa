import type { SceneBox } from './types';

/**
 * Katalog okuć z realnymi wymiarami producentów (mm).
 * Wszystko budowane jako bryły — renderer nie zna pojęcia „zawias".
 *
 * Źródła wymiarów:
 *  - Blum CLIP top BLUMOTION 71B3550: kielich Ø 35 mm, głęb. 11,5 mm, kąt 110°, pełne nakładanie
 *  - Blum LEGRABOX: N 66,5 / M 90,5 / K 128,5 / C 177 mm; NL 270–650
 *  - Hettich AvanTech YOU: 77 / 101 / 139 / 187 / 251 mm
 *  - Blum TANDEMBOX antaro: N 83 / M 115 / K 149 / L 183 mm
 *  - nóżki regulowane Ø 50 mm, 100–150 mm
 *  - uchwyty: reling Ø 12 mm, 128/160/192/320 mm; gałka Ø 30 mm
 */

export type HandleType = 'bar' | 'cup' | 'edge' | 'knob' | 'none';
export type RunnerSystem = 'legrabox' | 'tandembox' | 'antaro' | 'aventech' | 'none';

export const HANDLE_SPECS: Record<Exclude<HandleType, 'none'>, { label: string; depth: number; height: number }> = {
  bar: { label: 'Reling Ø12 (128–320 mm)', depth: 32, height: 12 },
  cup: { label: 'Uchwyt muszlowy 96 mm', depth: 26, height: 14 },
  edge: { label: 'Uchwyt krawędziowy (frez)', depth: 12, height: 22 },
  knob: { label: 'Gałka Ø30', depth: 28, height: 30 },
};

/** Systemy szuflad z realnymi wysokościami boków. */
export const RUNNER_SPECS: Record<Exclude<RunnerSystem, 'none'>, { label: string; heights: Record<string, number> }> = {
  legrabox: { label: 'Blum LEGRABOX', heights: { N: 66.5, M: 90.5, K: 128.5, C: 177 } },
  tandembox: { label: 'Blum TANDEMBOX antaro', heights: { N: 83, M: 115, K: 149, L: 183 } },
  antaro: { label: 'Blum antaro (profil)', heights: { N: 83, M: 115, K: 149, L: 183 } },
  aventech: { label: 'Hettich AvanTech YOU', heights: { '77': 77, '101': 101, '139': 139, '187': 187, '251': 251 } },
};

/** Uchwyt na froncie: reling z dwoma trzpieniami, muszla, frez lub gałka. */
export function handleBoxes(
  frontId: string,
  type: HandleType,
  size: [number, number],
  pos: [number, number, number],
  color = '#b9bcc1',
): SceneBox[] {
  if (type === 'none') return [];
  const out: SceneBox[] = [];
  const [w, h] = size;
  const [x, y, z] = pos;

  if (type === 'bar') {
    const len = Math.min(Math.max(w * 0.55, 128), 320);
    // reling: cylinder obrócony w osi X (poziomo wzdłuż frontu)
    out.push({
      id: `${frontId}:handle`,
      kind: 'handle',
      cabinetId: frontId.split('-')[0],
      frontId,
      size: [12, len, 12],
      position: [x, y, z + 30],
      color,
      mat: 'metal',
      shape: 'cylinder',
      outline: false,
      rotationZ: 90,
    });
    // trzpienie: cylinder w osi Z (od frontu do relingu)
    for (const s of [-1, 1]) {
      out.push({
        id: `${frontId}:handle-post${s > 0 ? 'r' : 'l'}`,
        kind: 'handle',
        cabinetId: frontId.split('-')[0],
        frontId,
        size: [10, 26, 10],
        position: [x + (s * len) / 2.2, y, z + 14],
        color,
        mat: 'metal',
        shape: 'cylinder',
        outline: false,
        rotationX: 90,
      });
    }
  } else if (type === 'knob') {
    out.push({
      id: `${frontId}:knob`,
      kind: 'handle',
      cabinetId: frontId.split('-')[0],
      frontId,
      size: [30, 34, 30],
      position: [x, y, z + 17],
      color,
      mat: 'metal',
      shape: 'cylinder',
      outline: false,
    });
  } else if (type === 'cup') {
    out.push({
      id: `${frontId}:cup`,
      kind: 'handle',
      cabinetId: frontId.split('-')[0],
      frontId,
      size: [96, 16, 24],
      position: [x, y, z + 12],
      color,
      mat: 'metal',
      outline: false,
    });
  } else {
    // edge: frez w krawędzi — ciemna szczelina
    out.push({
      id: `${frontId}:edge`,
      kind: 'handle',
      cabinetId: frontId.split('-')[0],
      frontId,
      size: [Math.min(w * 0.6, 300), 22, 8],
      position: [x, y + h / 2 - 30, z + 2],
      color: '#1a1a1a',
      outline: false,
    });
  }
  return out;
}

/**
 * Zawias Blum CLIP top BLUMOTION: kielich Ø 35 × 11,5 mm na froncie,
 * ramię do korpusu i płytka montażowa.
 */
export function hingeBoxes(
  cabinetId: string,
  side: 'left' | 'right',
  x: number,
  y: number,
  zFront: number,
  depth: number,
): SceneBox[] {
  const sign = side === 'left' ? -1 : 1;
  const cupX = x + sign * 21.5;
  return [
    // kielich w drzwiach
    {
      id: `${cabinetId}:hinge-cup-${side}-${y}`,
      kind: 'handle',
      cabinetId,
      size: [35, 35, 13],
      position: [cupX, y, zFront - 24],
      color: '#9aa0a6',
      mat: 'metal',
      shape: 'cylinder',
      outline: false,
      rotationX: 90,
    } as SceneBox,
    // ramię zawiasu (do wnętrza korpusu)
    {
      id: `${cabinetId}:hinge-arm-${side}-${y}`,
      kind: 'handle',
      cabinetId,
      size: [16, 22, depth * 0.35],
      position: [cupX, y - 6, zFront - 40],
      color: '#8d939a',
      mat: 'metal',
      outline: false,
    },
    // płytka montażowa na boku
    {
      id: `${cabinetId}:hinge-plate-${side}-${y}`,
      kind: 'handle',
      cabinetId,
      size: [8, 32, 48],
      position: [x + sign * 60, y - 8, zFront - 52],
      color: '#7f858c',
      mat: 'metal',
      outline: false,
    },
  ];
}

/**
 * Prowadnica szuflady: szyna + bok systemu (LEGRABOX itp.)
 * Bok ma realną wysokość systemu (N/M/K/C) i wykończenie metaliczne.
 */
export function runnerBoxes(
  cabinetId: string,
  system: Exclude<RunnerSystem, 'none'>,
  level: string,
  y: number,
  innerWidth: number,
  innerDepth: number,
  zBack: number,
  color = '#8d9298',
): SceneBox[] {
  const h = RUNNER_SPECS[system].heights[level] ?? 90.5;
  const out: SceneBox[] = [];
  for (const s of [-1, 1]) {
    // bok systemu
    out.push({
      id: `${cabinetId}:runner-side-${s}-${y}`,
      kind: 'handle',
      cabinetId,
      size: [16, h, innerDepth - 20],
      position: [s * (innerWidth / 2 - 8), y + h / 2, zBack + innerDepth / 2],
      color,
      mat: 'metal',
      outline: false,
    });
    // szyna teleskopowa (węższa, pod bokiem)
    out.push({
      id: `${cabinetId}:runner-rail-${s}-${y}`,
      kind: 'handle',
      cabinetId,
      size: [10, 18, innerDepth - 40],
      position: [s * (innerWidth / 2 - 20), y + 9, zBack + innerDepth / 2],
      color: '#6f747a',
      mat: 'metal',
      outline: false,
    });
  }
  return out;
}

/** Nóżki regulowane pod korpusem (Ø50, wysokość z cokołu). */
export function legBoxes(cabinetId: string, width: number, depth: number, height: number): SceneBox[] {
  const out: SceneBox[] = [];
  const xs = [-width / 2 + 60, width / 2 - 60];
  const zs = [-depth / 2 + 60, depth / 2 - 60];
  for (const x of xs) {
    for (const z of zs) {
      out.push({
        id: `${cabinetId}:leg-${x}-${z}`,
        kind: 'handle',
        cabinetId,
        size: [50, height, 50],
        position: [x, height / 2, z],
        color: '#3a3d42',
        mat: 'metal',
        shape: 'cylinder',
        outline: false,
      });
    }
  }
  return out;
}

/** Wieszak ścienny szafki górnej (Blum/Häfele typowy). */
export function hangerBoxes(cabinetId: string, width: number, y: number, z: number): SceneBox[] {
  const out: SceneBox[] = [];
  for (const s of [-1, 1]) {
    out.push({
      id: `${cabinetId}:hanger-${s}`,
      kind: 'handle',
      cabinetId,
      size: [20, 90, 22],
      position: [s * (width / 2 - 80), y, z],
      color: '#7f858c',
      mat: 'metal',
      outline: false,
    });
  }
  return out;
}

/** Wsporniki półek Ø5 mm (4 szt. na półkę). */
export function shelfPinBoxes(cabinetId: string, width: number, y: number, z: number): SceneBox[] {
  const out: SceneBox[] = [];
  for (const sx of [-1, 1]) {
    for (const sz of [-1, 1]) {
      out.push({
        id: `${cabinetId}:pin-${sx}-${sz}-${y}`,
        kind: 'handle',
        cabinetId,
        size: [5, 5, 12],
        position: [sx * (width / 2 - 30), y, z + sz * 40],
        color: '#c9ced6',
        mat: 'metal',
        shape: 'cylinder',
        outline: false,
      });
    }
  }
  return out;
}
