import type { Cabinet, CabinetElement, ElementKind } from './types';

/**
 * Automatyczne rozczytanie modelu szafki (GLB/GLTF/dostarczony opis brył).
 *
 * Zasada: nie zgadujemy „na oko" — mierzymy bryły i klasyfikujemy je po
 * proporcjach, orientacji i położeniu, według reguł konstrukcji mebli
 * bezramowych (płyta 18 mm, plecy 4 mm, wcięcie 3 mm).
 *
 * Wynik: szafka parametryczna (szer./wys./gł.) + lista elementów z nazwami
 * i przypisanymi rolami, gotowa do dalszej edycji w aplikacji.
 */

export interface RawPart {
  name?: string;
  /** wymiary bryły w mm */
  size: [number, number, number];
  /** środek bryły w mm, w układzie modelu */
  center: [number, number, number];
}

export type PartRole =
  | 'bok-lewy'
  | 'bok-prawy'
  | 'dno'
  | 'wieniec'
  | 'plecy'
  | 'półka'
  | 'przegroda'
  | 'front'
  | 'szuflada'
  | 'cokół'
  | 'blat'
  | 'nieznany';

export interface ParsedPart extends RawPart {
  role: PartRole;
  /** czytelna nazwa po polsku, z numeracją */
  label: string;
  /** grubość płyty wykryta z bryły */
  thickness: number;
  confidence: number;
}

export interface ParsedCabinet {
  width: number;
  height: number;
  depth: number;
  panel: number;
  parts: ParsedPart[];
  elements: CabinetElement[];
  warnings: string[];
}

const TOL = 2.5;

function dominantAxis(size: [number, number, number]): 0 | 1 | 2 {
  const i = size.indexOf(Math.max(...size));
  return i as 0 | 1 | 2;
}

/**
 * Klasyfikuje bryły i buduje parametryczną szafkę.
 * `axisMap` pozwala przestawić osie, jeśli model ma inną orientację (Y do góry / Z do góry).
 */
export function parseCabinetParts(
  parts: RawPart[],
  opts: { up?: 'y' | 'z'; panel?: number } = {},
): ParsedCabinet {
  const panel = opts.panel ?? 18;
  const warnings: string[] = [];
  if (!parts.length) {
    return { width: 0, height: 0, depth: 0, panel, parts: [], elements: [], warnings: ['Brak brył w modelu'] };
  }

  // 1. obrys całego modelu
  const min: [number, number, number] = [Infinity, Infinity, Infinity];
  const max: [number, number, number] = [-Infinity, -Infinity, -Infinity];
  for (const p of parts) {
    for (let a = 0; a < 3; a++) {
      min[a] = Math.min(min[a], p.center[a] - p.size[a] / 2);
      max[a] = Math.max(max[a], p.center[a] + p.size[a] / 2);
    }
  }
  const W = max[0] - min[0];
  const H = opts.up === 'z' ? max[2] - min[2] : max[1] - min[1];
  const D = opts.up === 'z' ? max[1] - min[1] : max[2] - min[2];
  const cx = (min[0] + max[0]) / 2;
  const cz = (min[2] + max[2]) / 2;

  // 2. klasyfikacja
  const out: ParsedPart[] = [];
  let shelfNo = 0;
  let drawerNo = 0;

  for (const p of parts) {
    const [sx, sy, sz] = p.size;
    const ax = dominantAxis(p.size);
    const thick = Math.min(sx, sy, sz);
    const relY = (p.center[1] - min[1]) / Math.max(1, H); // 0 = dół, 1 = góra
    const relZ = (p.center[2] - cz) / Math.max(1, D); // +1 przód, -1 tył
    const relX = (p.center[0] - cx) / Math.max(1, W);

    let role: PartRole = 'nieznany';
    let confidence = 0.45;

    if (sz <= 8 && Math.abs(relZ) > 0.25) {
      role = 'plecy';
      confidence = 0.95;
    } else if (thick <= 6 && sz > sy && sx > sy) {
      role = 'cokół';
      confidence = 0.6;
    } else if (ax === 0 && sx <= panel + TOL && Math.abs(relX) > 0.35) {
      // pionowa płyta po boku
      role = relX < 0 ? 'bok-lewy' : 'bok-prawy';
      confidence = 0.97;
    } else if (ax === 1 && sy <= panel + TOL) {
      // pozioma płyta
      if (relY < 0.08) {
        role = 'dno';
        confidence = 0.95;
      } else if (relY > 0.92) {
        role = 'wieniec';
        confidence = 0.95;
      } else {
        role = 'półka';
        shelfNo++;
        confidence = 0.85;
      }
    } else if (ax === 2 && sz <= panel + TOL) {
      // pionowa w poprzek, cienka w głąb
      if (relZ > 0.3) {
        role = 'front';
        confidence = 0.9;
      } else if (Math.abs(relX) < 0.3) {
        role = 'przegroda';
        confidence = 0.8;
      } else {
        role = 'bok-lewy';
        confidence = 0.4;
      }
    } else if (relZ > 0.35 && sy < H * 0.45) {
      role = 'szuflada';
      drawerNo++;
      confidence = 0.7;
    } else if (sy > H * 0.9 && sz > D * 0.9) {
      role = 'blat';
      confidence = 0.7;
    }

    const base = p.name?.trim();

    out.push({
      ...p,
      role,
      label: labelFor(role, shelfNo, drawerNo, base),
      thickness: Math.round(thick * 10) / 10,
      confidence,
    });
  }

  // 3. ostrzeżenia o nietypowych proporcjach
  const sides = out.filter((p) => p.role === 'bok-lewy' || p.role === 'bok-prawy').length;
  if (sides < 2) warnings.push('Nie znaleziono dwóch boków — sprawdź orientację modelu (up: y/z)');
  if (!out.some((p) => p.role === 'dno')) warnings.push('Brak dna — model może być niepełny');
  if (out.some((p) => p.confidence < 0.5)) warnings.push('Część brył jest niepewna — sprawdź nazwy ręcznie');

  // 4. elementy wnętrza (półki/przegrody/szuflady) → parametryczne elementy szafki
  const elements: CabinetElement[] = [];
  for (const p of out) {
    if (p.role === 'półka') {
      elements.push({ id: `e${elements.length}`, kind: 'shelf', y: Math.round(p.center[1] - min[1]), x0: 0, x1: 0 });
    } else if (p.role === 'przegroda') {
      elements.push({ id: `e${elements.length}`, kind: 'divider', y: 0, x0: 0, x1: 0 });
    } else if (p.role === 'szuflada') {
      elements.push({ id: `e${elements.length}`, kind: 'drawer', y: Math.round(p.center[1] - min[1]), x0: 0, x1: 0, variant: 'M' });
    }
  }

  return {
    width: Math.round(W),
    height: Math.round(H),
    depth: Math.round(D),
    panel: Math.round(median(out.map((p) => p.thickness)) ?? panel),
    parts: out,
    elements,
    warnings,
  };
}

function median(v: number[]): number | null {
  if (!v.length) return null;
  const s = [...v].sort((a, b) => a - b);
  return s[Math.floor(s.length / 2)];
}

function labelFor(role: PartRole, shelfNo: number, drawerNo: number, original?: string): string {
  switch (role) {
    case 'bok-lewy':
      return 'Bok lewy';
    case 'bok-prawy':
      return 'Bok prawy';
    case 'dno':
      return 'Dno';
    case 'wieniec':
      return 'Wieniec górny';
    case 'plecy':
      return 'Plecy (4 mm)';
    case 'półka':
      return `Półka ${shelfNo}`;
    case 'przegroda':
      return 'Przegroda pionowa';
    case 'front':
      return 'Front';
    case 'szuflada':
      return `Szuflada ${drawerNo}`;
    case 'cokół':
      return 'Cokół';
    case 'blat':
      return 'Blat';
    default:
      return original ? `Nieznany: ${original}` : 'Nieznany element';
  }
}

/** Buduje gotową szafkę z rozczytanego modelu. */
export function toCabinet(c: ParsedCabinet, name: string, id: string): Cabinet {
  const isTall = c.height > 1200;
  return {
    id,
    name,
    type: isTall ? 'tall' : 'base',
    width: c.width,
    height: c.height,
    depth: c.depth,
    x: 0,
    z: 0,
    rotation: 0,
    elements: c.elements,
    fronts: [],
    cutouts: [],
    plinth: isTall ? 150 : 150,
    worktop: false,
    backGap: 50,
    detail: 'basic',
    handle: 'bar',
    runner: 'legrabox',
  };
}

/** Rolna podpowiedź dla nieznanych brył — do ręcznego dopisania w UI. */
export const ROLE_OPTIONS: { id: PartRole; label: string }[] = [
  { id: 'bok-lewy', label: 'Bok lewy' },
  { id: 'bok-prawy', label: 'Bok prawy' },
  { id: 'dno', label: 'Dno' },
  { id: 'wieniec', label: 'Wieniec górny' },
  { id: 'plecy', label: 'Plecy' },
  { id: 'półka', label: 'Półka' },
  { id: 'przegroda', label: 'Przegroda' },
  { id: 'front', label: 'Front' },
  { id: 'szuflada', label: 'Szuflada' },
  { id: 'cokół', label: 'Cokół' },
  { id: 'blat', label: 'Blat' },
  { id: 'nieznany', label: 'Nieznany' },
];

export type { ElementKind };
