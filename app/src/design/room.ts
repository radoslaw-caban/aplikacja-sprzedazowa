/**
 * Pomieszczenie testowe 500 × 500 cm: podłoga w jodełkę, 4 ściany,
 * okno i drzwi. Wszystko w MILIMETRACH.
 */
export interface Room {
  /** szerokość (X) i głębokość (Z) w mm */
  width: number;
  depth: number;
  wallHeight: number;
  wallThickness: number;
  /** okno na ścianie północnej (z = 0) */
  window: { x: number; y: number; w: number; h: number; wall: WallSide };
  door: { x: number; y: number; w: number; h: number; wall: WallSide };
  /** odstęp szafek od ściany (mm) */
  wallGap: number;
}

export type WallSide = 'north' | 'south' | 'east' | 'west';

export function defaultRoom(): Room {
  return {
    width: 5000,
    depth: 5000,
    wallHeight: 2600,
    wallThickness: 100,
    window: { x: 3400, y: 900, w: 1500, h: 1400, wall: 'north' },
    door: { x: 600, y: 0, w: 900, h: 2100, wall: 'south' },
    wallGap: 50,
  };
}

export interface RoomBox {
  size: [number, number, number];
  position: [number, number, number];
  color: string;
  opacity?: number;
  kind: 'floor' | 'wall' | 'window' | 'door';
}

/** Geometria pomieszczenia: podłoga + ściany z otworami (jako segmenty). */
export function roomBoxes(r: Room): RoomBox[] {
  const out: RoomBox[] = [];
  const W = r.width;
  const D = r.depth;
  const H = r.wallHeight;
  const T = r.wallThickness;

  // podłoga
  out.push({ kind: 'floor', size: [W, 20, D], position: [0, -10, 0], color: '#6b5844' });

  // ściana północna (z = -D/2), z oknem
  out.push(...wallWithHole('north', r, W, D, H, T));
  // południowa (z = +D/2) z drzwiami
  out.push(...wallWithHole('south', r, W, D, H, T));
  // wschodnia (x = +W/2)
  out.push({
    kind: 'wall', size: [T, H, D], position: [W / 2 + T / 2, H / 2, 0], color: '#8e8a82',
  });
  // zachodnia (x = -W/2)
  out.push({
    kind: 'wall', size: [T, H, D], position: [-W / 2 - T / 2, H / 2, 0], color: '#8e8a82',
  });

  return out;
}

/** Ściana z prostokątnym otworem: 4 segmenty dookoła otworu. */
function wallWithHole(
  side: WallSide,
  r: Room,
  W: number,
  D: number,
  H: number,
  T: number,
): RoomBox[] {
  const out: RoomBox[] = [];
  const hole = side === 'north' ? r.window : r.door;
  const holeLen = hole.w;
  const holeH = hole.h;
  const holeX = hole.x; // od lewej krawędzi ściany
  const holeY = hole.y; // od podłogi

  const len = side === 'north' ? W : W;
  const z = side === 'north' ? -D / 2 - T / 2 : D / 2 + T / 2;
  const color = '#8e8a82';

  // lewy segment (pełna wysokość)
  if (holeX > 0) {
    out.push({
      kind: 'wall',
      size: [holeX, H, T],
      position: [-len / 2 + holeX / 2, H / 2, z],
      color,
    });
  }
  // prawy segment
  const rightW = len - (holeX + holeLen);
  if (rightW > 0) {
    out.push({
      kind: 'wall',
      size: [rightW, H, T],
      position: [len / 2 - rightW / 2, H / 2, z],
      color,
    });
  }
  // pod otworem
  if (holeY > 0) {
    out.push({
      kind: 'wall',
      size: [holeLen, holeY, T],
      position: [-len / 2 + holeX + holeLen / 2, holeY / 2, z],
      color,
    });
  }
  // nad otworem
  const above = H - (holeY + holeH);
  if (above > 0) {
    out.push({
      kind: 'wall',
      size: [holeLen, above, T],
      position: [-len / 2 + holeX + holeLen / 2, holeY + holeH + above / 2, z],
      color,
    });
  }
  // szyba / skrzydło
  if (side === 'north') {
    out.push({
      kind: 'window',
      size: [holeLen, holeH, 20],
      position: [-len / 2 + holeX + holeLen / 2, holeY + holeH / 2, z],
      color: '#7fa4b8',
      opacity: 0.22,
    });
  } else {
    out.push({
      kind: 'door',
      size: [holeLen, holeH, 40],
      position: [-len / 2 + holeX + holeLen / 2, holeY + holeH / 2, z],
      color: '#4a3b2e',
    });
  }
  return out;
}

/**
 * Dociąganie szafek do ścian: tył szafki do ściany z odstępem,
 * szafki narożne do rogów. Zwraca pozycję {x, z, rotation}.
 */
export function snapToWalls(
  r: Room,
  width: number,
  depth: number,
  nearX: number,
  nearZ: number,
): { x: number; z: number; rotation: number } {
  const halfW = width / 2;
  const halfD = depth / 2;
  const gap = r.wallGap;

  // najbliższa ściana
  const distNorth = Math.abs(nearZ - -r.depth / 2);
  const distSouth = Math.abs(nearZ - r.depth / 2);
  const distWest = Math.abs(nearX - -r.width / 2);
  const distEast = Math.abs(nearX - r.width / 2);
  const min = Math.min(distNorth, distSouth, distWest, distEast);

  if (min === distNorth) {
    // tył do ściany północnej: front patrzy na +Z
    return {
      x: clamp(nearX, -r.width / 2 + halfW, r.width / 2 - halfW),
      z: -r.depth / 2 + gap + halfD,
      rotation: 180,
    };
  }
  if (min === distSouth) {
    return {
      x: clamp(nearX, -r.width / 2 + halfW, r.width / 2 - halfW),
      z: r.depth / 2 - gap - halfD,
      rotation: 0,
    };
  }
  if (min === distWest) {
    return {
      x: -r.width / 2 + gap + halfD,
      z: clamp(nearZ, -r.depth / 2 + halfW, r.depth / 2 - halfW),
      rotation: 90,
    };
  }
  return {
    x: r.width / 2 - gap - halfD,
    z: clamp(nearZ, -r.depth / 2 + halfW, r.depth / 2 - halfW),
    rotation: 270,
  };
}

function clamp(v: number, lo: number, hi: number) {
  return Math.max(lo, Math.min(hi, v));
}

/**
 * Czy szafka jest w narożniku pomieszczenia — wtedy dociągamy do obu ścian.
 * Zwraca wyrównaną pozycję i orientację (front wzdłuż wybranej ściany).
 */
export function cornerSnap(
  r: Room,
  width: number,
  depth: number,
  nearX: number,
  nearZ: number,
  frontWall: WallSide,
): { x: number; z: number; rotation: number } {
  const halfW = width / 2;
  const gap = r.wallGap;
  const xSign = nearX < 0 ? -1 : 1;
  const zSign = nearZ < 0 ? -1 : 1;

  // orientacja zależna od ściany, wzdłuż której biegnie front
  const rot = frontWall === 'south' ? 0 : frontWall === 'north' ? 180 : frontWall === 'west' ? 90 : 270;
  const alongX = frontWall === 'north' || frontWall === 'south';
  return {
    x: xSign * (r.width / 2 - (alongX ? halfW : depth / 2) - gap),
    z: zSign * (r.depth / 2 - (alongX ? depth / 2 : halfW) - gap),
    rotation: rot,
  };
}
