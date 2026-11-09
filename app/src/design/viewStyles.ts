/**
 * Style widoku — przełączane gestem poziomym (albo klawiszami [ ]).
 * Każdy styl to zestaw ustawień silnika + materiałów + światła.
 */

export type ViewStyle = 'realistic' | 'technical' | 'blueprint' | 'evening' | 'sunset';

export interface StyleSpec {
  id: ViewStyle;
  label: string;
  hint: string;
  /** tryb materiałów: tekstury PBR albo płaskie kolory */
  materials: 'pbr' | 'flat' | 'wire';
  shadows: boolean;
  ao: boolean;
  bloom: boolean;
  /** kolor tła sceny */
  background: string;
  /** intensywność słońca */
  sun: number;
  /** kolor słońca */
  sunColor: string;
  /** wysokość słońca w stopniach */
  sunElevation: number;
  /** ekspozycja */
  exposure: number;
  /** kolor nieba (dół gradientu przy horyzoncie) */
  skyTint: string;
  /** przezroczystość ścian */
  wallGhost: boolean;
}

export const VIEW_STYLES: StyleSpec[] = [
  {
    id: 'realistic',
    label: 'Realistyczny',
    hint: 'Tekstury PBR, HDRI, cienie, AO',
    materials: 'pbr',
    shadows: true,
    ao: true,
    bloom: true,
    background: '#7fa8cc',
    sun: 3.0,
    sunColor: '#fff6e8',
    sunElevation: 42,
    exposure: 1.06,
    skyTint: '#dfe7ee',
    wallGhost: true,
  },
  {
    id: 'technical',
    label: 'Techniczny',
    hint: 'Płaskie kolory, mocne krawędzie — do pracy',
    materials: 'flat',
    shadows: false,
    ao: false,
    bloom: false,
    background: '#20262e',
    sun: 1.2,
    sunColor: '#ffffff',
    sunElevation: 60,
    exposure: 1.0,
    skyTint: '#2a313a',
    wallGhost: true,
  },
  {
    id: 'blueprint',
    label: 'Blueprint',
    hint: 'Szkic: same krawędzie, jak rysunek techniczny',
    materials: 'wire',
    shadows: false,
    ao: false,
    bloom: false,
    background: '#0d1b2a',
    sun: 0.8,
    sunColor: '#9fd0ff',
    sunElevation: 65,
    exposure: 1.0,
    skyTint: '#0d1b2a',
    wallGhost: true,
  },
  {
    id: 'evening',
    label: 'Wieczór',
    hint: 'Ciepłe światło wnętrza, przygaszone słońce',
    materials: 'pbr',
    shadows: true,
    ao: true,
    bloom: true,
    background: '#2a2f3a',
    sun: 0.35,
    sunColor: '#ffb877',
    sunElevation: 6,
    exposure: 1.15,
    skyTint: '#3a4250',
    wallGhost: true,
  },
  {
    id: 'sunset',
    label: 'Złota godzina',
    hint: 'Niskie, ciepłe słońce i długie cienie',
    materials: 'pbr',
    shadows: true,
    ao: true,
    bloom: true,
    background: '#b56a3c',
    sun: 2.2,
    sunColor: '#ffb066',
    sunElevation: 12,
    exposure: 1.1,
    skyTint: '#d9a071',
    wallGhost: true,
  },
];

export function styleById(id: ViewStyle): StyleSpec {
  return VIEW_STYLES.find((s) => s.id === id) ?? VIEW_STYLES[0];
}

export function nextStyle(current: ViewStyle, dir = 1): ViewStyle {
  const i = VIEW_STYLES.findIndex((s) => s.id === current);
  const n = VIEW_STYLES.length;
  return VIEW_STYLES[((i < 0 ? 0 : i) + dir + n) % n].id;
}
