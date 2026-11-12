/**
 * Kategorie biblioteki projektu — jedno źródło prawdy dla:
 *  - kolejności i nazw kategorii (od góry),
 *  - koloru kategorii (stonowane, „kobiece" pastele — nie jaskrawe),
 *  - źródła danych, które kategoria wyświetla.
 *
 * Kolor kategorii jest używany w trzech miejscach i musi być ten sam:
 * obwódka aktywnej karty, tło nagłówka grupy i poświata przy wyborze.
 * Dlatego trzymamy go jako parę (tint = pełny, soft = do tła).
 */

export type LibraryCategoryId =
  | 'zones'
  | 'cabinets'
  | 'decor'
  | 'lights'
  | 'appliances';

export interface LibraryCategory {
  id: LibraryCategoryId;
  label: string;
  /** pełny kolor kategorii — obwódka i akcent */
  tint: string;
  /** ten sam kolor w wersji do tła (bardzo niska alfa) */
  soft: string;
  /** jednolity znak graficzny zakładki */
  glyph: string;
  hint: string;
}

/**
 * Paleta: stonowane, ciepłe pastele o zbliżonej jasności i nasyceniu.
 * Wszystkie są rozróżnialne na ciemnym tle, ale żaden nie „krzyczy".
 */
export const LIBRARY_CATEGORIES: LibraryCategory[] = [
  {
    id: 'zones',
    label: 'Strefy użytkowe i przyłącza',
    tint: '#d19a9a', // pudrowy róż
    soft: 'rgba(209, 154, 154, 0.13)',
    glyph: '◫',
    hint: 'Strefy funkcjonalne: zlew, płyta, piekarnik — z przyłączami',
  },
  {
    id: 'cabinets',
    label: 'Szafki',
    tint: '#9db89d', // szałwia
    soft: 'rgba(157, 184, 157, 0.13)',
    glyph: '▤',
    hint: 'Korpusy: podblatowe, stojące, wiszące, słupki',
  },
  {
    id: 'decor',
    label: 'Elementy dekoracyjne',
    tint: '#b0a6cf', // lawenda
    soft: 'rgba(176, 166, 207, 0.13)',
    glyph: '❖',
    hint: 'Półki, przegrody, szuflady, wkłady, kosze',
  },
  {
    id: 'lights',
    label: 'Oświetlenie',
    tint: '#dcb289', // ciepły morelowy
    soft: 'rgba(220, 178, 137, 0.13)',
    glyph: '✦',
    hint: 'Taśmy LED, oprawy podszafkowe, cokół, sufit, ściana',
  },
  {
    id: 'appliances',
    label: 'AGD',
    tint: '#94aec6', // przygaszony błękit
    soft: 'rgba(148, 174, 198, 0.13)',
    glyph: '▣',
    hint: 'Zlew, płyta, piekarnik, mikrofala, lodówka, okap',
  },
];

export function categoryById(id: LibraryCategoryId): LibraryCategory {
  return LIBRARY_CATEGORIES.find((c) => c.id === id) ?? LIBRARY_CATEGORIES[0];
}

/**
 * AGD jako pozycje biblioteki. Wymiary w mm zgodne z realnymi standardami
 * (EU, zabudowa): zlew 600×500, płyta 580×510, piekarnik 595×595,
 * mikrofala 595×380, lodówka 1780×560, okap 600×500.
 */
export interface ApplianceItem {
  kind: string;
  label: string;
  w: number;
  h: number;
  d: number;
  note: string;
}

export const APPLIANCE_ITEMS: ApplianceItem[] = [
  { kind: 'sink', label: 'Zlew', w: 600, h: 500, d: 500, note: 'Zlew podblatowy / wpuszczany, szlif 600' },
  { kind: 'hob', label: 'Płyta grzewcza', w: 580, h: 510, d: 520, note: 'Płyta indukcyjna 4 pola, szlif 580×510' },
  { kind: 'oven', label: 'Piekarnik', w: 595, h: 595, d: 560, note: 'Zabudowa 60 cm, nisza 600×600' },
  { kind: 'microwave', label: 'Mikrofala', w: 595, h: 380, d: 540, note: 'Zabudowa 60 cm, nisza 600×390' },
  { kind: 'fridge', label: 'Lodówka', w: 560, h: 1780, d: 550, note: 'Słupkowa, wysokość zabudowy 1780' },
  { kind: 'hood', label: 'Okap', w: 600, h: 500, d: 500, note: 'Podszafkowy 60 cm, wylot Ø150' },
];
