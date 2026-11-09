import type { Cabinet, SceneBox } from './types';

/**
 * Biegi (runs): grupy szafek stojących obok siebie w jednej linii.
 * Blat i cokół są OSOBNYMI obiektami — jeden na cały bieg, łączony automatycznie
 * z sąsiadami. Edytowane niezależnie od szafek.
 */

export interface RunSpec {
  id: string;
  cabinetIds: string[];
  /** środek i długość biegu w mm (już w świecie) */
  cx: number;
  cz: number;
  length: number;
  rotation: number;
  /** czy w biegu są szafki podblatowe (blat ma sens) */
  hasBase: boolean;
  /** czy bieg ma cokół (wszystko poza wiszącymi) */
  hasPlinth: boolean;
  /** wysokość korpusu nad cokołem (mm) */
  bodyTop: number;
}

/** Grupuje szafki w biegi: ta sama linia, ten sam obrót, stykające się. */
export function computeRuns(cabinets: Cabinet[], tol = 20): RunSpec[] {
  const rows = new Map<string, Cabinet[]>();
  for (const c of cabinets) {
    const alongZ = c.rotation === 90 || c.rotation === 270;
    const key = `${Math.round((alongZ ? c.x : c.z) / 50)}:${c.rotation}`;
    const arr = rows.get(key) ?? [];
    arr.push(c);
    rows.set(key, arr);
  }

  const runs: RunSpec[] = [];
  for (const arr of rows.values()) {
    const alongZ = arr[0].rotation === 90 || arr[0].rotation === 270;
    const axis = alongZ ? 'z' : 'x';
    const sorted = [...arr].sort((a, b) => a[axis] - b[axis]);

    const flush = (group: Cabinet[]) => {
      if (!group.length) return;
      const mins = group.map((c) => c[axis] - c.width / 2);
      const maxs = group.map((c) => c[axis] + c.width / 2);
      const lo = Math.min(...mins);
      const hi = Math.max(...maxs);
      const first = group[0];
      runs.push({
        id: `run-${first.id}`,
        cabinetIds: group.map((c) => c.id),
        cx: (lo + hi) / 2,
        cz: alongZ ? (lo + hi) / 2 : first.z,
        length: hi - lo,
        rotation: first.rotation,
        hasBase: group.some((c) => c.type === 'base'),
        hasPlinth: group.some((c) => c.type !== 'wall'),
        bodyTop: Math.max(...group.map((c) => (c.type === 'base' ? c.plinth + c.height : c.height))),
      });
      // dla biegu wzdłuż Z środek X to pierwsza szafka
      if (alongZ) {
        const r = runs[runs.length - 1];
        r.cz = (lo + hi) / 2;
        r.cx = first.x;
      } else {
        runs[runs.length - 1].cz = first.z;
      }
    };

    let group: Cabinet[] = [];
    for (const c of sorted) {
      if (!group.length) {
        group.push(c);
        continue;
      }
      const prev = group[group.length - 1];
      const gap = c[axis] - c.width / 2 - (prev[axis] + prev.width / 2);
      if (Math.abs(gap) <= tol) group.push(c);
      else {
        flush(group);
        group = [c];
      }
    }
    flush(group);
  }
  return runs;
}

export interface WorktopParams {
  thickness: number;
  overhang: number;
  color: string;
  enabled: boolean;
}

export interface PlinthParams {
  height: number;
  mode: 'flush' | 'recessed';
  setback: number;
  color: string;
  enabled: boolean;
}

/** Bryły blatów — jeden na bieg, łączony automatycznie z sąsiednimi blatami. */
export function worktopBoxes(runs: RunSpec[], p: WorktopParams): SceneBox[] {
  if (!p.enabled) return [];
  return runs
    .filter((r) => r.hasBase)
    .map((r) => {
      const y = r.bodyTop + p.thickness / 2;
      return {
        id: `${r.id}:worktop`,
        kind: 'panel' as const,
        cabinetId: r.cabinetIds[0],
        size: [r.length + p.overhang * 2, p.thickness, 580] as [number, number, number],
        position: [r.cx, y, r.cz] as [number, number, number],
        rotationY: r.rotation,
        color: p.color,
        outline: true,
        mat: 'stone' as const,
      };
    });
}

/** Bryły cokołów — jeden na bieg; licowany z frontem albo cofnięty o `setback`. */
export function plinthBoxes(runs: RunSpec[], p: PlinthParams): SceneBox[] {
  if (!p.enabled) return [];
  const cof = p.mode === 'recessed' ? p.setback : 0;
  return runs
    .filter((r) => r.hasPlinth && r.hasBase)
    .map((r) => ({
      id: `${r.id}:plinth`,
      kind: 'panel' as const,
      cabinetId: r.cabinetIds[0],
      size: [r.length, p.height, 540 - cof] as [number, number, number],
      position: [r.cx, p.height / 2, r.cz + cof / 2] as [number, number, number],
      rotationY: r.rotation,
      color: p.color,
      outline: true,
      mat: 'plaster' as const,
    }));
}
