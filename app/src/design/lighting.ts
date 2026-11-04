import type { SceneBox } from './types';

/**
 * Oświetlenie jako obiekty sceny: oprawy (bryły emisyjne) + realne źródła światła.
 * Wymiary w mm, jak w rzeczywistych produktach.
 */

export interface LightTemplate {
  key: string;
  label: string;
  hint: string;
  /** szerokość oprawy (mm) — do dopasowania do szafki */
  width: number;
  /** kategoria: podszafkowe / cokół / sufit / ściana / blat */
  group: 'podszafkowe' | 'cokół' | 'sufit' | 'ściana' | 'wyspa';
  color: string;
  /** temperatura barwowa opisowo */
  temp: string;
  make: (x: number, y: number, z: number, width?: number) => SceneBox[];
}

const em = (id: string, size: [number, number, number], pos: [number, number, number], color: string, intensity: number, extra: Partial<SceneBox> = {}): SceneBox => ({
  id,
  kind: 'scene',
  cabinetId: 'light',
  size,
  position: pos,
  color,
  mat: 'metal',
  emissive: color,
  emissiveIntensity: intensity,
  outline: false,
  ...extra,
});

export const LIGHT_TEMPLATES: LightTemplate[] = [
  {
    key: 'led-undershelf',
    label: 'Taśma LED pod szafką',
    hint: 'Profil aluminiowy 16×8 mm, 3000 K, 12 W/m — pod górnymi szafkami',
    width: 600,
    group: 'podszafkowe',
    color: '#fff3d6',
    temp: '3000 K',
    make: (x, y, z, width = 600) => [
      // profil aluminiowy
      { id: `led-prof-${x}-${z}`, kind: 'scene', cabinetId: 'light', size: [width, 8, 16], position: [x, y, z], color: '#b8bcc2', mat: 'metal' },
      // świecąca taśma + realne światło punktowe pod szafką
      em(`led-glow-${x}-${z}`, [width - 20, 3, 12], [x, y - 5, z], '#fff3d6', 4, {
        light: { color: '#ffefd0', intensity: 1.6, distance: 900, y: y - 20 },
      }),
    ],
  },
  {
    key: 'led-plinth',
    label: 'Taśma LED w cokole',
    hint: 'Profil wpuszczany w cokół, 2700 K — efekt „pływającej" zabudowy',
    width: 600,
    group: 'cokół',
    color: '#ffe9c4',
    temp: '2700 K',
    make: (x, _y, z, width = 600) => [
      em(`led-plinth-${x}-${z}`, [width - 40, 4, 10], [x, 40, z + 285], '#ffe9c4', 3.5, {
        light: { color: '#ffe6bc', intensity: 1.1, distance: 700, y: 30 },
      }),
    ],
  },
  {
    key: 'spot-ceiling',
    label: 'Halogen wpuszczany (sufit)',
    hint: 'Oprawa Ø 82 mm, 350 lm, 3000 K — nad ciągiem roboczym',
    width: 82,
    group: 'sufit',
    color: '#fff6e2',
    temp: '3000 K',
    make: (x, y, z) => [
      // pierścień oprawy
      { id: `spot-ring-${x}-${z}`, kind: 'scene', cabinetId: 'light', size: [82, 6, 82], position: [x, y, z], color: '#d9dde3', mat: 'metal', shape: 'cylinder' },
      // soczewka
      em(`spot-lens-${x}-${z}`, [62, 4, 62], [x, y - 5, z], '#fff6e2', 5, {
        shape: 'cylinder',
        light: { color: '#fff2d8', intensity: 2.4, distance: 1600, y: y - 30 },
      }),
    ],
  },
  {
    key: 'plafond',
    label: 'Plafon sufitowy',
    hint: 'Kopuła Ø 300 mm, 2×E27 — światło ogólne pomieszczenia',
    width: 300,
    group: 'sufit',
    color: '#fff8ea',
    temp: '3000 K',
    make: (x, y, z) => [
      { id: `plafond-base-${x}-${z}`, kind: 'scene', cabinetId: 'light', size: [300, 14, 300], position: [x, y, z], color: '#e6e9ee', mat: 'metal', shape: 'cylinder' },
      em(`plafond-glow-${x}-${z}`, [272, 60, 272], [x, y - 36, z], '#fff8ea', 3.2, {
        shape: 'sphere',
        light: { color: '#fff4e0', intensity: 3.2, distance: 3200, y: y - 120 },
      }),
    ],
  },
  {
    key: 'pendant',
    label: 'Lampa wisząca (wyspa)',
    hint: 'Klosz Ø 250 mm, zwis 800 mm — nad wyspą/blatem',
    width: 250,
    group: 'wyspa',
    color: '#ffeccb',
    temp: '2700 K',
    make: (x, y, z) => [
      // przewód
      { id: `pend-cable-${x}-${z}`, kind: 'scene', cabinetId: 'light', size: [8, 800, 8], position: [x, y + 400, z], color: '#2a2a2a', shape: 'cylinder' },
      // klosz
      { id: `pend-shade-${x}-${z}`, kind: 'scene', cabinetId: 'light', size: [250, 180, 250], position: [x, y, z], color: '#1f2227', mat: 'metal', shape: 'cylinder' },
      em(`pend-glow-${x}-${z}`, [220, 40, 220], [x, y - 70, z], '#ffeccb', 4.5, {
        shape: 'sphere',
        light: { color: '#ffe8c0', intensity: 2.8, distance: 2200, y: y - 100 },
      }),
    ],
  },
  {
    key: 'sconce',
    label: 'Kinkiet ścienny',
    hint: 'Oprawa Ø 120 mm, IP44 — nad blatem przy ścianie',
    width: 120,
    group: 'ściana',
    color: '#ffe9c8',
    temp: '3000 K',
    make: (x, y, z) => [
      { id: `sconce-body-${x}-${z}`, kind: 'scene', cabinetId: 'light', size: [120, 120, 90], position: [x, y, z], color: '#c9ced6', mat: 'metal', shape: 'cylinder' },
      em(`sconce-glow-${x}-${z}`, [90, 60, 40], [x, y, z + 50], '#ffe9c8', 4, {
        light: { color: '#ffe6c2', intensity: 2.0, distance: 1400, y },
      }),
    ],
  },
  {
    key: 'led-strip-shelf',
    label: 'LED w półce (podświetlenie witryny)',
    hint: 'Taśma 8 mm w wrębie półki — podświetlenie ekspozycji',
    width: 500,
    group: 'podszafkowe',
    color: '#eaf4ff',
    temp: '4000 K',
    make: (x, y, z, width = 500) => [
      em(`led-shelf-${x}-${z}`, [width - 30, 3, 8], [x, y, z + 260], '#eaf4ff', 4, {
        light: { color: '#e6f2ff', intensity: 1.0, distance: 600, y: y - 40 },
      }),
    ],
  },
];

export function lightsByGroup() {
  return LIGHT_TEMPLATES;
}
