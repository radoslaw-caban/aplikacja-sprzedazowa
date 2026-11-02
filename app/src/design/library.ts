import { baseCabinet, type Cabinet } from './types';

/** Biblioteka szablonów szafek — przeciągane na projekt, auto-dociągane do sąsiada. */
export interface CabinetTemplate {
  key: string;
  label: string;
  make: () => Cabinet;
}

export const CABINET_TEMPLATES: CabinetTemplate[] = [
  {
    key: 'base-400',
    label: 'Dolna 400',
    make: () => ({ ...baseCabinet(), width: 400, name: 'Dolna 400' }),
  },
  {
    key: 'base-600',
    label: 'Dolna 600',
    make: () => ({ ...baseCabinet(), width: 600, name: 'Dolna 600' }),
  },
  {
    key: 'base-800',
    label: 'Dolna 800',
    make: () => ({ ...baseCabinet(), width: 800, name: 'Dolna 800', doors: 2 }),
  },
  {
    key: 'base-drawers',
    label: 'Dolna 600 / 3 szuflady',
    make: () => {
      const c = { ...baseCabinet(), width: 600, name: 'Dolna 600 / 3 szuflady', doors: 0 };
      c.elements = [
        { id: `${c.id}-ds`, kind: 'drawerSystem', y: 0, x0: 0, x1: 0, variant: '3' },
      ];
      return c;
    },
  },
  {
    key: 'sink-800',
    label: 'Dolna 800 / zlew',
    make: () => ({ ...baseCabinet(), width: 800, name: 'Dolna 800 / zlew', doors: 2 }),
  },
  {
    key: 'wall-600',
    label: 'Górna 600',
    make: () => ({
      ...baseCabinet(),
      type: 'wall',
      width: 600,
      height: 720,
      depth: 350,
      name: 'Górna 600',
    }),
  },
  {
    key: 'wall-900',
    label: 'Górna 900',
    make: () => ({
      ...baseCabinet(),
      type: 'wall',
      width: 900,
      height: 720,
      depth: 350,
      doors: 2,
      name: 'Górna 900',
    }),
  },
  {
    key: 'tall-600',
    label: 'Słupek 600',
    make: () => ({
      ...baseCabinet(),
      type: 'tall',
      width: 600,
      height: 2100,
      depth: 600,
      doors: 2,
      name: 'Słupek 600',
    }),
  },
];

/** Elementy do przeciągania do wnętrza szafki. */
export interface ElementTemplate {
  key: string;
  label: string;
  kind: import('./types').ElementKind;
  variant?: string;
}

export const ELEMENT_TEMPLATES: ElementTemplate[] = [
  { key: 'shelf', label: 'Półka', kind: 'shelf' },
  { key: 'divider', label: 'Przegroda pionowa', kind: 'divider' },
  { key: 'drawer', label: 'Szuflada', kind: 'drawer' },
  { key: 'innerDrawer', label: 'Szuflada wewnętrzna', kind: 'innerDrawer' },
  { key: 'ds2', label: 'System szuflad ×2', kind: 'drawerSystem', variant: '2' },
  { key: 'ds3', label: 'System szuflad ×3', kind: 'drawerSystem', variant: '3' },
  { key: 'ds4', label: 'System szuflad ×4', kind: 'drawerSystem', variant: '4' },
  { key: 'basket', label: 'Kosz narożny', kind: 'cornerBasket' },
  { key: 'cutlery', label: 'Wkład na sztućce', kind: 'cutlery' },
];

/**
 * Auto-dociąganie: nowa szafka staje obok ostatniej w rzędzie (tym samym z),
 * bez szczelin i bez nakładania. Zwraca pozycję X w mm.
 */
export function snapX(cabinets: Cabinet[], moving: Cabinet, gapMm = 0): number {
  const others = cabinets.filter((c) => c.id !== moving.id && Math.abs(c.z - moving.z) < 1);
  if (!others.length) return moving.x;

  const half = moving.width / 2;
  // najbliższy sąsiad po prawej i po lewej
  const right = others
    .map((c) => c.x + c.width / 2)
    .filter((edge) => edge <= moving.x - half + 1)
    .sort((a, b) => b - a)[0];
  const left = others
    .map((c) => c.x - c.width / 2)
    .filter((edge) => edge >= moving.x + half - 1)
    .sort((a, b) => a - b)[0];

  const snapRight = right !== undefined ? right + gapMm + half : undefined;
  const snapLeft = left !== undefined ? left - gapMm - half : undefined;
  if (snapRight === undefined && snapLeft === undefined) return moving.x;
  const dRight = snapRight !== undefined ? Math.abs(moving.x - snapRight) : Infinity;
  const dLeft = snapLeft !== undefined ? Math.abs(moving.x - snapLeft) : Infinity;
  const best = dRight <= dLeft ? snapRight! : snapLeft!;
  // dociągaj tylko w promieniu 150 mm
  return Math.abs(best - moving.x) < 150 ? best : moving.x;
}

/** Dodaje szafkę na końcu rzędu (używane przy przeciągnięciu z biblioteki). */
export function appendToRow(cabinets: Cabinet[], template: CabinetTemplate, z = 0): Cabinet {
  const c = template.make();
  c.id = 'c' + Math.random().toString(36).slice(2, 8);
  c.z = z;
  const sameRow = cabinets.filter((x) => Math.abs(x.z - z) < 1);
  if (!sameRow.length) {
    c.x = c.width / 2;
  } else {
    const rightmost = sameRow.reduce((m, x) => Math.max(m, x.x + x.width / 2), -Infinity);
    c.x = rightmost + c.width / 2;
  }
  return c;
}
