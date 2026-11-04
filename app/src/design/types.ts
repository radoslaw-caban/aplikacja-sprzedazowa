/**
 * Model danych projektanta szafek — wszystko w MILIMETRACH.
 * Renderer przelicza mm → metry (skala sceny = metry, zgodnie z chmurą X9).
 *
 * Wymiary bazowe wg standardu europejskiego (bezramowe):
 *  - szafka dolna: korpus 720 mm, głębokość 560 mm, cokół 100–150 mm, blat 38 mm
 *  - szafka górna: głębokość 350 mm, wysokość 360–864 mm
 *  - słupek: głębokość 561 mm, wysokość 2016–2232 mm
 */

export type CabinetType = 'base' | 'wall' | 'tall';

export type ElementKind =
  | 'shelf'
  | 'drawer'
  | 'innerDrawer'
  | 'divider'
  | 'drawerSystem'
  | 'cornerBasket'
  | 'cutlery';

/** Front szafki: drzwi (skrzydłowe) albo front szuflady. */
export interface Front {
  id: string;
  kind: 'door' | 'drawer';
  /** mm w układzie korpusu */
  x0: number;
  x1: number;
  /** dolna i górna krawędź (mm od podłogi) */
  y0: number;
  y1: number;
  /** stopień otwarcia 0..1 (do animacji podglądu wnętrza) */
  open: number;
  /** powiązany element wnętrza (szuflada) */
  elementId?: string;
}

/** Kształt wycięcia. */
export type CutoutShape = 'circle' | 'rect' | 'socket1' | 'socket2';

/** Wycięcie / otwór / kieszeń (frez pod LED) w szafce. */
export interface Cutout {
  id: string;
  shape: CutoutShape;
  /** w co wchodzi wycięcie */
  target: 'front' | 'top' | 'bottom' | 'sideL' | 'sideR' | 'element';
  /** gdy target = 'element' */
  elementId?: string;
  /** pozycja w mm w układzie szafki (x od lewej, y od dołu korpusu, z od frontu) */
  x: number;
  y: number;
  z: number;
  /** prostokąt: szerokość; koło/gniazdo: średnica */
  w: number;
  h: number;
  /** głębokość wycięcia; 0 = na przelot */
  depth: number;
  /** kieszeń (nieprzelotowa, np. frez pod LED) */
  pocket: boolean;
}

export interface CabinetElement {
  id: string;
  kind: ElementKind;
  /** Wysokość dolnej krawędzi elementu nad dnem korpusu (mm). */
  y: number;
  /** Zakres poziomy w świetle korpusu (mm od lewej wewnętrznej ściany). */
  x0: number;
  x1: number;
  color?: string;
  /** wariant systemu szuflad (2/3/4) lub wysokości Blum (N/M/K) */
  variant?: string;
  holes?: boolean;
  /** stopień wysunięcia szuflady 0..1 */
  open?: number;
  /** układ pojemników (tylko szuflady) */
  organizer?: import('./organizer').OrganizerLayout;
}

export interface Cabinet {
  id: string;
  name: string;
  type: CabinetType;
  /** mm */
  width: number;
  height: number;
  depth: number;
  /** pozycja w scenie w mm (x wzdłuż szerokości, z w głąb), podłoga y=0 */
  x: number;
  z: number;
  /** obrót w stopniach: 0 / 90 / 180 / 270 */
  rotation: number;
  elements: CabinetElement[];
  fronts: Front[];
  cutouts: Cutout[];
  color?: string;
  /** cokół (mm) — dolne i słupki; blat i cokół renderowane są jako osobne biegi */
  plinth: number;
  /** czy szafka ma blat */
  worktop: boolean;
  /** odsunięcie pleców od ściany (mm) — domyślnie 50 */
  backGap: number;
}

/** Neutralny opis bryły — renderer nie zna pojęcia „szafka". */
export interface SceneBox {
  id: string;
  kind: 'panel' | ElementKind | 'hole' | 'handle' | 'organizer' | 'front' | 'cutout';
  cabinetId: string;
  elementId?: string;
  frontId?: string;
  /** mm */
  size: [number, number, number];
  /** mm, względem środka szafki na podłodze */
  position: [number, number, number];
  rotationY?: number;
  rotationZ?: number;
  color?: string;
  shape?: 'box' | 'cylinder';
  opacity?: number;
  /** rysuj kontur krawędzi */
  outline?: boolean;
}

export const PANEL = 18;
export const BACK_PANEL = 4;
export const GAP = 3;
export const WORKTOP = 38;
export const HOLE_STEP = 32;

/** Domyślna szafka bazowa — punkt startowy projektu. */
export function baseCabinet(id = 'cab1', x = 0, z = 0): Cabinet {
  const c: Cabinet = {
    id,
    name: 'Szafka dolna 600',
    type: 'base',
    width: 600,
    height: 720,
    depth: 560,
    x,
    z,
    rotation: 0,
    elements: [],
    fronts: [],
    cutouts: [],
    plinth: 150,
    worktop: true,
    backGap: 50,
  };
  c.fronts = makeDoors(c, 1);
  return c;
}

/** Dwa skrzydła / jedno skrzydło — liczone w świetle korpusu. */
export function makeDoors(c: Cabinet, count: number): Front[] {
  if (count <= 0) return [];
  const y0 = c.type === 'base' ? c.plinth + GAP : GAP;
  const y1 = c.type === 'base' ? c.plinth + c.height - GAP : c.height - GAP;
  const w = (c.width - GAP * (count + 1)) / count;
  const out: Front[] = [];
  for (let i = 0; i < count; i++) {
    const x0 = GAP + i * (w + GAP);
    out.push({
      id: `${c.id}-d${i}`,
      kind: 'door',
      x0,
      x1: x0 + w,
      y0,
      y1,
      open: 0,
    });
  }
  return out;
}

/**
 * Fronty szuflad — n frontów ułożonych od góry (typowy układ Blum).
 * Wysokości dobierane wg systemu (LEGRABOX: M 90,5 / K 128,5 / C 177 mm).
 */
export function makeDrawerFronts(c: Cabinet, heights: number[], elementIds: string[] = []): Front[] {
  const top = c.type === 'base' ? c.plinth + c.height - GAP : c.height - GAP;
  const bottom = c.type === 'base' ? c.plinth + GAP : GAP;
  const total = top - bottom;
  const sum = heights.reduce((a, b) => a + b, 0) || total;
  const scale = total / sum;
  const out: Front[] = [];
  let y = top;
  heights.forEach((h, i) => {
    const hh = h * scale;
    out.push({
      id: `${c.id}-f${i}`,
      kind: 'drawer',
      x0: GAP,
      x1: c.width - GAP,
      y0: y - hh,
      y1: y,
      open: 0,
      elementId: elementIds[i],
    });
    y -= hh;
  });
  return out;
}
