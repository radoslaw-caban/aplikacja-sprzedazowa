/**
 * Modułowy konfigurator pojemników w szufladzie.
 * Siatka modułów (mm) + prostokątne pojemniki zajmujące N×M komórek.
 * Rzut z góry: X = szerokość szuflady, Y = głębokość.
 */

export type OrganizerKind = 'cubby' | 'tray' | 'glass';

export interface OrganizerItem {
  id: string;
  /** kolumna / wiersz lewego-górnego narożnika (0-based) */
  col: number;
  row: number;
  /** rozmiar w komórkach */
  w: number;
  h: number;
  kind: OrganizerKind;
}

export interface OrganizerLayout {
  /** bok pojedynczego modułu w mm */
  cell: number;
  cols: number;
  rows: number;
  items: OrganizerItem[];
}

export const ORGANIZER_KINDS: Record<OrganizerKind, { label: string; height: number; wall: number; color: string }> = {
  cubby: { label: 'Pojemnik', height: 70, wall: 4, color: '#8d9b6a' },
  tray: { label: 'Taca', height: 35, wall: 3, color: '#b08968' },
  glass: { label: 'Szklany', height: 55, wall: 4, color: '#7fa4b8' },
};

/** Paleta modułów do wyboru — kwadraty i prostokąty. */
export const MODULE_SIZES: { w: number; h: number; label: string }[] = [
  { w: 1, h: 1, label: '1×1' },
  { w: 2, h: 1, label: '2×1' },
  { w: 1, h: 2, label: '1×2' },
  { w: 2, h: 2, label: '2×2' },
  { w: 3, h: 1, label: '3×1' },
  { w: 3, h: 2, label: '3×2' },
  { w: 4, h: 2, label: '4×2' },
];

/** Tworzy siatkę dopasowaną do światła szuflady (mm). */
export function makeLayout(innerW: number, innerD: number, cell = 50): OrganizerLayout {
  const cols = Math.max(2, Math.floor(innerW / cell));
  const rows = Math.max(2, Math.floor(innerD / cell));
  return { cell, cols, rows, items: [] };
}

function overlaps(a: OrganizerItem, col: number, row: number, w: number, h: number) {
  return !(col + w <= a.col || a.col + a.w <= col || row + h <= a.row || a.row + a.h <= row);
}

export function isFree(layout: OrganizerLayout, col: number, row: number, w: number, h: number, ignoreId?: string) {
  if (col < 0 || row < 0 || col + w > layout.cols || row + h > layout.rows) return false;
  return !layout.items.some((it) => it.id !== ignoreId && overlaps(it, col, row, w, h));
}

export function place(
  layout: OrganizerLayout,
  col: number,
  row: number,
  w: number,
  h: number,
  kind: OrganizerKind,
): OrganizerLayout {
  if (!isFree(layout, col, row, w, h)) return layout;
  const item: OrganizerItem = {
    id: 'o' + Math.random().toString(36).slice(2, 8),
    col,
    row,
    w,
    h,
    kind,
  };
  return { ...layout, items: [...layout.items, item] };
}

export function removeItem(layout: OrganizerLayout, id: string): OrganizerLayout {
  return { ...layout, items: layout.items.filter((i) => i.id !== id) };
}

/** Ile komórek zajętych / wszystkich. */
export function usage(layout: OrganizerLayout) {
  const used = layout.items.reduce((s, i) => s + i.w * i.h, 0);
  return { used, total: layout.cols * layout.rows };
}

export interface OrganizerBox {
  size: [number, number, number];
  pos: [number, number, number];
  color: string;
  opacity?: number;
}

/**
 * Geometria pojemników: dno + 4 ścianki.
 * Układ lokalny szuflady: X = szerokość, Y = wysokość, Z = głębokość.
 * Pojemniki stoją na dnie szuflady (y = 0 = dno).
 */
export function organizerBoxes(
  layout: OrganizerLayout,
  innerW: number,
  innerD: number,
  drawerColor?: string,
): OrganizerBox[] {
  const out: OrganizerBox[] = [];
  const cw = innerW / layout.cols;
  const cd = innerD / layout.rows;
  const x0 = -innerW / 2;
  const z0 = -innerD / 2;

  for (const it of layout.items) {
    const spec = ORGANIZER_KINDS[it.kind];
    const w = it.w * cw - 2;
    const d = it.h * cd - 2;
    const h = spec.height;
    const wall = spec.wall;
    const cx = x0 + it.col * cw + (it.w * cw) / 2;
    const cz = z0 + it.row * cd + (it.h * cd) / 2;
    const color = spec.color ?? drawerColor;

    // dno
    out.push({ size: [w, wall, d], pos: [cx, wall / 2, cz], color, opacity: 1 });
    // ścianki: przód/tył
    out.push({ size: [w, h, wall], pos: [cx, h / 2, cz - d / 2 + wall / 2], color });
    out.push({ size: [w, h, wall], pos: [cx, h / 2, cz + d / 2 - wall / 2], color });
    // ścianki: lewa/prawa
    out.push({ size: [wall, h, d - 2 * wall], pos: [cx - w / 2 + wall / 2, h / 2, cz], color });
    out.push({ size: [wall, h, d - 2 * wall], pos: [cx + w / 2 - wall / 2, h / 2, cz], color });
  }
  return out;
}
