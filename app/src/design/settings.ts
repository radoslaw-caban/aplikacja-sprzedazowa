/**
 * Ustawienia programu — jedno źródło prawdy dla:
 *  - oddalenia kamery we wszystkich widokach
 *  - widoczności frontów
 *  - danych klienta
 *  - skrótów klawiszowych (każda funkcja ma nazwę i edytowalny skrót)
 * Zapis w localStorage + eksport/import razem z projektem.
 */

export type Module = 'layout' | 'interior' | 'global';

export interface ActionDef {
  id: string;
  label: string;
  module: Module;
  defaultKey: string;
}

/** Rejestr wszystkich funkcji programu — tu dopisuje się nową funkcję. */
export const ACTIONS: ActionDef[] = [
  { id: 'tab.layout', label: 'Przejdź do układu', module: 'global', defaultKey: 'q' },
  { id: 'tab.interior', label: 'Przejdź do wnętrza', module: 'global', defaultKey: 'w' },
  { id: 'fronts.toggle', label: 'Pokaż/ukryj fronty', module: 'global', defaultKey: 'd' },
  { id: 'fronts.open', label: 'Otwórz fronty', module: 'interior', defaultKey: 'o' },
  { id: 'fronts.close', label: 'Zamknij fronty', module: 'interior', defaultKey: 'p' },
  { id: 'settings.open', label: 'Ustawienia programu', module: 'global', defaultKey: 's' },
  { id: 'project.save', label: 'Zapisz projekt', module: 'global', defaultKey: 'k' },
  { id: 'project.load', label: 'Wczytaj projekt', module: 'global', defaultKey: 'l' },
  { id: 'view.frame', label: 'Kadruj widok', module: 'global', defaultKey: 'f' },
  { id: 'view.front', label: 'Kamera przed szafkę', module: 'interior', defaultKey: 'g' },
  { id: 'view.drawer', label: 'Kamera do szuflady', module: 'interior', defaultKey: 'h' },
  { id: 'library.toggle', label: 'Pokaż/ukryj bibliotekę', module: 'global', defaultKey: 'b' },
  { id: 'element.delete', label: 'Usuń wybrany element', module: 'global', defaultKey: 'x' },
  { id: 'cutout', label: 'Dodaj wycięcie…', module: 'interior', defaultKey: 'v' },
  { id: 'cabinet.move', label: 'Tryb przesuwania szafek', module: 'layout', defaultKey: 'm' },
  { id: 'engine.cycle', label: 'Przełącz silnik graficzny', module: 'global', defaultKey: 'e' },
  { id: 'cloud.toggle', label: 'Pokaż/ukryj chmurę punktów', module: 'global', defaultKey: 'c' },
  { id: 'orbit.toggle', label: 'Auto-orbitowanie pola roboczego', module: 'global', defaultKey: 'o' },
];

export interface ClientData {
  name: string;
  phone: string;
  email: string;
  address: string;
  notes: string;
}

export interface CameraSettings {
  /** mnożnik oddalenia (0.5 = bliżej, 3 = dalej) */
  distance: number;
  fov: number;
  /** wysokość patrzenia w widoku wnętrza (0..1 wysokości szafki) */
  interiorHeight: number;
}

export interface Settings {
  camera: CameraSettings;
  showFronts: boolean;
  autoRotate: boolean;
  /** jednostka wyświetlania wymiarów */
  units: 'mm' | 'cm' | 'm';
  /** dokładność edycji: liczba miejsc po przecinku (0..4) */
  precision: number;
  /** wybrany silnik graficzny */
  engine: string;
  /** poziom detalu okuć: basic = uchwyty + prowadnice, full = + zawiasy, nóżki, wieszaki, wsporniki */
  hardwareDetail: 'basic' | 'full';
  /** blat — osobny obiekt, łączony automatycznie w biegi */
  worktop: { enabled: boolean; thickness: number; overhang: number; color: string };
  /** cokół — osobny obiekt, łączony automatycznie, licowany lub cofnięty */
  plinth: { enabled: boolean; height: number; mode: 'flush' | 'recessed'; setback: number; color: string };
  shortcuts: Record<string, string>;
  client: ClientData;
}

const KEY = 'aplikacja-sprzedazowa:settings:v2';

export function defaultSettings(): Settings {
  return {
    camera: { distance: 1, fov: 45, interiorHeight: 0.45 },
    showFronts: true,
    autoRotate: false,
    units: 'mm',
    precision: 1,
    engine: 'three',
    hardwareDetail: 'basic',
    worktop: { enabled: true, thickness: 38, overhang: 20, color: '#e9e5dd' },
    plinth: { enabled: true, height: 150, mode: 'recessed', setback: 40, color: '#42423f' },
    shortcuts: Object.fromEntries(ACTIONS.map((a) => [a.id, a.defaultKey])),
    client: { name: '', phone: '', email: '', address: '', notes: '' },
  };
}

export function loadSettings(): Settings {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return defaultSettings();
    const parsed = JSON.parse(raw) as Partial<Settings>;
    const base = defaultSettings();
    return {
      ...base,
      ...parsed,
      camera: { ...base.camera, ...(parsed.camera ?? {}) },
      client: { ...base.client, ...(parsed.client ?? {}) },
      shortcuts: { ...base.shortcuts, ...(parsed.shortcuts ?? {}) },
      worktop: { ...base.worktop, ...(parsed.worktop ?? {}) },
      plinth: { ...base.plinth, ...(parsed.plinth ?? {}) },
    };
  } catch {
    return defaultSettings();
  }
}

export function saveSettings(s: Settings) {
  try {
    localStorage.setItem(KEY, JSON.stringify(s));
  } catch {
    /* prywatny tryb przeglądarki */
  }
}

/** Czy zdarzenie klawiatury odpowiada danemu skrótowi. */
export function matchesKey(e: KeyboardEvent, key: string): boolean {
  if (!key) return false;
  const k = key.toLowerCase();
  const pressed = e.key.toLowerCase();
  if (e.ctrlKey || e.metaKey || e.altKey) return false;
  return pressed === k;
}

/** Nie przechwytuj skrótów, gdy użytkownik pisze w polu. */
export function isTyping(e: KeyboardEvent): boolean {
  const t = e.target as HTMLElement | null;
  return !!t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable);
}
