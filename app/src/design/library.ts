import {
  baseCabinet,
  makeDoors,
  makeDrawerFronts,
  type Cabinet,
  type CabinetElement,
  type ElementKind,
} from './types';

/**
 * Wstępna baza szafek — standardy europejskie (bezramowe).
 * Wymiary wg katalogów producentów:
 *  - dolne: korpus 720 mm, głęb. 560 mm, cokół 100–150, blat 38 mm
 *  - górne: głęb. 350 mm, wys. 360–864 mm
 *  - słupki: głęb. 561 mm, wys. 2016–2232 mm
 *  - szuflady: szereg Blum LEGRABOX (N 66,5 / M 90,5 / K 128,5; NL 270–650)
 */

export interface CabinetTemplate {
  key: string;
  label: string;
  group: 'dolne' | 'górne' | 'słupki' | 'specjalne';
  width: number;
  make: () => Cabinet;
}

let seq = 0;
const uid = () => `c${Date.now().toString(36)}${(seq++).toString(36)}`;

const el = (kind: ElementKind, y: number, variant?: string): CabinetElement => ({
  id: `e${Math.random().toString(36).slice(2, 8)}`,
  kind,
  y,
  x0: 0,
  x1: 0,
  variant,
});

function baseDoor(width: number, doors: number, name: string): Cabinet {
  const c = baseCabinet(uid(), 0, 0);
  c.width = width;
  c.name = name;
  c.fronts = makeDoors(c, doors);
  return c;
}

/** Szafka dolna z szufladami — wysokości frontów wg systemu Blum. */
function baseDrawers(width: number, heights: number[], name: string): Cabinet {
  const c = baseCabinet(uid(), 0, 0);
  c.width = width;
  c.name = name;
  const els: CabinetElement[] = [];
  let y = 0;
  for (const h of heights) {
    els.push(el('drawer', y, h >= 170 ? 'K' : 'M'));
    y += h + 6;
  }
  c.elements = els;
  c.fronts = makeDrawerFronts(c, heights, els.map((e) => e.id));
  return c;
}

export const CABINET_LIBRARY: CabinetTemplate[] = [
  // ---------- DOLNE ----------
  { key: 'base-300', group: 'dolne', label: 'Dolna 300 / 1 front', width: 300, make: () => baseDoor(300, 1, 'Dolna 300') },
  { key: 'base-400', group: 'dolne', label: 'Dolna 400 / 1 front', width: 400, make: () => baseDoor(400, 1, 'Dolna 400') },
  { key: 'base-450', group: 'dolne', label: 'Dolna 450 / 1 front', width: 450, make: () => baseDoor(450, 1, 'Dolna 450') },
  { key: 'base-500', group: 'dolne', label: 'Dolna 500 / 1 front', width: 500, make: () => baseDoor(500, 1, 'Dolna 500') },
  { key: 'base-600', group: 'dolne', label: 'Dolna 600 / 1 front', width: 600, make: () => baseDoor(600, 1, 'Dolna 600') },
  { key: 'base-800', group: 'dolne', label: 'Dolna 800 / 2 fronty', width: 800, make: () => baseDoor(800, 2, 'Dolna 800') },
  { key: 'base-900', group: 'dolne', label: 'Dolna 900 / 2 fronty', width: 900, make: () => baseDoor(900, 2, 'Dolna 900') },
  { key: 'base-1000', group: 'dolne', label: 'Dolna 1000 / 2 fronty', width: 1000, make: () => baseDoor(1000, 2, 'Dolna 1000') },
  { key: 'base-1200', group: 'dolne', label: 'Dolna 1200 / 3 fronty', width: 1200, make: () => baseDoor(1200, 3, 'Dolna 1200') },

  { key: 'drawer-600-2', group: 'dolne', label: 'Dolna 600 / 2 szuflady', width: 600, make: () => baseDrawers(600, [280, 280], 'Dolna 600 / 2 szuflady') },
  { key: 'drawer-600-3', group: 'dolne', label: 'Dolna 600 / 3 szuflady', width: 600, make: () => baseDrawers(600, [220, 220, 220], 'Dolna 600 / 3 szuflady') },
  { key: 'drawer-600-4', group: 'dolne', label: 'Dolna 600 / 4 szuflady', width: 600, make: () => baseDrawers(600, [176, 176, 176, 176], 'Dolna 600 / 4 szuflady') },
  { key: 'drawer-800-3', group: 'dolne', label: 'Dolna 800 / 3 szuflady', width: 800, make: () => baseDrawers(800, [220, 220, 220], 'Dolna 800 / 3 szuflady') },

  {
    key: 'sink-800', group: 'dolne', label: 'Dolna 800 / zlew', width: 800,
    make: () => {
      const c = baseDoor(800, 2, 'Dolna 800 / zlew');
      c.elements = [el('shelf', 0)];
      return c;
    },
  },
  {
    key: 'hob-600', group: 'dolne', label: 'Dolna 600 / płyta', width: 600,
    make: () => {
      const c = baseDoor(600, 1, 'Dolna 600 / płyta');
      c.elements = [el('drawer', 0, 'K')];
      return c;
    },
  },
  {
    key: 'cargo-300', group: 'dolne', label: 'Dolna 300 / cargo', width: 300,
    make: () => {
      const c = baseDoor(300, 0, 'Dolna 300 / cargo');
      c.fronts = [];
      c.elements = [el('drawer', 0, 'K'), el('drawer', 350, 'K')];
      return c;
    },
  },

  // ---------- GÓRNE ----------
  {
    key: 'wall-400', group: 'górne', label: 'Górna 400', width: 400,
    make: () => {
      const c = baseDoor(400, 1, 'Górna 400');
      c.type = 'wall'; c.height = 720; c.depth = 350; c.worktop = false; c.plinth = 0;
      c.elements = [el('shelf', 340)];
      c.fronts = makeDoors(c, 1);
      return c;
    },
  },
  {
    key: 'wall-600', group: 'górne', label: 'Górna 600', width: 600,
    make: () => {
      const c = baseDoor(600, 1, 'Górna 600');
      c.type = 'wall'; c.height = 720; c.depth = 350; c.worktop = false; c.plinth = 0;
      c.elements = [el('shelf', 340)];
      c.fronts = makeDoors(c, 1);
      return c;
    },
  },
  {
    key: 'wall-800', group: 'górne', label: 'Górna 800 / 2 fronty', width: 800,
    make: () => {
      const c = baseDoor(800, 2, 'Górna 800');
      c.type = 'wall'; c.height = 720; c.depth = 350; c.worktop = false; c.plinth = 0;
      c.elements = [el('shelf', 340)];
      c.fronts = makeDoors(c, 2);
      return c;
    },
  },
  {
    key: 'wall-600-lift', group: 'górne', label: 'Górna 600 / podnośna', width: 600,
    make: () => {
      const c = baseDoor(600, 1, 'Górna 600 / podnośna');
      c.type = 'wall'; c.height = 490; c.depth = 350; c.worktop = false; c.plinth = 0;
      c.fronts = makeDoors(c, 1);
      return c;
    },
  },

  // ---------- SŁUPKI ----------
  {
    key: 'tall-600', group: 'słupki', label: 'Słupek 600', width: 600,
    make: () => {
      const c = baseDoor(600, 2, 'Słupek 600');
      c.type = 'tall'; c.height = 2100; c.depth = 561;
      c.elements = [el('shelf', 700), el('shelf', 1400)];
      c.fronts = makeDoors(c, 2);
      return c;
    },
  },
  {
    key: 'tall-600-oven', group: 'słupki', label: 'Słupek 600 / piekarnik', width: 600,
    make: () => {
      const c = baseDoor(600, 2, 'Słupek 600 / piekarnik');
      c.type = 'tall'; c.height = 2100; c.depth = 561;
      c.elements = [el('shelf', 1200), el('shelf', 1800)];
      c.fronts = makeDoors(c, 2);
      return c;
    },
  },
  {
    key: 'tall-450', group: 'słupki', label: 'Słupek 450 / spiżarnia', width: 450,
    make: () => {
      const c = baseDoor(450, 1, 'Słupek 450 / spiżarnia');
      c.type = 'tall'; c.height = 2100; c.depth = 561;
      c.elements = [el('shelf', 900), el('shelf', 1500)];
      c.fronts = makeDoors(c, 1);
      return c;
    },
  },

  // ---------- SPECJALNE ----------
  {
    key: 'corner-carousel', group: 'specjalne', label: 'Narożna / kosz obrotowy', width: 900,
    make: () => {
      const c = baseDoor(900, 1, 'Narożna / kosz');
      c.elements = [el('cornerBasket', 100), el('cornerBasket', 500)];
      return c;
    },
  },
  {
    key: 'sink-double', group: 'specjalne', label: 'Dolna 900 / 2 zlewy', width: 900,
    make: () => {
      const c = baseDoor(900, 2, 'Dolna 900 / 2 zlewy');
      c.elements = [el('shelf', 0), el('divider', 0)];
      return c;
    },
  },
  {
    key: 'open-600', group: 'specjalne', label: 'Dolna 600 / otwarta', width: 600,
    make: () => {
      const c = baseDoor(600, 0, 'Dolna 600 / otwarta');
      c.fronts = [];
      c.elements = [el('shelf', 340)];
      return c;
    },
  },
];

export const LIBRARY_GROUPS = ['dolne', 'górne', 'słupki', 'specjalne'] as const;

export function byGroup(g: string) {
  return CABINET_LIBRARY.filter((t) => t.group === g);
}

/** Elementy wnętrza do biblioteki. */
export interface ElementTemplate {
  key: string;
  label: string;
  kind: ElementKind;
  variant?: string;
}

export const ELEMENT_TEMPLATES: ElementTemplate[] = [
  { key: 'shelf', label: 'Półka', kind: 'shelf' },
  { key: 'divider', label: 'Przegroda pionowa', kind: 'divider' },
  { key: 'drawer-N', label: 'Szuflada N (66,5)', kind: 'drawer', variant: 'N' },
  { key: 'drawer-M', label: 'Szuflada M (90,5)', kind: 'drawer', variant: 'M' },
  { key: 'drawer-K', label: 'Szuflada K (128,5)', kind: 'drawer', variant: 'K' },
  { key: 'innerDrawer', label: 'Szuflada wewnętrzna', kind: 'innerDrawer', variant: 'M' },
  { key: 'ds2', label: 'System szuflad ×2', kind: 'drawerSystem', variant: '2' },
  { key: 'ds3', label: 'System szuflad ×3', kind: 'drawerSystem', variant: '3' },
  { key: 'ds4', label: 'System szuflad ×4', kind: 'drawerSystem', variant: '4' },
  { key: 'basket', label: 'Kosz narożny', kind: 'cornerBasket' },
  { key: 'cutlery', label: 'Wkład na sztućce', kind: 'cutlery' },
];

/**
 * Inteligentne dociąganie: szafka trafia do NAJBLIŻSZEGO końca istniejącego mebla
 * (lewy lub prawy koniec rzędu), a nie na jego koniec z definicji.
 * Nie ma pojęcia „element zamykający" — mebel jest zbiorem szafek, do którego
 * nowa szafka dokleja się z wybranej strony. Zwraca pozycję X (mm).
 */
export function attachX(
  cabinets: Cabinet[],
  moving: Cabinet,
  side: 'left' | 'right',
  gapMm = 0,
): number {
  const row = cabinets.filter((c) => c.id !== moving.id && Math.abs(c.z - moving.z) < 1);
  const half = moving.width / 2;
  if (!row.length) return half;

  const minX = Math.min(...row.map((c) => c.x - c.width / 2));
  const maxX = Math.max(...row.map((c) => c.x + c.width / 2));
  return side === 'left' ? minX - gapMm - half : maxX + gapMm + half;
}

/** Nowa szafka dokleja się do bliższego końca mebla (domyślnie prawy). */
export function appendToRowBySide(
  cabinets: Cabinet[],
  template: CabinetTemplate,
  side: 'left' | 'right' = 'right',
  z = 0,
): Cabinet {
  const c = template.make();
  c.z = z;
  c.x = attachX(cabinets, c, side);
  return c;
}

/** Auto-dociąganie w rzędzie — bez szczelin i nakładania. */
export function snapX(cabinets: Cabinet[], moving: Cabinet, gapMm = 0): number {
  const others = cabinets.filter((c) => c.id !== moving.id && Math.abs(c.z - moving.z) < 1);
  if (!others.length) return moving.x;
  const half = moving.width / 2;
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
  return Math.abs(best - moving.x) < 150 ? best : moving.x;
}

/** Wstawia szafkę na końcu rzędu. */
export function appendToRow(cabinets: Cabinet[], template: CabinetTemplate, z = 0): Cabinet {
  const c = template.make();
  c.z = z;
  const sameRow = cabinets.filter((x) => Math.abs(x.z - z) < 1);
  if (!sameRow.length) c.x = c.width / 2;
  else {
    const rightmost = sameRow.reduce((m, x) => Math.max(m, x.x + x.width / 2), -Infinity);
    c.x = rightmost + c.width / 2;
  }
  return c;
}

/** Podsumowanie wnętrza — do podglądu i wyceny. */
export interface InteriorSummary {
  shelves: number;
  drawers: number;
  innerDrawers: number;
  dividers: number;
  baskets: number;
  cutlery: number;
  panelArea: number;
  drawerRunners: number;
}

export function summarize(c: Cabinet): InteriorSummary {
  const s: InteriorSummary = {
    shelves: 0, drawers: 0, innerDrawers: 0, dividers: 0,
    baskets: 0, cutlery: 0, panelArea: 0, drawerRunners: 0,
  };
  for (const e of c.elements) {
    if (e.kind === 'shelf') s.shelves++;
    else if (e.kind === 'drawer') { s.drawers++; s.drawerRunners++; }
    else if (e.kind === 'innerDrawer') { s.innerDrawers++; s.drawerRunners++; }
    else if (e.kind === 'divider') s.dividers++;
    else if (e.kind === 'cornerBasket') s.baskets++;
    else if (e.kind === 'cutlery') s.cutlery++;
    else if (e.kind === 'drawerSystem') {
      const n = e.variant === '2' ? 2 : e.variant === '4' ? 4 : 3;
      s.drawers += n;
      s.drawerRunners += n;
    }
  }
  const W = c.width, H = c.height, D = c.depth;
  let area = 2 * (D * H) + 2 * ((W - 36) * D);
  area += s.shelves * ((W - 36) * (D - 4));
  s.panelArea = area / 1e6;
  return s;
}
