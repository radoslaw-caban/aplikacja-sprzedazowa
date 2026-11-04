import type { Cabinet, CabinetElement } from './types';
import { innerHeight, innerWidth } from './generator';

/**
 * Kolizje i dociąganie — wspólne dla układu szafek i wnętrza.
 * Wszystko w mm.
 */

export interface Rect {
  x0: number;
  x1: number;
  z0: number;
  z1: number;
}

/** Obrys szafki na planie (uwzględnia obrót 90/270). */
export function cabinetRect(c: Cabinet): Rect {
  const swap = c.rotation === 90 || c.rotation === 270;
  const w = swap ? c.depth : c.width;
  const d = swap ? c.width : c.depth;
  return { x0: c.x - w / 2, x1: c.x + w / 2, z0: c.z - d / 2, z1: c.z + d / 2 };
}

function overlap(a: Rect, b: Rect, tol = 1): boolean {
  return a.x0 < b.x1 - tol && b.x0 < a.x1 - tol && a.z0 < b.z1 - tol && b.z0 < a.z1 - tol;
}

/** Czy nowa/patchowana szafka koliduje z istniejącymi. */
export function collidesWithCabinets(cabinets: Cabinet[], candidate: Cabinet): boolean {
  const a = cabinetRect(candidate);
  return cabinets.some((c) => c.id !== candidate.id && overlap(a, cabinetRect(c)));
}

/**
 * Kolizje wnętrza: elementy w tej samej kolumnie (x) i tej samej warstwie (y)
 * nie mogą na siebie nachodzić. Zwraca true, gdy nowy element koliduje.
 */
export function elementCollides(
  c: Cabinet,
  candidate: CabinetElement,
  ignoreId?: string,
): boolean {
  const innerW = innerWidth(c);
  const spanX = candidate.x1 > candidate.x0 ? candidate.x1 - candidate.x0 : innerW;
  const x0 = candidate.x1 > candidate.x0 ? candidate.x0 : 0;
  const a = {
    x0,
    x1: x0 + spanX,
    y0: candidate.y,
    y1: candidate.y + elementHeight(c, candidate),
  };

  for (const e of c.elements) {
    if (e.id === ignoreId) continue;
    const eSpanX = e.x1 > e.x0 ? e.x1 - e.x0 : innerW;
    const eX0 = e.x1 > e.x0 ? e.x0 : 0;
    const b = {
      x0: eX0,
      x1: eX0 + eSpanX,
      y0: e.y,
      y1: e.y + elementHeight(c, e),
    };
    if (a.x0 < b.x1 - 1 && b.x0 < a.x1 - 1 && a.y0 < b.y1 - 1 && b.y0 < a.y1 - 1) return true;
  }
  return false;
}

/** Wysokość zajmowana przez element (do sprawdzania kolizji). */
export function elementHeight(c: Cabinet, e: CabinetElement): number {
  switch (e.kind) {
    case 'shelf':
    case 'divider':
      return 18;
    case 'drawer':
    case 'innerDrawer':
      return e.variant === 'N' ? 66.5 : e.variant === 'K' ? 128.5 : 90.5;
    case 'drawerSystem':
      return innerHeight(c) - e.y;
    case 'cornerBasket':
      return 110;
    case 'cutlery':
      return 40;
    default:
      return 18;
  }
}

/** Najbliższa wolna pozycja Y dla nowego elementu (od dołu). */
export function findFreeY(c: Cabinet, candidate: CabinetElement): number | null {
  const limit = innerHeight(c) - 20;
  for (let y = 0; y <= limit; y += 32) {
    const test = { ...candidate, y };
    if (!elementCollides(c, test)) return y;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Dociąganie szafek: krawędzie i narożniki (każdy z każdym w projekcie)
// ---------------------------------------------------------------------------

export interface SnapResult {
  x: number;
  z: number;
  /** które krawędzie się złapały (do narysowania linii) */
  guides: { axis: 'x' | 'z'; value: number; from: number; to: number }[];
}

const SNAP_TOL = 60; // mm

/**
 * Dociąganie do krawędzi i narożników innych szafek:
 * porównuje lewą/prawą krawędź i tył/przód kandydata z krawędziami sąsiadów.
 */
export function snapCabinet(
  cabinets: Cabinet[],
  candidate: Cabinet,
): SnapResult {
  const r = cabinetRect(candidate);
  const guides: SnapResult['guides'] = [];
  let x = candidate.x;
  let z = candidate.z;

  let bestDx = SNAP_TOL;
  let bestDz = SNAP_TOL;

  for (const o of cabinets) {
    if (o.id === candidate.id) continue;
    const or = cabinetRect(o);

    // dopasowanie w osi X: lewa do lewej, prawa do prawej, prawa do lewej itd.
    const pairsX: [number, number][] = [
      [r.x0, or.x0],
      [r.x1, or.x1],
      [r.x1, or.x0],
      [r.x0, or.x1],
    ];
    for (const [mine, theirs] of pairsX) {
      const d = Math.abs(mine - theirs);
      if (d < bestDx) {
        bestDx = d;
        x = candidate.x + (theirs - mine);
        guides.push({ axis: 'x', value: theirs, from: Math.min(r.z0, or.z0), to: Math.max(r.z1, or.z1) });
      }
    }

    // dopasowanie w osi Z: tył/przód
    const pairsZ: [number, number][] = [
      [r.z0, or.z0],
      [r.z1, or.z1],
      [r.z1, or.z0],
      [r.z0, or.z1],
    ];
    for (const [mine, theirs] of pairsZ) {
      const d = Math.abs(mine - theirs);
      if (d < bestDz) {
        bestDz = d;
        z = candidate.z + (theirs - mine);
        guides.push({ axis: 'z', value: theirs, from: Math.min(r.x0, or.x0), to: Math.max(r.x1, or.x1) });
      }
    }
  }

  return { x, z, guides: guides.slice(-2) };
}
