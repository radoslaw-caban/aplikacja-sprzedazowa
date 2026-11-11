/**
 * STREFY ZABUDOWY — czyste reguły projektowania (bez zależności od renderera).
 *
 * Ten plik celowo nie importuje niczego runtime (tylko typy sąsiednich modułów),
 * dzięki czemu reguły dają się testować w Node bez budowania aplikacji.
 *
 * Zasada: strefa = ściana + odpowiedzi → deterministyczny plan (lista szafek).
 * Wymiary oparte na standardzie produkcyjnym:
 *  - korpus dolny 720 mm, głębokość 560 mm, blat 38 mm, cokół 80–220 mm
 *  - szafka górna: głębokość 350 mm, wysokość 720 mm, montaż 600 mm nad blatem
 *  - słupek: głębokość 561 mm, wysokość 2216 mm (lub do sufitu)
 *  - szafa: 600 mm (otwierana) / 650 mm (przesuwna)
 */

export type ZoneKind =
  | 'kitchen-cook'
  | 'kitchen-clean'
  | 'kitchen-tall'
  | 'kitchen-island'
  | 'wardrobe-hinged'
  | 'wardrobe-sliding'
  | 'living-tv'
  | 'bathroom';

export type ZoneGroup = 'kuchnia' | 'sypialnia' | 'salon' | 'łazienka';
export type ZoneAnswers = Record<string, string | number | boolean>;

export type ApplianceKind =
  | 'sink'
  | 'hob'
  | 'oven'
  | 'microwave'
  | 'fridge'
  | 'hood'
  | 'dishwasher'
  | 'washer'
  | 'tv'
  | 'mirror'
  | 'basin'
  | 'bin';

export const BASE_H = 720;
export const BASE_D = 560;
export const WALL_D = 350;
export const TALL_D = 561;
export const WORKTOP_T = 38;
export const SINK_GAP = 600; // blat → dół szafki górnej

export interface Obstacle {
  kind: 'window' | 'door';
  /** od początku ściany (mm) */
  from: number;
  to: number;
  y0: number;
  y1: number;
}

export interface ZoneContext {
  wallLength: number;
  /** odcinek ściany bez światła drzwi (od, długość) — zabudowa nie wchodzi w skrzydło */
  usableFrom?: number;
  usableLength?: number;
  wallHeight: number;
  /** głębokość pomieszczenia — do ostrzeżeń o wyspie */
  roomDepth: number;
  roomWidth: number;
  obstacles: Obstacle[];
  worktopThickness: number;
}

export interface ZonePart {
  role: string;
  type: 'base' | 'wall' | 'tall';
  /** mm */
  width: number;
  height: number;
  depth: number;
  plinth: number;
  mountHeight: number;
  worktop: boolean;
  label: string;
  /** pozycja w ciągu od początku strefy (mm) */
  at: number;
  doors: number;
  /** wysokości frontów szuflad; puste = brak szuflad */
  drawers: number[];
  interior: 'none' | 'shelf' | 'pantry' | 'glass' | 'rail';
  appliances: ApplianceKind[];
  /** rola dla kamery: sink / hob / oven / fridge / tv / wardrobe / vitrine */
  feature?: string;
  /** blat głębszy niż korpus (wyspa, nawis na siedzenie) */
  worktopDepth?: number;
  /** przesunięcie blatu w głąb (lokalne +z) */
  worktopShift?: number;
  slidingPanels?: number;
  floating?: boolean;
}

export interface ZonePlan {
  parts: ZonePart[];
  start: number;
  width: number;
  notes: string[];
  warnings: string[];
}

export interface ZoneChoice {
  value: string | number | boolean;
  label: string;
  hint?: string;
}

export interface ZoneQuestion {
  id: string;
  label: string;
  help?: string;
  type: 'choice' | 'position';
  choices?: ZoneChoice[];
  min?: number;
  max?: number;
  step?: number;
  unit?: string;
  /** element do zbliżenia kamery */
  feature?: string;
  /** pytanie aktywne tylko przy spełnionym warunku */
  when?: (a: ZoneAnswers) => boolean;
  /** przesuwanie po blacie w 3D (klik / przeciągnięcie) */
  placement?: boolean;
}

export interface ZoneSpec {
  kind: ZoneKind;
  label: string;
  short: string;
  group: ZoneGroup;
  icon: string;
  /** obszerny opis zależności — widoczny w bibliotece */
  description: string;
  relations: string[];
  defaults: ZoneAnswers;
  questions: ZoneQuestion[];
}

// ---------------------------------------------------------------------------
// Pomocnicze
// ---------------------------------------------------------------------------

const num = (a: ZoneAnswers, k: string, d: number) => {
  const v = a[k];
  return typeof v === 'number' && Number.isFinite(v) ? v : d;
};
const str = (a: ZoneAnswers, k: string, d: string) => {
  const v = a[k];
  return typeof v === 'string' ? v : d;
};
const bool = (a: ZoneAnswers, k: string, d: boolean) => {
  const v = a[k];
  return typeof v === 'boolean' ? v : d;
};
const clamp = (v: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, v));
const round50 = (v: number) => Math.round(v / 50) * 50;

function basePart(role: string, width: number, o: Partial<ZonePart> = {}): ZonePart {
  return {
    role, type: 'base', width, height: BASE_H, depth: BASE_D,
    plinth: 150, mountHeight: 0, worktop: true, label: 'Szafka dolna',
    at: 0, doors: 0, drawers: [], interior: 'none', appliances: [], ...o,
  };
}

function wallPart(role: string, width: number, o: Partial<ZonePart> = {}): ZonePart {
  return {
    role, type: 'wall', width, height: 720, depth: WALL_D,
    plinth: 0, mountHeight: 1500, worktop: false, label: 'Szafka górna',
    at: 0, doors: Math.max(1, Math.round(width / 600)), drawers: [], interior: 'shelf',
    appliances: [], ...o,
  };
}

function tallPart(role: string, width: number, o: Partial<ZonePart> = {}): ZonePart {
  return {
    role, type: 'tall', width, height: 2216, depth: TALL_D,
    plinth: 150, mountHeight: 0, worktop: false, label: 'Słupek',
    at: 0, doors: 1, drawers: [], interior: 'shelf', appliances: [], ...o,
  };
}

/** Równe moduły ~600–900 mm, suma dokładnie `total` (mm). */
function splitModules(total: number, n: number): number[] {
  if (n <= 0) return [];
  const base = Math.max(300, round50(total / n));
  const out = new Array(n).fill(base);
  let diff = total - base * n;
  let i = 0;
  let guard = 0;
  while (Math.abs(diff) >= 50 && guard++ < 400) {
    const idx = i % n;
    if (diff > 0) {
      out[idx] += 50;
      diff -= 50;
    } else if (out[idx] > 300) {
      out[idx] -= 50;
      diff += 50;
    }
    i++;
  }
  if (diff !== 0) out[n - 1] += diff;
  return out;
}

function windowBlocks(ctx: ZoneContext, from: number, to: number, y0: number, y1: number) {
  return ctx.obstacles.some(
    (o) => o.kind === 'window' && o.to > from && o.from < to && o.y1 > y0 && o.y0 < y1,
  );
}

function startFor(a: ZoneAnswers, ctx: ZoneContext, width: number, warnings: string[]): number {
  const align = str(a, 'align', 'center');
  const from = ctx.usableFrom ?? 0;
  const len = ctx.usableLength ?? ctx.wallLength;
  const margin = 50;
  const free = Math.max(0, len - margin * 2 - width);
  let start =
    align === 'left' ? from + margin
    : align === 'right' ? from + margin + free
    : from + margin + free / 2;
  start = clamp(start, from, Math.max(from, from + len - width));
  if (width > len + 1) {
    warnings.push(
      `Zabudowa ${Math.round(width)} mm nie mieści się na odcinku ${Math.round(len)} mm — zmniejsz szerokość albo zmień ścianę.`,
    );
  }
  return start;
}

// ---------------------------------------------------------------------------
// Kuchnia — strefa gotowania
// ---------------------------------------------------------------------------

function planCook(a: ZoneAnswers, ctx: ZoneContext): ZonePlan {
  const notes: string[] = [];
  const warnings: string[] = [];
  const worktopH = num(a, 'worktopHeight', 900);
  const plinth = clamp(worktopH - WORKTOP_T - BASE_H, 80, 220);
  if (worktopH - WORKTOP_T - BASE_H < 80) warnings.push('Cokół poniżej 80 mm — sprawdź poziom podłogi.');
  const handleless = str(a, 'fronts', 'handle') === 'handleless';
  const hob = str(a, 'hob', 'induction-600');
  const hobW = hob === 'none' ? 0 : hob === 'induction-800' ? 800 : 600;
  const oven = str(a, 'oven', 'column');
  const micro = str(a, 'microwave', 'above-oven');
  const fridge = str(a, 'fridge', 'built-in');
  const fridgeW = fridge === 'side-by-side' ? 900 : fridge === 'freestanding' ? 700 : fridge === 'built-in' ? 600 : 0;
  const vitrines = bool(a, 'vitrines', true);
  const dw = bool(a, 'dishwasher', true);
  const wallCabs = bool(a, 'wallCabinets', true);
  const hood = hob !== 'none' && str(a, 'hood', 'chimney') !== 'none';
  const hobPos = clamp(num(a, 'hobPos', 50), 0, 100);
  const avail = ctx.usableLength ?? ctx.wallLength;
  let baseTarget = clamp(round50(num(a, 'width', 1800)), 1200, 3600);

  // --- wysoka zabudowa na końcach (witryny po bokach) ---
  const tallH = Math.min(2216, ctx.wallHeight - 40);
  const tallL: ZonePart[] = [];
  const tallR: ZonePart[] = [];
  let vitrinesOn = vitrines;
  const tallRough = fridgeW + (oven === 'column' ? 600 : 0) + (vitrinesOn ? 800 : 0);
  if (avail < tallRough + baseTarget + 100) {
    if (vitrinesOn) {
      vitrinesOn = false;
      warnings.push('Witryny pominięte — ściana za krótka na pełny układ.');
    }
  }
  const tallBase = fridgeW + (oven === 'column' ? 600 : 0);
  if (avail < tallBase + baseTarget + 100) {
    baseTarget = Math.max(1200, round50(avail - tallBase - 100));
    warnings.push('Ciąg dolny dopasowany do wolnego odcinka ściany (drzwi / narożnik).');
  }

  if (vitrinesOn) {
    tallL.push(tallPart('witryna-l', 400, {
      label: 'Witryna szklana 400', height: tallH, doors: 1, interior: 'glass',
      feature: 'vitrine', appliances: [],
    }));
  }
  if (fridgeW) {
    tallL.push(tallPart('fridge', fridgeW, {
      label: `Zabudowa lodówki (${fridge})`, height: tallH,
      doors: fridge === 'side-by-side' ? 2 : 1, appliances: ['fridge'], feature: 'fridge',
      interior: 'none',
    }));
  }
  if (oven === 'column') {
    tallR.push(tallPart('oven', 600, {
      label: 'Słupek piekarnik + mikrofala', height: tallH,
      doors: micro === 'above-oven' ? 2 : 1, interior: 'shelf',
      appliances: micro === 'above-oven' ? ['oven', 'microwave'] : ['oven'],
      feature: 'oven',
    }));
  }
  if (vitrinesOn) {
    tallR.push(tallPart('witryna-p', 400, {
      label: 'Witryna szklana 400', height: tallH, doors: 1, interior: 'glass',
      feature: 'vitrine', appliances: [],
    }));
  }

  const tallLw = tallL.reduce((s, p) => s + p.width, 0);

  // --- ciąg dolny: strefy pracy + płyta (+ zmywarka) ---
  const dwW = dw && baseTarget - hobW - 600 >= 850 ? 600 : 0;
  if (dw && !dwW) warnings.push('Zmywarka pominięta — za mało miejsca w ciągu dolnym.');
  const landTotal = baseTarget - hobW - dwW;
  let wl = Math.max(400, round50((landTotal * hobPos) / 100));
  let wr = landTotal - wl;
  if (wr < 400) {
    wr = Math.max(150, Math.min(400, landTotal - 150));
    wl = landTotal - wr;
  }
  if (hobW && (wl < 400 || wr < 400)) {
    warnings.push('Strefa pracy przy płycie < 400 mm — zwiększ długość ciągu.');
  }

  const parts: ZonePart[] = [...tallL];
  let at = tallLw;
  const baseParts: ZonePart[] = [];
  if (wl > 0) {
    baseParts.push(basePart('landing-l', wl, {
      label: 'Szafka z szufladami (strefa pracy)', plinth, drawers: [128, 128, 128],
      height: BASE_H, feature: 'landing',
    }));
  }
  if (hobW) {
    baseParts.push(basePart('hob', hobW, {
      label: `Szafka pod płytą ${hob === 'induction-800' ? 800 : 600}`, plinth,
      drawers: [90, 240, 240], appliances: ['hob', ...(hood ? (['hood'] as ApplianceKind[]) : [])],
      feature: 'hob', worktop: true,
    }));
  }
  if (wr > 0) {
    baseParts.push(basePart('landing-r', wr, {
      label: 'Szafka z szufladami (strefa pracy)', plinth, drawers: [128, 128, 128],
      feature: 'landing',
    }));
  }
  if (dwW) {
    const p = basePart('dishwasher', dwW, {
      label: 'Zmywarka 600', plinth: plinth, doors: 0, appliances: ['dishwasher'],
      feature: 'dishwasher',
    });
    baseParts.push(p);
  }
  for (const p of baseParts) {
    p.at = at;
    at += p.width;
    parts.push(p);
  }
  for (const p of tallR) {
    p.at = at;
    at += p.width;
    parts.push(p);
  }
  const runWidth = at;

  // --- szafki górne + okap ---
  const wallMount = worktopH + SINK_GAP;
  const wallH = Math.min(720, Math.max(0, ctx.wallHeight - wallMount - 40));
  const wallParts: ZonePart[] = [];
  if (wallCabs && wallH >= 400) {
    for (const p of baseParts) {
      if (p.role !== 'landing-l' && p.role !== 'landing-r') continue;
      const w = Math.min(600, p.width);
      const from = p.at;
      if (windowBlocks(ctx, from, from + w, wallMount, wallMount + wallH)) {
        notes.push('Szafka górna pominięta — okno nad blatem.');
        continue;
      }
      wallParts.push(wallPart(`wall-${p.role}`, w, {
        label: 'Szafka górna 600', height: wallH, mountHeight: wallMount,
        at: from + (p.width - w) / 2,
        interior: 'shelf',
      }));
    }
    if (hobW && !hood) {
      const from = tallLw + wl;
      if (!windowBlocks(ctx, from, from + hobW, wallMount, wallMount + wallH)) {
        wallParts.push(wallPart('wall-hob', Math.min(600, hobW), {
          label: 'Szafka górna nad płytą', height: wallH, mountHeight: wallMount, at: from,
        }));
      }
    }
  } else if (wallCabs) {
    warnings.push('Szafki górne pominięte — za niski sufit.');
  }
  parts.push(...wallParts);

  notes.push(`Blat ${worktopH} mm = cokół ${plinth} + korpus 720 + blat ${WORKTOP_T}.`);
  notes.push(`Strefy pracy: lewa ${Math.round(wl)} / prawa ${Math.round(wr)} mm (min. 400).`);
  if (hood) notes.push('Okap 650 mm nad płytą, komin do sufitu.');
  if (handleless) notes.push('Fronty bezuchwytowe — frez 45°.');
  if (oven === 'column') notes.push('Piekarnik w słupku 600 na wysokości 900–1500 (ergonomia).');

  const start = startFor(a, ctx, runWidth, warnings);
  if (windowBlocks(ctx, start, start + runWidth, 0, ctx.wallHeight)) {
    warnings.push('Okno na ścianie — wysoka zabudowa lub okap zasłoni okno.');
  }
  return { parts, start, width: runWidth, notes, warnings };
}

// ---------------------------------------------------------------------------
// Kuchnia — strefa czystości
// ---------------------------------------------------------------------------

function planClean(a: ZoneAnswers, ctx: ZoneContext): ZonePlan {
  const notes: string[] = [];
  const warnings: string[] = [];
  const worktopH = num(a, 'worktopHeight', 900);
  const plinth = clamp(worktopH - WORKTOP_T - BASE_H, 80, 220);
  const sink = str(a, 'sink', 'one-half');
  const sinkW = sink === 'double' ? 900 : sink === 'one-half' ? 800 : sink === 'single' ? 600 : 0;
  const dw = bool(a, 'dishwasher', true);
  const bin = bool(a, 'bin', true);
  const wallCabs = bool(a, 'wallCabinets', true);
  const tallStorage = bool(a, 'tallStorage', false);
  const sinkPos = clamp(num(a, 'sinkPos', 40), 0, 100);
  const avail = ctx.usableLength ?? ctx.wallLength;
  let total = clamp(round50(num(a, 'width', 1800)), 1200, 4200);
  const tallW = tallStorage ? 600 : 0;
  if (avail < total + tallW + 100) {
    total = Math.max(1200, round50(avail - tallW - 100));
    warnings.push('Ciąg skrócony do wolnego odcinka ściany.');
  }
  if (sinkW === 0) warnings.push('Brak zlewu — to nie jest już strefa czystości.');

  const dwW = dw && sinkW > 0 && total - sinkW - 600 >= 300 ? 600 : 0;
  if (dw && !dwW) warnings.push('Zmywarka pominięta — za mało miejsca obok zlewu.');
  const rest = total - sinkW - dwW;
  const nRest = Math.max(1, Math.round(rest / 700));
  const restW = rest > 0 ? splitModules(rest, nRest) : [];
  const insertIdx = Math.min(restW.length, Math.max(0, Math.round((sinkPos / 100) * restW.length)));

  const parts: ZonePart[] = [];
  let at = 0;
  const addSink = () => {
    if (sinkW <= 0) return;
    const p = basePart('sink', sinkW, {
      label: `Szafka ze zlewem ${sinkW}`, plinth, doors: 2,
      interior: 'none', appliances: ['sink', ...(bin ? (['bin'] as ApplianceKind[]) : [])],
      feature: 'sink',
    });
    p.at = at; at += p.width; parts.push(p);
  };
  const addDw = () => {
    if (!dwW) return;
    const p = basePart('dishwasher', dwW, {
      label: 'Zmywarka 600', plinth, doors: 0, appliances: ['dishwasher'], feature: 'dishwasher',
    });
    p.at = at; at += p.width; parts.push(p);
  };
  for (let i = 0; i < restW.length; i++) {
    if (i === insertIdx) { addSink(); addDw(); }
    const p = basePart(`base-${i}`, restW[i], {
      label: 'Szafka z szufladami', plinth, drawers: [128, 128, 128],
    });
    p.at = at; at += p.width; parts.push(p);
  }
  if (insertIdx >= restW.length) { addSink(); addDw(); }

  // szafka wysoka na końcu
  if (tallW) {
    const p = tallPart('pantry', tallW, {
      label: 'Słupek/spiżarnia 600', height: Math.min(2216, ctx.wallHeight - 40),
      interior: 'pantry', doors: 2, feature: 'pantry',
    });
    p.at = at; at += p.width; parts.push(p);
  }

  // szafki górne nad modułami (z pominięciem okna)
  const wallMount = worktopH + SINK_GAP;
  const wallH = Math.min(720, Math.max(0, ctx.wallHeight - wallMount - 40));
  if (wallCabs && wallH >= 400) {
    for (const p of parts.filter((x) => x.type === 'base' && x.role !== 'sink')) {
      const w = Math.min(600, p.width);
      const from = p.at + (p.width - w) / 2;
      if (windowBlocks(ctx, from, from + w, wallMount, wallMount + wallH)) continue;
      parts.push(wallPart(`wall-${p.role}`, w, {
        label: 'Szafka górna 600', height: wallH, mountHeight: wallMount, at: from,
      }));
    }
    const sinkPart = parts.find((x) => x.role === 'sink');
    if (sinkPart && !windowBlocks(ctx, sinkPart.at, sinkPart.at + sinkPart.width, wallMount, wallMount + wallH)) {
      parts.push(wallPart('wall-sink', Math.min(600, sinkPart.width), {
        label: 'Szafka górna nad zlewem', height: wallH, mountHeight: wallMount,
        at: sinkPart.at + (sinkPart.width - Math.min(600, sinkPart.width)) / 2,
      }));
    } else if (sinkPart) {
      notes.push('Szafka górna nad zlewem pominięta — okno.');
    }
  }

  notes.push('Kosz i syfon pod zlewem, dojście serwisowe 600 mm.');
  notes.push('Zmywarka w promieniu 1200 mm od zlewu (kanalizacja i woda).');
  if (bin) notes.push('Segregacja odpadów w szufladzie pod zlewem.');

  const start = startFor(a, ctx, at, warnings);
  return { parts, start, width: at, notes, warnings };
}

// ---------------------------------------------------------------------------
// Kuchnia — wysoka zabudowa
// ---------------------------------------------------------------------------

function planTall(a: ZoneAnswers, ctx: ZoneContext): ZonePlan {
  const notes: string[] = [];
  const warnings: string[] = [];
  const fridge = str(a, 'fridge', 'built-in');
  const fridgeW = fridge === 'none' ? 0 : fridge === 'side-by-side' ? 900 : fridge === 'freestanding' ? 700 : 600;
  const oven = bool(a, 'oven', true);
  const micro = bool(a, 'microwave', true);
  const pantry = num(a, 'pantryWidth', 600);
  const toCeiling = bool(a, 'toCeiling', true);
  const height = toCeiling ? Math.max(2000, ctx.wallHeight - 40) : 2216;
  const parts: ZonePart[] = [];
  let at = 0;
  if (fridgeW) {
    const p = tallPart('fridge', fridgeW, {
      label: 'Zabudowa lodówki', height, doors: fridge === 'side-by-side' ? 2 : 1,
      appliances: ['fridge'], feature: 'fridge', interior: 'none',
    });
    p.at = at; at += p.width; parts.push(p);
  }
  if (oven) {
    const p = tallPart('oven', 600, {
      label: 'Słupek piekarnik + mikrofala', height, doors: micro ? 2 : 1,
      appliances: micro ? ['oven', 'microwave'] : ['oven'], feature: 'oven', interior: 'shelf',
    });
    p.at = at; at += p.width; parts.push(p);
  }
  if (pantry > 0) {
    const p = tallPart('pantry', pantry, {
      label: `Spiżarnia ${pantry}`, height, doors: pantry >= 900 ? 2 : 1,
      interior: 'pantry', feature: 'pantry',
    });
    p.at = at; at += p.width; parts.push(p);
  }
  if (!at) warnings.push('Pusta strefa — wybierz lodówkę, piekarnik lub spiżarnię.');
  notes.push(`Wysokość ${Math.round(height)} mm ${toCeiling ? '(do sufitu, zaślepka 40 mm)' : '(korpus 2216)'}.`);
  notes.push('Cokół 150 mm, zlicowany z ciągiem dolnym.');
  if (!fridgeW) notes.push('Lodówka poza tą strefą.');
  const start = startFor(a, ctx, at, warnings);
  if (windowBlocks(ctx, start, start + at, 0, ctx.wallHeight)) {
    warnings.push('Okno na ścianie — wysoka zabudowa zasłoni okno.');
  }
  return { parts, start, width: at, notes, warnings };
}

// ---------------------------------------------------------------------------
// Kuchnia — wyspa
// ---------------------------------------------------------------------------

function planIsland(a: ZoneAnswers, ctx: ZoneContext): ZonePlan {
  const notes: string[] = [];
  const warnings: string[] = [];
  const worktopH = num(a, 'worktopHeight', 900);
  const plinth = clamp(worktopH - WORKTOP_T - BASE_H, 80, 220);
  const feature = str(a, 'islandFeature', 'hob');
  const seating = bool(a, 'seating', true);
  const len = clamp(round50(num(a, 'width', 2400)), 1800, 3600);
  const depth = 560;
  const worktopDepth = seating ? 860 : 680;
  const overhang = worktopDepth - depth;
  const n = Math.max(2, Math.round(len / 800));
  const widths = splitModules(len, n);
  const featureIdx = Math.floor(n / 2);
  const parts: ZonePart[] = [];
  let at = 0;
  widths.forEach((w, i) => {
    const isFeature = i === featureIdx && feature !== 'none';
    const p = basePart(isFeature ? feature : `island-${i}`, w, {
      label: isFeature ? (feature === 'sink' ? `Wyspa — zlew ${w}` : `Wyspa — płyta ${w}`) : 'Wyspa — szuflady',
      plinth,
      drawers: isFeature ? [90, 240, 240] : [128, 128, 128],
      appliances: isFeature
        ? ([...([feature] as ApplianceKind[]), ...(feature === 'hob' ? (['hood'] as ApplianceKind[]) : [])])
        : [],
      feature: isFeature ? feature : undefined,
      worktopDepth, worktopShift: seating ? overhang / 2 : 0,
      depth,
    });
    p.at = at; at += w; parts.push(p);
  });
  // okap sufitowy nad płytą
  notes.push(`Blat ${worktopH} mm, nawis ${seating ? 300 : 0} mm na siedzenie.`);
  notes.push('Wyspa bez szafek górnych — okap sufitowy, obwód wentylacji.');
  const need = 900 + depth + 100;
  if (ctx.roomDepth < need * 2) {
    warnings.push('Wyspa: przejścia < 900 mm — sprawdź odległość od ścian.');
  }
  // wyspa stoi w świetle pomieszczenia — start liczony po osi ściany
  const start = clamp((ctx.wallLength - len) / 2, 50, Math.max(0, ctx.wallLength - len - 50));
  return { parts, start, width: at, notes, warnings };
}

// ---------------------------------------------------------------------------
// Sypialnia — szafa otwierana / przesuwna
// ---------------------------------------------------------------------------

function wardrobe(a: ZoneAnswers, ctx: ZoneContext, sliding: boolean): ZonePlan {
  const notes: string[] = [];
  const warnings: string[] = [];
  const width = clamp(round50(num(a, 'width', sliding ? 1800 : 1800)), 900, 4200);
  const toCeiling = bool(a, 'toCeiling', true);
  const height = toCeiling ? Math.max(2000, ctx.wallHeight - 40) : 2216;
  const depth = sliding ? 650 : 600;
  const plinth = 100;
  const doorsPerSection = clamp(num(a, 'doors', 2), 1, 4);
  const interior = str(a, 'interior', 'rail');
  const panels = clamp(num(a, 'panels', 2), 2, 3);
  const mirror = bool(a, 'mirror', false);
  const parts: ZonePart[] = [];
  let at = 0;
  if (sliding) {
    const p = tallPart('wardrobe', width, {
      label: `Szafa przesuwna ${width}`, height, depth, plinth,
      doors: 0, slidingPanels: panels, interior: interior === 'shelf' ? 'pantry' : 'rail',
      feature: 'wardrobe',
    });
    p.at = 0;
    parts.push(p);
    at = width;
  } else {
    const sections = Math.max(2, Math.round(width / 550));
    const widths = splitModules(width, sections);
    widths.forEach((w, i) => {
      const p = tallPart(`wardrobe-${i}`, w, {
        label: `Szafa otwierana ${Math.round(w)}`, height, depth, plinth,
        doors: Math.min(doorsPerSection, 2), interior: interior === 'shelf' ? 'pantry' : 'rail',
        feature: 'wardrobe',
      });
      p.at = at; at += w; parts.push(p);
    });
  }
  if (!sliding) {
    notes.push('Wymagane 600 mm wolnej przestrzeni przed frontami (skrzydła 500–600).');
  } else {
    notes.push(`Panel${panels > 2 ? 'e' : ''} przesuwne ${panels} × ~${Math.round(width / panels)} mm, prowadnice góra/dół.`);
    notes.push('Głębokość 650 mm — fronty nie wymagają miejsca na otwieranie.');
    if (mirror) notes.push('Jeden panel lustrzany.');
  }
  notes.push('Wysokość ' + Math.round(height) + ' mm, cokół 100 mm.');
  if (ctx.roomWidth < width + 600 && ctx.roomDepth < width + 600) {
    warnings.push('Sprawdź obejście szafy — min. 600 mm przed frontem.');
  }
  const start = startFor(a, ctx, at, warnings);
  if (windowBlocks(ctx, start, start + at, 0, ctx.wallHeight)) {
    warnings.push('Okno na ścianie — szafa zasłoni okno.');
  }
  return { parts, start, width: at, notes, warnings };
}

// ---------------------------------------------------------------------------
// Salon — strefa RTV
// ---------------------------------------------------------------------------

function planTv(a: ZoneAnswers, ctx: ZoneContext): ZonePlan {
  const notes: string[] = [];
  const warnings: string[] = [];
  const width = clamp(round50(num(a, 'width', 1800)), 1200, 3600);
  const lowH = num(a, 'height', 450);
  const floating = bool(a, 'floating', true);
  const tvSize = num(a, 'tvSize', 65);
  const wallUnit = bool(a, 'wallUnit', true);
  const parts: ZonePart[] = [];
  let at = 0;
  const n = Math.max(2, Math.round(width / 900));
  const widths = splitModules(width, n);
  widths.forEach((w, i) => {
    const p = basePart(`tv-${i}`, w, {
      label: 'Niska szafka RTV', height: lowH, depth: 400, plinth: floating ? 0 : 100,
      mountHeight: floating ? 250 : 0, doors: 2,
      interior: 'shelf', worktop: true, feature: i === Math.floor(n / 2) ? 'tv' : undefined,
    });
    p.at = at; at += w; parts.push(p);
  });
  // TV na środkowej szafce
  const mid = parts.find((p) => p.feature === 'tv');
  if (mid) mid.appliances = ['tv'];
  if (wallUnit) {
    // nadbudowa nad telewizorem: 500 mm zapasu na ekran + 100 mm odstępu
    const mount = lowH + (floating ? 250 : 0) + 1100;
    const wh = Math.min(400, ctx.wallHeight - mount - 60);
    if (wh >= 300) {
      parts.push(wallPart('tv-wall', Math.min(1800, width), {
        label: 'Nadbudowa RTV', height: wh, depth: 350, mountHeight: mount,
        at: (at - Math.min(1800, width)) / 2, doors: 2, interior: 'shelf',
      }));
    } else {
      warnings.push('Nadbudowa RTV pominięta — za nisko sufit.');
    }
  }
  notes.push(`TV ${tvSize}" (${Math.round(tvSize * 22.1)} mm szer.), montaż 1100–1300 mm.`);
  notes.push(floating ? 'Szafka wisząca 250 mm nad podłogą — efekt lekkości, łatwe sprzątanie.' : 'Szafka na cokole 100 mm.');
  notes.push('Przepusty na kable i listwa maskująca w środkowym module.');
  if (tvSize >= 75) notes.push('Przy 75" zalecana odległość oglądania 2200–3000 mm.');
  const start = startFor(a, ctx, at, warnings);
  return { parts, start, width: at, notes, warnings };
}

// ---------------------------------------------------------------------------
// Łazienka
// ---------------------------------------------------------------------------

function planBathroom(a: ZoneAnswers, ctx: ZoneContext): ZonePlan {
  const notes: string[] = [];
  const warnings: string[] = [];
  const vanity = clamp(round50(num(a, 'vanity', 800)), 600, 1600);
  const hanging = bool(a, 'hanging', true);
  const mirror = bool(a, 'mirror', true);
  const tall = bool(a, 'tall', true);
  const worktopH = num(a, 'worktopHeight', 850);
  const plinth = hanging ? 0 : clamp(worktopH - WORKTOP_T - BASE_H, 60, 200);
  const parts: ZonePart[] = [];
  let at = 0;
  const n = Math.max(1, Math.round(vanity / 800));
  const widths = splitModules(vanity, n);
  widths.forEach((w, i) => {
    const p = basePart(`vanity-${i}`, w, {
      label: 'Szafka pod umywalkę', height: BASE_H, depth: 500, plinth,
      mountHeight: hanging ? 300 : 0, doors: 2, interior: 'none',
      appliances: i === 0 ? ['basin'] : [], feature: i === 0 ? 'sink' : undefined,
      worktop: true,
    });
    p.at = at; at += w; parts.push(p);
  });
  if (mirror) {
    const mount = worktopH + 250;
    const h = Math.min(700, ctx.wallHeight - mount - 100);
    if (h >= 400) {
      parts.push(wallPart('mirror', Math.min(vanity, 1000), {
        label: 'Lustro z podświetleniem', height: h, depth: 160, mountHeight: mount,
        doors: 0, interior: 'none', appliances: ['mirror'], at: 0,
      }));
    } else {
      warnings.push('Lustro pominięte — za nisko sufit.');
    }
  }
  if (tall) {
    const p = tallPart('bath-tall', 400, {
      label: 'Słupek łazienkowy 400', height: Math.min(2000, ctx.wallHeight - 60),
      depth: 350, doors: 1, interior: 'shelf', feature: 'pantry',
    });
    p.at = at; at += p.width; parts.push(p);
  }
  notes.push('Strefa mokra: płyta wodoodporna, krawędzie klejone, cokół z PVC.');
  notes.push('Umywalka 850 mm nad podłogą, gniazda poza strefą 1.');
  if (hanging) notes.push('Szafka wisząca 300 mm nad podłogą — dobra wentylacja.');
  const start = startFor(a, ctx, at, warnings);
  return { parts, start, width: at, notes, warnings };
}

// ---------------------------------------------------------------------------
// Biblioteka stref + pytania
// ---------------------------------------------------------------------------

const alignQ: ZoneQuestion = {
  id: 'align', label: 'Ustawienie na ścianie', type: 'choice', feature: 'zone',
  choices: [
    { value: 'left', label: 'Od lewej' },
    { value: 'center', label: 'Na środku' },
    { value: 'right', label: 'Od prawej' },
  ],
};
const frontsQ: ZoneQuestion = {
  id: 'fronts', label: 'Rodzaj frontów', type: 'choice',
  choices: [
    { value: 'handle', label: 'Z uchwytami' },
    { value: 'handleless', label: 'Bezuchwytowe' },
  ],
};
const worktopQ: ZoneQuestion = {
  id: 'worktopHeight', label: 'Wysokość blatu', type: 'choice', feature: 'zone',
  help: 'Cokół liczy się sam: H − 38 mm (blat) − 720 mm (korpus).',
  choices: [
    { value: 860, label: '860 mm — niski' },
    { value: 880, label: '880 mm — kompakt' },
    { value: 900, label: '900 mm — standard' },
    { value: 910, label: '910 mm — wysoki' },
  ],
};

export const ZONE_SPECS: ZoneSpec[] = [
  {
    kind: 'kitchen-cook',
    label: 'Kuchnia — strefa gotowania',
    short: 'Gotowanie',
    group: 'kuchnia',
    icon: '🔥',
    description:
      'Ciąg z płytą grzewczą, strefami pracy po bokach, słupkiem piekarnika i zabudową lodówki. ' +
      'Witryny zamykają meble na obu końcach, okap prowadzi komin do sufitu.',
    relations: [
      'Płyta min. 600 mm, indukcja 800 mm na życzenie; strefy pracy min. 400 mm z każdej strony.',
      'Pod płytą szuflady (nie skrzydła) — dostęp bez schylania, szuflada górna 90 mm.',
      'Okap 650 mm nad płytą; przy braku okapu wymagana wentylacja mechaniczna.',
      'Piekarnik w słupku 600 na wysokości 900–1500 mm; mikrofala nad piekarnikiem.',
      'Lodówka na końcu ciągu (600/700/900), witryny 400 na skrajach.',
      'Szafki górne 600 mm nad blatem, pomijane nad oknem.',
      'Wysokość blatu 860–910 → cokół 80–220 mm liczony automatycznie.',
    ],
    defaults: {
      width: 2400, align: 'center', worktopHeight: 900, fronts: 'handle',
      hob: 'induction-600', hobPos: 50, hood: 'chimney', oven: 'column',
      microwave: 'above-oven', fridge: 'built-in', vitrines: true,
      dishwasher: true, wallCabinets: true,
    },
    questions: [
      { id: 'width', label: 'Długość ciągu dolnego', type: 'choice', feature: 'zone',
        help: 'Wysoka zabudowa i witryny dochodzą po bokach.',
        choices: [
          { value: 1500, label: '1500 mm' }, { value: 1800, label: '1800 mm' },
          { value: 2400, label: '2400 mm' }, { value: 3000, label: '3000 mm' },
        ] },
      alignQ,
      {
        id: 'hob', label: 'Rodzaj płyty grzewczej', type: 'choice', feature: 'hob',
        choices: [
          { value: 'induction-600', label: 'Indukcja 600', hint: 'Standard, 4 pola' },
          { value: 'induction-800', label: 'Indukcja 800', hint: '5 pól, szeroki front' },
          { value: 'gas-600', label: 'Gaz 600', hint: 'Palniki + ruszt' },
          { value: 'none', label: 'Bez płyty', hint: 'Tylko blat roboczy' },
        ],
      },
      {
        id: 'hobPos', label: 'Gdzie płyta na blacie', type: 'position', min: 0, max: 100,
        step: 5, unit: '%', feature: 'hob', placement: true,
        help: 'Przeciągnij po blacie w 3D albo ustaw suwakiem.',
        when: (a) => str(a, 'hob', 'induction-600') !== 'none',
      },
      {
        id: 'hood', label: 'Okap nad płytą', type: 'choice', feature: 'hob',
        choices: [
          { value: 'chimney', label: 'Kominowy' }, { value: 'flat', label: 'Płaski' },
          { value: 'none', label: 'Brak' },
        ],
        when: (a) => str(a, 'hob', 'induction-600') !== 'none',
      },
      {
        id: 'oven', label: 'Piekarnik', type: 'choice', feature: 'oven',
        choices: [
          { value: 'column', label: 'Słupek 600', hint: 'Piekarnik + mikrofala na wysokości' },
          { value: 'under', label: 'Pod blatem', hint: 'Nisza 595×595' },
          { value: 'none', label: 'Brak' },
        ],
      },
      {
        id: 'microwave', label: 'Mikrofala', type: 'choice', feature: 'oven',
        choices: [{ value: 'above-oven', label: 'Nad piekarnikiem' }, { value: 'none', label: 'Brak' }],
        when: (a) => str(a, 'oven', 'column') === 'column',
      },
      {
        id: 'fridge', label: 'Rodzaj lodówki', type: 'choice', feature: 'fridge',
        choices: [
          { value: 'built-in', label: 'Do zabudowy 600' },
          { value: 'freestanding', label: 'Wolnostojąca 700' },
          { value: 'side-by-side', label: 'Side-by-side 900' },
          { value: 'none', label: 'Bez lodówki' },
        ],
      },
      {
        id: 'vitrines', label: 'Witryny na końcu mebli', type: 'choice', feature: 'vitrine',
        choices: [{ value: true, label: 'Tak — 2 × 400 szklane' }, { value: false, label: 'Nie' }],
      },
      {
        id: 'dishwasher', label: 'Zmywarka w ciągu', type: 'choice', feature: 'dishwasher',
        choices: [{ value: true, label: 'Tak 600' }, { value: false, label: 'Nie' }],
      },
      {
        id: 'wallCabinets', label: 'Szafki górne', type: 'choice',
        choices: [{ value: true, label: 'Tak, 600 nad blatem' }, { value: false, label: 'Tylko blat' }],
      },
      worktopQ,
      frontsQ,
    ],
  },
  {
    kind: 'kitchen-clean',
    label: 'Kuchnia — strefa czystości',
    short: 'Czystość',
    group: 'kuchnia',
    icon: '💧',
    description:
      'Zlew, zmywarka i segregacja odpadów w jednym ciągu, z szafkami górnymi ' +
      'pomijającymi okno. Pozycję zlewu przesuwa się po blacie.',
    relations: [
      'Zlew 600/800/900; szafka bez półki (syfon, kosz), dojście serwisowe 600 mm.',
      'Zmywarka 600 w promieniu 1200 mm od zlewu — wspólna woda i kanalizacja.',
      'Kosz na odpady w szufladzie pod zlewem, segregacja 2–3 frakcje.',
      'Szafki górne 600 mm nad blatem; nad oknem pomijane automatycznie.',
      'Min. 400 mm strefy odkładczej przy zlewie.',
      'Blat 860–910 mm, cokół liczony automatycznie.',
    ],
    defaults: {
      width: 2400, align: 'center', worktopHeight: 900, fronts: 'handle',
      sink: 'one-half', sinkPos: 40, dishwasher: true, bin: true,
      wallCabinets: true, tallStorage: false,
    },
    questions: [
      { id: 'width', label: 'Długość ciągu', type: 'choice', feature: 'zone',
        choices: [
          { value: 1200, label: '1200 mm' }, { value: 1800, label: '1800 mm' },
          { value: 2400, label: '2400 mm' }, { value: 3000, label: '3000 mm' },
        ] },
      alignQ,
      {
        id: 'sink', label: 'Rodzaj zlewu', type: 'choice', feature: 'sink',
        choices: [
          { value: 'single', label: '1-komorowy 600' },
          { value: 'one-half', label: '1,5-komorowy 800' },
          { value: 'double', label: '2-komorowy 900' },
          { value: 'none', label: 'Brak zlewu' },
        ],
      },
      {
        id: 'sinkPos', label: 'Gdzie zlew na blacie', type: 'position', min: 0, max: 100,
        step: 5, unit: '%', feature: 'sink', placement: true,
        help: 'Przeciągnij zlew po blacie w 3D albo ustaw suwakiem.',
        when: (a) => str(a, 'sink', 'one-half') !== 'none',
      },
      { id: 'dishwasher', label: 'Zmywarka', type: 'choice', feature: 'dishwasher',
        choices: [{ value: true, label: 'Tak 600, obok zlewu' }, { value: false, label: 'Nie' }] },
      { id: 'bin', label: 'Segregacja odpadów pod zlewem', type: 'choice', feature: 'sink',
        choices: [{ value: true, label: 'Tak, 2–3 frakcje' }, { value: false, label: 'Nie' }] },
      { id: 'tallStorage', label: 'Słupek/spiżarnia na końcu', type: 'choice',
        choices: [{ value: true, label: 'Tak 600' }, { value: false, label: 'Nie' }] },
      { id: 'wallCabinets', label: 'Szafki górne', type: 'choice',
        choices: [{ value: true, label: 'Tak' }, { value: false, label: 'Nie' }] },
      worktopQ,
      frontsQ,
    ],
  },
  {
    kind: 'kitchen-tall',
    label: 'Kuchnia — wysoka zabudowa',
    short: 'Wysoka',
    group: 'kuchnia',
    icon: '🗄',
    description:
      'Słupki od lodówki przez piekarnik z mikrofalą do spiżarni. Wysokość 2216 lub do sufitu, ' +
      'cokół zlicowany z ciągiem dolnym.',
    relations: [
      'Lodówka 600/700/900, piekarnik 600, spiżarnia 450/600/900.',
      'Wysokość 2216 mm lub do sufitu (zaślepka 40 mm).',
      'Cokół 150 mm — zlicowany z kuchnią dolną.',
      'Piekarnik 900–1500 mm nad podłogą, mikrofala bezpośrednio nad nim.',
      'Spiżarnia: półki 350 mm, cargo 450/600.',
    ],
    defaults: {
      align: 'left', fridge: 'built-in', oven: true, microwave: true,
      pantryWidth: 600, toCeiling: true,
    },
    questions: [
      alignQ,
      { id: 'fridge', label: 'Rodzaj lodówki', type: 'choice', feature: 'fridge',
        choices: [
          { value: 'built-in', label: 'Do zabudowy 600' },
          { value: 'freestanding', label: 'Wolnostojąca 700' },
          { value: 'side-by-side', label: 'Side-by-side 900' },
          { value: 'none', label: 'Bez lodówki' },
        ] },
      { id: 'oven', label: 'Piekarnik w słupku', type: 'choice', feature: 'oven',
        choices: [{ value: true, label: 'Tak 600' }, { value: false, label: 'Nie' }] },
      { id: 'microwave', label: 'Mikrofala nad piekarnikiem', type: 'choice', feature: 'oven',
        choices: [{ value: true, label: 'Tak' }, { value: false, label: 'Nie' }],
        when: (a) => bool(a, 'oven', true) },
      { id: 'pantryWidth', label: 'Spiżarnia', type: 'choice', feature: 'pantry',
        choices: [
          { value: 450, label: '450 mm' }, { value: 600, label: '600 mm' },
          { value: 900, label: '900 mm' }, { value: 0, label: 'Brak' },
        ] },
      { id: 'toCeiling', label: 'Wysokość zabudowy', type: 'choice',
        choices: [{ value: true, label: 'Do sufitu' }, { value: false, label: 'Korpus 2216' }] },
    ],
  },
  {
    kind: 'kitchen-island',
    label: 'Kuchnia — wyspa',
    short: 'Wyspa',
    group: 'kuchnia',
    icon: '▭',
    description:
      'Wyspa 1800–3600 z płytą lub zlewem, blatem 900 i nawisem 300 na siedzenie. ' +
      'Stoi w świetle pomieszczenia — bez szafek górnych, z okapem sufitowym.',
    relations: [
      'Długość 1800–3600, korpus 560, blat 900 z nawisem 300 na krzesła.',
      'Płyta lub zlew na środku, szuflady pod urządzeniem.',
      'Przejścia min. 900 mm z każdej strony (rekomendowane 1000–1200).',
      'Okap sufitowy nad płytą, kanał w suficie.',
      'Blat 38 mm, cokół 80–220 mm.',
    ],
    defaults: {
      width: 2400, align: 'center', worktopHeight: 900, fronts: 'handle',
      islandFeature: 'hob', seating: true,
    },
    questions: [
      { id: 'width', label: 'Długość wyspy', type: 'choice', feature: 'zone',
        choices: [
          { value: 1800, label: '1800 mm' }, { value: 2400, label: '2400 mm' },
          { value: 3000, label: '3000 mm' }, { value: 3600, label: '3600 mm' },
        ] },
      { id: 'islandFeature', label: 'Co na wyspie', type: 'choice', feature: 'zone',
        choices: [
          { value: 'hob', label: 'Płyta grzewcza' },
          { value: 'sink', label: 'Zlew' },
          { value: 'none', label: 'Tylko blat roboczy' },
        ] },
      { id: 'seating', label: 'Nawis na siedzenie', type: 'choice', feature: 'zone',
        choices: [{ value: true, label: 'Tak, 300 mm' }, { value: false, label: 'Nie' }] },
      worktopQ,
      frontsQ,
    ],
  },
  {
    kind: 'wardrobe-hinged',
    label: 'Sypialnia — szafa otwierana',
    short: 'Szafa otwierana',
    group: 'sypialnia',
    icon: '🚪',
    description:
      'Szafa 600 mm głębokości, skrzydła 400–600, wymagane 600 mm wolnej przestrzeni przed frontem. ' +
      'Drążek na ubrania i półki, wysokość 2216 lub do sufitu.',
    relations: [
      'Głębokość 600 mm — ubrania na drążku mieszczą się bez gniecenia.',
      'Skrzydła 400–600 mm; przy 2 skrzydłach sekcja do 1200 mm.',
      'Wymagane 600 mm przed frontem na otwarcie skrzydła.',
      'Wysokość 2216 lub do sufitu (zaślepka 40 mm).',
      'Drążek 1800 mm, półki 350 mm, cokół 100 mm.',
    ],
    defaults: {
      width: 1800, align: 'center', doors: 2, toCeiling: true, interior: 'rail',
    },
    questions: [
      { id: 'width', label: 'Szerokość szafy', type: 'choice', feature: 'wardrobe',
        choices: [
          { value: 1200, label: '1200 mm' }, { value: 1800, label: '1800 mm' },
          { value: 2400, label: '2400 mm' }, { value: 3000, label: '3000 mm' },
        ] },
      alignQ,
      { id: 'doors', label: 'Skrzydła w sekcji', type: 'choice', feature: 'wardrobe',
        choices: [ { value: 1, label: '1 skrzydło' }, { value: 2, label: '2 skrzydła' } ] },
      { id: 'interior', label: 'Wnętrze', type: 'choice', feature: 'wardrobe',
        choices: [ { value: 'rail', label: 'Drążek + półki' }, { value: 'shelf', label: 'Same półki' } ] },
      { id: 'toCeiling', label: 'Wysokość', type: 'choice',
        choices: [ { value: true, label: 'Do sufitu' }, { value: false, label: 'Korpus 2216' } ] },
    ],
  },
  {
    kind: 'wardrobe-sliding',
    label: 'Sypialnia — szafa przesuwna',
    short: 'Szafa przesuwna',
    group: 'sypialnia',
    icon: '⇄',
    description:
      'Szafa 650 mm głębokości z 2–3 panelami przesuwnymi. Nie potrzebuje miejsca na otwieranie, ' +
      'wymaga prowadnic góra/dół i równej podłogi.',
    relations: [
      'Głębokość 650 mm — miejsce na prowadnice i ubrania.',
      'Panele 2 lub 3, szerokość panelu ~900–1200 mm.',
      'Bez strefy otwierania — może stać przy łóżku (min. 100 mm na prowadnicę).',
      'Prowadnica górna w suficie/zaślepce, dolna w podłodze, poziom 1 mm/m.',
      'Opcja panelu lustrzanego.',
    ],
    defaults: {
      width: 1800, align: 'center', panels: 2, mirror: false, toCeiling: true, interior: 'rail',
    },
    questions: [
      { id: 'width', label: 'Szerokość szafy', type: 'choice', feature: 'wardrobe',
        choices: [
          { value: 1800, label: '1800 mm' }, { value: 2400, label: '2400 mm' },
          { value: 3000, label: '3000 mm' }, { value: 3600, label: '3600 mm' },
        ] },
      alignQ,
      { id: 'panels', label: 'Liczba paneli', type: 'choice', feature: 'wardrobe',
        choices: [ { value: 2, label: '2 panele' }, { value: 3, label: '3 panele' } ] },
      { id: 'mirror', label: 'Panel lustrzany', type: 'choice', feature: 'wardrobe',
        choices: [ { value: false, label: 'Nie' }, { value: true, label: 'Tak' } ] },
      { id: 'interior', label: 'Wnętrze', type: 'choice', feature: 'wardrobe',
        choices: [ { value: 'rail', label: 'Drążek + półki' }, { value: 'shelf', label: 'Same półki' } ] },
      { id: 'toCeiling', label: 'Wysokość', type: 'choice',
        choices: [ { value: true, label: 'Do sufitu' }, { value: false, label: 'Korpus 2216' } ] },
    ],
  },
  {
    kind: 'living-tv',
    label: 'Salon — strefa RTV',
    short: 'RTV / salon',
    group: 'salon',
    icon: '📺',
    description:
      'Niska szafka RTV z opcją podwieszenia, TV 55–75 cali i nadbudowa na ścianie. ' +
      'Przepusty na kable i listwa maskująca.',
    relations: [
      'Wysokość szafki 400–450 mm, głębokość 400 mm (sprzęt, kable).',
      'TV 55/65/75 cali, środek ekranu 1100–1300 mm nad podłogą.',
      'Podwieszenie 250 mm nad podłogą albo cokół 100 mm.',
      'Nadbudowa 400 mm głębokości 350, 500 mm nad szafką.',
      'Przepusty kablowe w środkowym module, listwa maskująca.',
    ],
    defaults: {
      width: 1800, align: 'center', height: 450, floating: true, tvSize: 65, wallUnit: true,
    },
    questions: [
      { id: 'width', label: 'Szerokość szafki RTV', type: 'choice', feature: 'tv',
        choices: [
          { value: 1200, label: '1200 mm' }, { value: 1800, label: '1800 mm' },
          { value: 2400, label: '2400 mm' }, { value: 3000, label: '3000 mm' },
        ] },
      alignQ,
      { id: 'tvSize', label: 'Wielkość telewizora', type: 'choice', feature: 'tv',
        choices: [
          { value: 55, label: '55"' }, { value: 65, label: '65"' },
          { value: 75, label: '75"' }, { value: 83, label: '83"' },
        ] },
      { id: 'height', label: 'Wysokość szafki', type: 'choice', feature: 'tv',
        choices: [ { value: 400, label: '400 mm' }, { value: 450, label: '450 mm' }, { value: 500, label: '500 mm' } ] },
      { id: 'floating', label: 'Montaż', type: 'choice',
        choices: [ { value: true, label: 'Wisząca 250 mm' }, { value: false, label: 'Na cokole 100 mm' } ] },
      { id: 'wallUnit', label: 'Nadbudowa na ścianie', type: 'choice',
        choices: [ { value: true, label: 'Tak' }, { value: false, label: 'Nie' } ] },
    ],
  },
  {
    kind: 'bathroom',
    label: 'Łazienka',
    short: 'Łazienka',
    group: 'łazienka',
    icon: '🛁',
    description:
      'Szafka pod umywalkę z blatem ceramicznym, lustro z podświetleniem i słupek 400. ' +
      'Wersja wisząca lub na cokole, płyta wodoodporna.',
    relations: [
      'Szafka 800/1000/1200, głębokość 500, blat 850 mm.',
      'Wisząca 300 mm nad podłogą albo cokół 60–200 mm.',
      'Lustro 700 mm wysokości, 250 mm nad blatem, podświetlenie LED.',
      'Słupek 400 × 350 × 2000 na kosmetyki i ręczniki.',
      'Płyta wodoodporna, krawędzie klejone, cokół PVC.',
    ],
    defaults: {
      vanity: 800, align: 'center', hanging: true, mirror: true, tall: true, worktopHeight: 850,
    },
    questions: [
      { id: 'vanity', label: 'Szerokość szafki', type: 'choice', feature: 'sink',
        choices: [
          { value: 600, label: '600 mm' }, { value: 800, label: '800 mm' },
          { value: 1000, label: '1000 mm' }, { value: 1200, label: '1200 mm' },
        ] },
      alignQ,
      { id: 'hanging', label: 'Montaż szafki', type: 'choice',
        choices: [ { value: true, label: 'Wisząca' }, { value: false, label: 'Na cokole' } ] },
      { id: 'mirror', label: 'Lustro z podświetleniem', type: 'choice', feature: 'sink',
        choices: [ { value: true, label: 'Tak' }, { value: false, label: 'Nie' } ] },
      { id: 'tall', label: 'Słupek łazienkowy 400', type: 'choice',
        choices: [ { value: true, label: 'Tak' }, { value: false, label: 'Nie' } ] },
      { id: 'worktopHeight', label: 'Wysokość blatu', type: 'choice', feature: 'sink',
        choices: [ { value: 830, label: '830 mm' }, { value: 850, label: '850 mm' }, { value: 880, label: '880 mm' } ] },
    ],
  },
];

export const ZONE_GROUPS: { id: ZoneGroup; label: string; hint: string }[] = [
  { id: 'kuchnia', label: 'Kuchnia', hint: 'Gotowanie, czystość, wysoka zabudowa, wyspa' },
  { id: 'sypialnia', label: 'Sypialnia', hint: 'Szafa otwierana i przesuwna' },
  { id: 'salon', label: 'Salon', hint: 'Strefa RTV i wypoczynku' },
  { id: 'łazienka', label: 'Łazienka', hint: 'Umywalka, lustro, słupek' },
];

export function zoneSpec(kind: ZoneKind): ZoneSpec {
  return ZONE_SPECS.find((s) => s.kind === kind) ?? ZONE_SPECS[0];
}

export function zoneDefaults(kind: ZoneKind): ZoneAnswers {
  return { ...zoneSpec(kind).defaults };
}

/** Pytania aktywne dla bieżących odpowiedzi. */
export function activeQuestions(kind: ZoneKind, a: ZoneAnswers): ZoneQuestion[] {
  return zoneSpec(kind).questions.filter((q) => !q.when || q.when(a));
}

export function planZone(kind: ZoneKind, answers: ZoneAnswers, ctx: ZoneContext): ZonePlan {
  switch (kind) {
    case 'kitchen-cook': return planCook(answers, ctx);
    case 'kitchen-clean': return planClean(answers, ctx);
    case 'kitchen-tall': return planTall(answers, ctx);
    case 'kitchen-island': return planIsland(answers, ctx);
    case 'wardrobe-hinged': return wardrobe(answers, ctx, false);
    case 'wardrobe-sliding': return wardrobe(answers, ctx, true);
    case 'living-tv': return planTv(answers, ctx);
    case 'bathroom': return planBathroom(answers, ctx);
    default: return planCook(answers, ctx);
  }
}
