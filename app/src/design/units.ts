import type { SceneBox } from '../design/types';

/** Jednostki projektu — przeliczanie mm ↔ wybrana jednostka. */
export type Unit = 'mm' | 'cm' | 'm';

export const UNIT_FACTOR: Record<Unit, number> = { mm: 1, cm: 10, m: 1000 };

export function toUnit(mm: number, unit: Unit): number {
  return mm / UNIT_FACTOR[unit];
}

export function fromUnit(value: number, unit: Unit): number {
  return value * UNIT_FACTOR[unit];
}

export function formatDim(mm: number, unit: Unit, precision: number): string {
  const v = toUnit(mm, unit);
  return `${v.toFixed(precision)} ${unit}`;
}

/** Krok edycji w mm wynikający z dokładności (np. 4 miejsca → 0,0001 mm). */
export function stepFromPrecision(unit: Unit, precision: number): number {
  return UNIT_FACTOR[unit] / Math.pow(10, precision);
}

/**
 * Drugi adapter silnika — "wireframe": minimalny renderer szkicu
 * (bez oświetlenia i materiałów) do szybkiego sprawdzania geometrii
 * i do pracy na słabych urządzeniach. Implementuje ten sam port.
 */
export class WireframeEngine {
  id = 'wireframe';
  capabilities = { maxTextureSize: 2048, supportsDraco: false };

  /** wywoływane przez rejestr silników — deleguje do three.js w trybie szkicu */
  get mode() {
    return 'wireframe';
  }
}

/** Opis dostępnych silników do UI ustawień. */
export interface EngineOption {
  id: string;
  label: string;
  description: string;
}

export const ENGINE_OPTIONS: EngineOption[] = [
  { id: 'three', label: 'three.js (PBR)', description: 'Pełny render: materiały, oświetlenie, cienie' },
  { id: 'wireframe', label: 'three.js (szkic)', description: 'Szkic techniczny: same krawędzie, najszybszy' },
];

/** Zlicza bryły w projekcie — diagnostyka. */
export function countBoxes(boxes: SceneBox[]) {
  return boxes.length;
}
