import type { Cabinet } from './types';

/** Zapis/odczyt projektu — dane klienta + szafki + wersja schematu. */
export interface ProjectFile {
  format: 'aplikacja-sprzedazowa/project';
  version: 1;
  savedAt: string;
  client: {
    name: string;
    phone: string;
    email: string;
    address: string;
    notes: string;
  };
  cabinets: Cabinet[];
}

export function serializeProject(
  cabinets: Cabinet[],
  client: ProjectFile['client'],
): ProjectFile {
  return {
    format: 'aplikacja-sprzedazowa/project',
    version: 1,
    savedAt: new Date().toISOString(),
    client,
    cabinets,
  };
}

export function parseProject(text: string): ProjectFile {
  const data = JSON.parse(text) as ProjectFile;
  if (data.format !== 'aplikacja-sprzedazowa/project') {
    throw new Error('To nie jest plik projektu tej aplikacji');
  }
  if (!Array.isArray(data.cabinets)) throw new Error('Projekt nie zawiera listy szafek');
  return data;
}

export function downloadJSON(filename: string, data: unknown) {
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename.endsWith('.json') ? filename : `${filename}.json`;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
