import type { Cabinet, Cutout } from './types';
import type { SceneBox } from './types';
import type { Room } from './room';
import type { Zone } from './zones';

/**
 * Projekty: wiele niezależnych aranżacji w jednej aplikacji.
 * Przełączanie gestem pionowym (palcem) albo strzałkami.
 */

export interface ProjectData {
  cabinets: Cabinet[];
  lights: SceneBox[];
  room: Room;
  /** strefy zabudowy (auto-projekt) — brak pola = projekt bez stref */
  zones?: Zone[];
  purpose?: string;
  notes?: string;
}

export interface Project {
  id: string;
  name: string;
  updatedAt: number;
  /** każdy projekt domyślnie zablokowany (ochrona przed edycją) */
  locked?: boolean;
  data: ProjectData;
}

const KEY = 'aplikacja-sprzedazowa:projects:v1';
const ACTIVE_KEY = 'aplikacja-sprzedazowa:active-project:v1';

export function newId() {
  return `p${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
}

export function loadProjects(): Project[] {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as Project[];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

export function saveProjects(list: Project[]) {
  try {
    localStorage.setItem(KEY, JSON.stringify(list));
  } catch {
    /* brak miejsca — ignorujemy */
  }
}

export function activeProjectId(): string | null {
  try {
    return localStorage.getItem(ACTIVE_KEY);
  } catch {
    return null;
  }
}

export function setActiveProjectId(id: string) {
  try {
    localStorage.setItem(ACTIVE_KEY, id);
  } catch {
    /* ignore */
  }
}

/** Tworzy pusty projekt z domyślnym pomieszczeniem. */
export function makeProject(
  name: string,
  room: Room,
  cabinets: Cabinet[] = [],
  lights: SceneBox[] = [],
  zones: Zone[] = [],
): Project {
  return {
    id: newId(),
    name,
    updatedAt: Date.now(),
    locked: true,
    data: { cabinets, lights, room, zones },
  };
}

/** Suma szafek — do podglądu na liście projektów. */
export function projectStats(p: Project) {
  const c = p.data.cabinets;
  return {
    count: c.length,
    area: c.reduce((s, x) => s + x.width * x.height, 0) / 1e6,
    room: `${Math.round(p.data.room.width)}×${Math.round(p.data.room.depth)}`,
  };
}

export type { Cutout };
