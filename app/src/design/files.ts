/**
 * Pliki klienta: umowy, skany pomieszczeń, rzuty, zdjęcia, pomiary.
 * Trzymane per projekt w localStorage. Duże pliki (skany E57/PLY) zapisujemy
 * tylko jako metadane — same dane zostają u klienta, aplikacja je tylko wskazuje.
 */

export type FileKind = 'umowa' | 'skan' | 'rzut' | 'zdjęcie' | 'pomiar' | 'inne';

export interface ClientFile {
  id: string;
  name: string;
  kind: FileKind;
  /** rozmiar w bajtach (0 jeśli nieznany) */
  size: number;
  addedAt: number;
  /** podgląd dla małych plików (obrazy/PDF < 3 MB) */
  dataUrl?: string;
  /** adres zdalny, jeśli plik leży na serwerze */
  url?: string;
}

export const FILE_KINDS: { id: FileKind; label: string; icon: string }[] = [
  { id: 'umowa', label: 'Umowy', icon: '✎' },
  { id: 'skan', label: 'Skany pomieszczeń', icon: '◍' },
  { id: 'rzut', label: 'Rzuty i projekty', icon: '▤' },
  { id: 'zdjęcie', label: 'Zdjęcia', icon: '▣' },
  { id: 'pomiar', label: 'Pomiary', icon: '⟺' },
  { id: 'inne', label: 'Inne', icon: '◇' },
];

const key = (projectId: string) => `aplikacja-sprzedazowa:files:v1:${projectId}`;

export function loadFiles(projectId: string): ClientFile[] {
  try {
    const raw = localStorage.getItem(key(projectId));
    return raw ? (JSON.parse(raw) as ClientFile[]) : [];
  } catch {
    return [];
  }
}

export function saveFiles(projectId: string, files: ClientFile[]) {
  try {
    localStorage.setItem(key(projectId), JSON.stringify(files));
  } catch {
    /* brak miejsca — pomijamy */
  }
}

export function kindOf(name: string): FileKind {
  const n = name.toLowerCase();
  if (/umow|contract|aneks/.test(n)) return 'umowa';
  if (/\.(e57|ply|las|pts)$/.test(n)) return 'skan';
  if (/\.(dwg|dxf|skp|pdf|glb|gltf)$/.test(n)) return 'rzut';
  if (/\.(jpg|jpeg|png|heic|webp)$/.test(n)) return 'zdjęcie';
  if (/pomiar|wymiar|metry/.test(n)) return 'pomiar';
  return 'inne';
}

export function humanSize(bytes: number): string {
  if (!bytes) return '—';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} kB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

/** Dodaje plik z File; duże pliki bez kopii danych. */
export async function addFile(projectId: string, file: File): Promise<ClientFile> {
  const small = file.size <= 3 * 1024 * 1024;
  let dataUrl: string | undefined;
  if (small) {
    dataUrl = await new Promise<string>((resolve) => {
      const fr = new FileReader();
      fr.onload = () => resolve(String(fr.result));
      fr.readAsDataURL(file);
    });
  }
  const entry: ClientFile = {
    id: `f${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`,
    name: file.name,
    kind: kindOf(file.name),
    size: file.size,
    addedAt: Date.now(),
    dataUrl,
  };
  const list = loadFiles(projectId);
  saveFiles(projectId, [entry, ...list]);
  return entry;
}
