import {
  baseCabinet,
  makeDoors,
  type Cabinet,
  type CabinetElement,
  type ElementKind,
} from './types';

/**
 * Baza szafek — standardy europejskie (bezramowe), wymiary z katalogów producentów:
 *
 *  PODBLATOWE: korpus 720 mm, głęb. 560 mm, nóżki 100–150, blat 38 → 908 mm
 *              szerokości 150 / 300 / 400 / 450 / 500 / 600 / 700 / 800 / 900 / 1000 / 1200
 *  WISZĄCE:    głęb. 350 mm, wys. 575 / 720 / 900 mm
 *  SŁUPKI:     głęb. 561 mm, korpus 2016 / 2216 mm
 *  Szuflady:   Blum LEGRABOX N 66,5 / M 90,5 / K 128,5 / C 177
 *              Blum TANDEMBOX antaro N 68,5 / M 83,6 / K 149 / L 183
 *              Hettich AvanTech YOU 77 / 101 / 139 / 187 / 251
 *  Zawiasy:    Blum CLIP top BLUMOTION 71B3550 — kielich Ø 35 × 11,5, kąt 110°
 */

export interface CabinetTemplate {
  key: string;
  label: string;
  group: 'podblatowe' | 'stojace' | 'górne' | 'słupki' | 'dojscie' | 'specjalne';
  /** kategoria decyduje o wymuszonych elementach (blat, cokół) */
  category: 'podblatowa' | 'wisząca' | 'słupek' | 'stojąca' | 'z dojściem' | 'specjalna';
  width: number;
  /** krótki opis do podpowiedzi w bibliotece */
  hint?: string;
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

// ---------------------------------------------------------------------------
// Konstruktory
// ---------------------------------------------------------------------------

function mkBase(width: number, doors: number, name: string, opts: Partial<Cabinet> = {}): Cabinet {
  const c = baseCabinet(uid(), 0, 0);
  c.width = width;
  c.name = name;
  c.fronts = makeDoors(c, doors);
  Object.assign(c, opts);
  return c;
}

/** Szafka dolna z szufladami — wysokości frontów wg systemu Blum. */
function mkDrawers(width: number, heights: number[], name: string): Cabinet {
  const c = baseCabinet(uid(), 0, 0);
  c.width = width;
  c.name = name;
  c.runner = 'legrabox';
  const els: CabinetElement[] = [];
  const fronts: Cabinet['fronts'] = [];
  let y = 0;
  for (const h of heights) {
    els.push(el('drawer', y, h >= 160 ? 'K' : h >= 85 ? 'M' : 'N'));
    fronts.push({
      id: `${c.id}-dr${fronts.length}`,
      kind: 'drawer',
      x0: 3,
      x1: width - 3,
      y0: y,
      y1: y + h,
      open: 0,
    });
    y += h + 6;
  }
  c.elements = els;
  c.fronts = fronts;
  return c;
}

function mkWall(
  width: number,
  doors: number,
  height: number,
  name: string,
  opts: Partial<Cabinet> = {},
): Cabinet {
  const c = baseCabinet(uid(), 0, 0);
  c.width = width;
  c.name = name;
  c.type = 'wall';
  c.height = height;
  c.depth = 350;
  c.plinth = 0;
  c.worktop = false;
  c.mountHeight = 1500;
  c.elements = [el('shelf', height * 0.45)];
  c.fronts = makeDoors(c, doors);
  Object.assign(c, opts);
  return c;
}

function mkTall(width: number, doors: number, height: number, name: string): Cabinet {
  const c = baseCabinet(uid(), 0, 0);
  c.width = width;
  c.name = name;
  c.type = 'tall';
  c.height = height;
  c.depth = 561;
  c.plinth = 150;
  c.worktop = false;
  c.elements = [el('shelf', height * 0.35), el('shelf', height * 0.62)];
  c.fronts = makeDoors(c, doors);
  return c;
}

// ---------------------------------------------------------------------------
// KATALOG
// ---------------------------------------------------------------------------

export const CABINET_LIBRARY: CabinetTemplate[] = [
  // ======================= PODBLATOWE =======================
  { key: 'base-150', group: 'podblatowe', category: 'podblatowa', width: 150, label: 'Dolna 150 (wąska)', hint: 'Pojemnik na wąskie dodatki', make: () => mkBase(150, 1, 'Dolna 150') },
  { key: 'base-300', group: 'podblatowe', category: 'podblatowa', width: 300, label: 'Dolna 300 / 1 front', hint: 'Standard wąski', make: () => mkBase(300, 1, 'Dolna 300') },
  { key: 'base-400', group: 'podblatowe', category: 'podblatowa', width: 400, label: 'Dolna 400 / 1 front', hint: 'Standard', make: () => mkBase(400, 1, 'Dolna 400') },
  { key: 'base-450', group: 'podblatowe', category: 'podblatowa', width: 450, label: 'Dolna 450 / 1 front', hint: 'Standard', make: () => mkBase(450, 1, 'Dolna 450') },
  { key: 'base-500', group: 'podblatowe', category: 'podblatowa', width: 500, label: 'Dolna 500 / 1 front', hint: 'Standard', make: () => mkBase(500, 1, 'Dolna 500') },
  { key: 'base-600', group: 'podblatowe', category: 'podblatowa', width: 600, label: 'Dolna 600 / 1 front', hint: 'Moduł podstawowy 600', make: () => mkBase(600, 1, 'Dolna 600') },
  {
    key: 'base-600-2d', group: 'podblatowe', category: 'podblatowa', width: 600, label: 'Dolna 600 / 2 fronty',
    hint: 'Dwie półfronty + przegroda', make: () => {
      const c = mkBase(600, 2, 'Dolna 600 / 2 fronty');
      c.elements = [el('shelf', 0), el('divider', 0)];
      return c;
    },
  },
  { key: 'base-600-3dr', group: 'podblatowe', category: 'podblatowa', width: 600, label: 'Dolna 600 / 3 szuflady', hint: 'Blum LEGRABOX M 90,5', make: () => mkDrawers(600, [128, 128, 128], 'Dolna 600 / 3 szuflady') },
  { key: 'base-600-4dr', group: 'podblatowe', category: 'podblatowa', width: 600, label: 'Dolna 600 / 4 szuflady', hint: 'Blum LEGRABOX N 66,5', make: () => mkDrawers(600, [128, 90, 90, 90], 'Dolna 600 / 4 szuflady') },
  {
    key: 'base-600-oven', group: 'podblatowe', category: 'podblatowa', width: 600, label: 'Dolna 600 / piekarnik',
    hint: 'Nisza piekarnika 595×595 pod blatem', make: () => {
      const c = mkBase(600, 0, 'Dolna 600 / piekarnik');
      c.fronts = [];
      c.elements = [el('shelf', 600)];
      return c;
    },
  },
  { key: 'base-700', group: 'podblatowe', category: 'podblatowa', width: 700, label: 'Dolna 700 / 2 fronty', hint: 'Standard', make: () => mkBase(700, 2, 'Dolna 700') },
  { key: 'base-800', group: 'podblatowe', category: 'podblatowa', width: 800, label: 'Dolna 800 / 2 fronty', hint: 'Szafa zlewowa / duża', make: () => mkBase(800, 2, 'Dolna 800') },
  { key: 'base-800-dr', group: 'podblatowe', category: 'podblatowa', width: 800, label: 'Dolna 800 / 3 szuflady K', hint: 'Blum LEGRABOX K 128,5', make: () => mkDrawers(800, [180, 180, 180], 'Dolna 800 / 3 szuflady') },
  {
    key: 'base-900-sink', group: 'podblatowe', category: 'podblatowa', width: 900, label: 'Dolna 900 / zlew',
    hint: 'Dno wzmocnione, miejsce na syfon', make: () => {
      const c = mkBase(900, 2, 'Dolna 900 / zlew');
      c.elements = [];
      return c;
    },
  },
  { key: 'base-900-hob', group: 'podblatowe', category: 'podblatowa', width: 900, label: 'Dolna 900 / płyta', hint: 'Szuflady pod płytą indukcyjną', make: () => mkDrawers(900, [150, 240, 240], 'Dolna 900 / płyta') },
  { key: 'base-1000', group: 'podblatowe', category: 'podblatowa', width: 1000, label: 'Dolna 1000 / 2 fronty', hint: 'Standard szeroki', make: () => mkBase(1000, 2, 'Dolna 1000') },
  { key: 'base-1200', group: 'podblatowe', category: 'podblatowa', width: 1200, label: 'Dolna 1200 / 3 fronty', hint: 'Maksymalna szerokość modułu', make: () => mkBase(1200, 3, 'Dolna 1200') },
  {
    key: 'base-600-dw', group: 'podblatowe', category: 'podblatowa', width: 600, label: 'Zmywarka 600',
    hint: 'Miejsce na zmywarkę pod blatem', make: () => {
      const c = mkBase(600, 0, 'Zmywarka 600');
      c.fronts = [];
      c.plinth = 0;
      return c;
    },
  },
  {
    key: 'base-600-bin', group: 'podblatowe', category: 'podblatowa', width: 600, label: 'Dolna 600 / kosze',
    hint: 'Wyciągane kosze na odpady', make: () => {
      const c = mkBase(600, 1, 'Dolna 600 / kosze');
      c.elements = [el('cornerBasket', 0)];
      return c;
    },
  },
  {
    key: 'corner-900', group: 'podblatowe', category: 'podblatowa', width: 900, label: 'Narożna 900 / karuzela',
    hint: 'Karuzela narożna', make: () => {
      const c = mkBase(900, 1, 'Narożna 900');
      c.elements = [el('cornerBasket', 300)];
      return c;
    },
  },
  {
    key: 'corner-blind', group: 'podblatowe', category: 'podblatowa', width: 900, label: 'Narożna 900 / ślepa',
    hint: 'Narożnik z dostępem jednostronnym', make: () => {
      const c = mkBase(900, 1, 'Narożna 900 / ślepa');
      c.elements = [el('shelf', 300)];
      return c;
    },
  },

  // ======================= STOJĄCE WYSOKIE =======================
  { key: 'standing-400', group: 'stojace', category: 'stojąca', width: 400, label: 'Stojąca 400 (bez blatu)', hint: 'Korpus 2016, cokół 150', make: () => mkTall(400, 1, 2016, 'Stojąca 400') },
  { key: 'standing-600', group: 'stojace', category: 'stojąca', width: 600, label: 'Stojąca 600 (bez blatu)', hint: 'Korpus 2016, cokół 150', make: () => mkTall(600, 2, 2016, 'Stojąca 600') },
  { key: 'standing-600-h', group: 'stojace', category: 'stojąca', width: 600, label: 'Stojąca 600 / 2216', hint: 'Wysoka pod sufit z cokołem', make: () => mkTall(600, 2, 2216, 'Stojąca 600 / 2216') },
  { key: 'standing-900', group: 'stojace', category: 'stojąca', width: 900, label: 'Stojąca 900 / 3 fronty', hint: 'Spiżarka szeroka', make: () => mkTall(900, 3, 2016, 'Stojąca 900') },

  // ======================= WISZĄCE =======================
  { key: 'wall-300', group: 'górne', category: 'wisząca', width: 300, label: 'Wisząca 300', hint: 'Głęb. 350, wys. 720', make: () => mkWall(300, 1, 720, 'Wisząca 300') },
  { key: 'wall-400', group: 'górne', category: 'wisząca', width: 400, label: 'Wisząca 400', hint: 'Głęb. 350, wys. 720', make: () => mkWall(400, 1, 720, 'Wisząca 400') },
  { key: 'wall-500', group: 'górne', category: 'wisząca', width: 500, label: 'Wisząca 500', hint: 'Głęb. 350, wys. 720', make: () => mkWall(500, 1, 720, 'Wisząca 500') },
  { key: 'wall-600', group: 'górne', category: 'wisząca', width: 600, label: 'Wisząca 600', hint: 'Głęb. 350, wys. 720', make: () => mkWall(600, 1, 720, 'Wisząca 600') },
  { key: 'wall-600-lift', group: 'górne', category: 'wisząca', width: 600, label: 'Wisząca 600 / podnośna', hint: 'AVENTOS HL — front podnoszony', make: () => mkWall(600, 0, 720, 'Wisząca 600 / podnośna') },
  {
    key: 'wall-600-filler', group: 'górne', category: 'wisząca', width: 600, label: 'Wisząca 600 + zaślepka',
    hint: '60 cm nad blatem, zaślepka 480 mm', make: () => {
      const c = mkWall(600, 1, 720, 'Wisząca 600 + zaślepka');
      c.mountHeight = 1500;
      c.topFiller = 480;
      return c;
    },
  },
  { key: 'wall-800', group: 'górne', category: 'wisząca', width: 800, label: 'Wisząca 800 / 2 fronty', hint: 'Głęb. 350, wys. 720', make: () => mkWall(800, 2, 720, 'Wisząca 800') },
  { key: 'wall-900', group: 'górne', category: 'wisząca', width: 900, label: 'Wisząca 900 / 2 fronty', hint: 'Głęb. 350, wys. 720', make: () => mkWall(900, 2, 720, 'Wisząca 900') },
  { key: 'wall-600-low', group: 'górne', category: 'wisząca', width: 600, label: 'Wisząca 600 / 575', hint: 'Nad okapem, wys. 575', make: () => mkWall(600, 1, 575, 'Wisząca 600 / 575') },
  { key: 'wall-600-high', group: 'górne', category: 'wisząca', width: 600, label: 'Wisząca 600 / 900', hint: 'Wyższa wersja — do 900', make: () => mkWall(600, 1, 900, 'Wisząca 600 / 900') },
  {
    key: 'sink-600', group: 'górne', category: 'wisząca', width: 600, label: 'Pod umywalkę 600',
    hint: 'Korpus 720×500, bez cokołu', make: () => {
      const c = mkBase(600, 0, 'Pod umywalkę 600');
      c.height = 720;
      c.depth = 500;
      c.plinth = 0;
      c.worktop = true;
      c.fronts = [];
      return c;
    },
  },

  // ======================= SŁUPKI =======================
  {
    key: 'tall-600-oven', group: 'słupki', category: 'słupek', width: 600, label: 'Słupek 600 / piekarnik',
    hint: 'Nisza 595×595, wys. 2016', make: () => {
      const c = mkTall(600, 2, 2016, 'Słupek 600 / piekarnik');
      c.elements = [el('shelf', 950), el('drawer', 150, 'M')];
      return c;
    },
  },
  { key: 'tall-450', group: 'słupki', category: 'słupek', width: 450, label: 'Słupek 450 / spiżarnia', hint: 'Wysuwane kosze, wys. 2016', make: () => mkTall(450, 1, 2016, 'Słupek 450 / spiżarnia') },
  {
    key: 'tall-600-fridge', group: 'słupki', category: 'słupek', width: 600, label: 'Słupek 600 / lodówka',
    hint: 'Zabudowa lodówki, wys. 2216', make: () => {
      const c = mkTall(600, 2, 2216, 'Słupek 600 / lodówka');
      c.elements = [];
      return c;
    },
  },
  {
    key: 'tall-600-micro', group: 'słupki', category: 'słupek', width: 600, label: 'Słupek 600 / mikrofala',
    hint: 'Nisza mikrofali nad piekarnikiem', make: () => {
      const c = mkTall(600, 2, 2216, 'Słupek 600 / mikrofala');
      c.elements = [el('shelf', 1350)];
      return c;
    },
  },

  // ======================= Z DOJŚCIEM =======================
  {
    key: 'access-600', group: 'dojscie', category: 'z dojściem', width: 600, label: 'Szafka z dojściem 600',
    hint: 'Otwarta wnęka — pion, licznik', make: () => {
      const c = mkBase(600, 0, 'Z dojściem 600');
      c.fronts = [];
      c.elements = [el('shelf', 340)];
      c.accessWidth = 600;
      return c;
    },
  },
  {
    key: 'access-900', group: 'dojscie', category: 'z dojściem', width: 900, label: 'Szafka z dojściem 900',
    hint: 'Pod pion kanalizacyjny / licznik', make: () => {
      const c = mkBase(900, 0, 'Z dojściem 900');
      c.fronts = [];
      c.accessWidth = 900;
      return c;
    },
  },

  // ======================= SPECJALNE =======================
  {
    key: 'open-600', group: 'specjalne', category: 'specjalna', width: 600, label: 'Dolna 600 / otwarta',
    hint: 'Bez frontów — ekspozycja', make: () => {
      const c = mkBase(600, 0, 'Dolna 600 / otwarta');
      c.elements = [el('shelf', 340)];
      return c;
    },
  },
  {
    key: 'wine-600', group: 'specjalne', category: 'specjalna', width: 600, label: 'Słupek 600 / witryna na wino',
    hint: 'Półki na butelki', make: () => {
      const c = mkTall(600, 0, 2016, 'Witryna na wino');
      c.fronts = [];
      c.elements = [el('shelf', 300), el('shelf', 600), el('shelf', 900), el('shelf', 1200)];
      return c;
    },
  },
  {
    key: 'micro-600', group: 'specjalne', category: 'specjalna', width: 600, label: 'Wisząca 600 / mikrofala',
    hint: 'Nisza mikrofali w ciągu górnym', make: () => {
      const c = mkWall(600, 1, 720, 'Wisząca 600 / mikrofala');
      c.elements = [];
      return c;
    },
  },
];

export const LIBRARY_GROUPS = ['podblatowe', 'stojace', 'górne', 'słupki', 'dojscie', 'specjalne'] as const;

/** Etykiety kategorii widoczne w bibliotece. */
export const GROUP_LABELS: Record<string, string> = {
  podblatowe: 'Szafki podblatowe',
  stojace: 'Szafki stojące wysokie',
  górne: 'Szafki wiszące',
  słupki: 'Słupki',
  dojscie: 'Szafki z dojściem',
  specjalne: 'Specjalne',
};

/**
 * Reguły kategorii:
 *  - podblatowa: ZAWSZE blat i cokół (osobne, łączone obiekty)
 *  - stojąca:    BEZ blatu, Z cokołem
 *  - słupek:     cokół, bez blatu
 *  - wisząca:    bez blatu i cokołu, na wysokości montażu
 */
export const CATEGORY_RULES = {
  podblatowa: { forcedWorktop: true, forcedPlinth: true },
  stojąca: { forcedWorktop: false, forcedPlinth: true },
  wisząca: { forcedWorktop: false, forcedPlinth: false },
  słupek: { forcedWorktop: false, forcedPlinth: true },
  'z dojściem': { forcedWorktop: true, forcedPlinth: true },
  specjalna: { forcedWorktop: false, forcedPlinth: false },
};

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
 * Inteligentne dociąganie: szafka trafia do NAJBLIŻSZEGO końca istniejącego mebla.
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
