/**
 * Model danych projektanta szafek — wszystko w MILIMETRACH.
 * Renderer przelicza mm → metry (skala sceny = metry, zgodnie z chmurą X9).
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

export interface CabinetElement {
  id: string;
  kind: ElementKind;
  /** Wysokość dolnej krawędzi elementu nad dnem korpusu (mm). */
  y: number;
  /** Zakres poziomy w świetle korpusu (mm od lewej wewnętrznej ściany). */
  x0: number;
  x1: number;
  /** kolor nadpisany przez użytkownika (hex) */
  color?: string;
  /** wariant systemu szuflad / kosza itp. */
  variant?: string;
  /** wiercenie / otwory montażowe (rysowane jako walce) */
  holes?: boolean;
  /** układ pojemników w szufladzie (tylko dla kind 'drawer' / 'innerDrawer' / 'drawerSystem') */
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
  color?: string;
  /** liczba frontów (0 = otwarta, bez frontu) */
  doors: number;
}

/** Neutralny opis bryły — renderer nie zna pojęcia „szafka". */
export interface SceneBox {
  id: string;
  kind: 'panel' | ElementKind | 'hole' | 'handle' | 'organizer' | 'front';
  cabinetId: string;
  elementId?: string;
  /** mm */
  size: [number, number, number];
  /** mm, względem środka szafki na podłodze */
  position: [number, number, number];
  rotationY?: number;
  color?: string;
  shape?: 'box' | 'cylinder';
  /** przezroczystość 0..1 */
  opacity?: number;
}

export const PANEL = 18;
export const BACK_PANEL = 8;
export const GAP = 3;
export const PLINTH = 150;
export const HOLE_STEP = 32;

/** Domyślna szafka bazowa — punkt startowy projektu. */
export function baseCabinet(id = 'cab1', x = 0, z = 0): Cabinet {
  return {
    id,
    name: 'Szafka dolna',
    type: 'base',
    width: 600,
    height: 720,
    depth: 560,
    x,
    z,
    rotation: 0,
    doors: 1,
    elements: [],
  };
}

export function newElement(kind: ElementKind, id: string, y = 0, x0 = 0, x1 = 0): CabinetElement {
  return { id, kind, y, x0, x1 };
}
