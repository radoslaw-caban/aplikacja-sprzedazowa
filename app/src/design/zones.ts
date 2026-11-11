import {
  baseCabinet,
  makeDoors,
  makeDrawerFronts,
  PANEL,
  type Cabinet,
  type CabinetElement,
} from './types';
import type { Appliance } from './appliances';
import {
  planZone,
  zoneSpec,
  type Obstacle,
  type ZoneAnswers,
  type ZoneContext,
  type ZoneKind,
  type ZonePart,
  type ZonePlan,
} from './zonePlan';
import type { Room, WallSide } from './room';

/**
 * Strefy zabudowy — warstwa łącząca reguły (zonePlan) z rzeczywistymi szafkami.
 * Tu liczy się geometrię ściany, przeszkody (okno/drzwi) i materializuje plan.
 */

export interface Zone {
  id: string;
  kind: ZoneKind;
  side: WallSide;
  /** początek zabudowy od lewej krawędzi ściany (mm) — informacyjnie */
  start: number;
  answers: ZoneAnswers;
  name: string;
}

export interface WallFrame {
  side: WallSide;
  length: number;
  rotation: number;
  place(t: number, depth: number, extraGap?: number): { x: number; z: number };
  t(x: number, z: number): number;
}

const WALL_LABEL: Record<WallSide, string> = {
  north: 'północna',
  south: 'południowa',
  west: 'zachodnia',
  east: 'wschodnia',
};

export function wallLabel(side: WallSide): string {
  return WALL_LABEL[side] ?? side;
}

/** Długość ściany w świetle (mm). */
export function wallLength(room: Room, side: WallSide): number {
  return side === 'north' || side === 'south' ? room.width : room.depth;
}

/**
 * Układ współrzędnych ściany:
 *  - t = 0 na lewej krawędzi (od zachodu dla N/S, od północy dla W/E),
 *  - rotacja szafki obraca front (+lokalne z) do wnętrza pomieszczenia.
 */
export function wallFrame(room: Room, side: WallSide): WallFrame {
  const W = room.width;
  const D = room.depth;
  const gap = room.wallGap;
  const len = wallLength(room, side);
  switch (side) {
    case 'north':
      return {
        side, length: len, rotation: 0,
        place: (t, depth, extra = 0) => ({ x: -W / 2 + t, z: -D / 2 + gap + depth / 2 + extra }),
        t: (x) => x + W / 2,
      };
    case 'south':
      return {
        side, length: len, rotation: 180,
        place: (t, depth, extra = 0) => ({ x: -W / 2 + t, z: D / 2 - gap - depth / 2 - extra }),
        t: (x) => x + W / 2,
      };
    case 'west':
      return {
        side, length: len, rotation: 90,
        place: (t, depth, extra = 0) => ({ x: -W / 2 + gap + depth / 2 + extra, z: -D / 2 + t }),
        t: (_x, z) => z + D / 2,
      };
    default:
      return {
        side: 'east', length: len, rotation: 270,
        place: (t, depth, extra = 0) => ({ x: W / 2 - gap - depth / 2 - extra, z: -D / 2 + t }),
        t: (_x, z) => z + D / 2,
      };
  }
}

/** Okno i drzwi jako przeszkody na konkretnej ścianie (mm od lewej krawędzi). */
export function wallObstacles(room: Room, side: WallSide): Obstacle[] {
  const out: Obstacle[] = [];
  if (room.window?.wall === side) {
    out.push({
      kind: 'window',
      from: room.window.x,
      to: room.window.x + room.window.w,
      y0: room.window.y,
      y1: room.window.y + room.window.h,
    });
  }
  if (room.door?.wall === side) {
    out.push({
      kind: 'door',
      from: room.door.x,
      to: room.door.x + room.door.w,
      y0: room.door.y,
      y1: room.door.y + room.door.h,
    });
  }
  return out;
}

export function zoneContext(room: Room, side: WallSide): ZoneContext {
  const len = wallLength(room, side);
  const obstacles = wallObstacles(room, side);
  const door = obstacles.find((o) => o.kind === 'door');
  let usableFrom = 0;
  let usableLength = len;
  if (door) {
    const afterLen = len - door.to - 100;
    const beforeLen = door.from - 100;
    if (afterLen >= beforeLen) {
      usableFrom = door.to + 100;
      usableLength = Math.max(0, afterLen);
    } else {
      usableLength = Math.max(0, beforeLen);
    }
  }
  return {
    wallLength: len,
    usableFrom,
    usableLength,
    wallHeight: room.wallHeight,
    roomDepth: room.depth,
    roomWidth: room.width,
    obstacles,
    worktopThickness: 38,
  };
}

/** Podgląd planu (ostrzeżenia, długości, opis) dla UI. */
export function planForZone(zone: Zone, room: Room): ZonePlan {
  return planZone(zone.kind, zone.answers, zoneContext(room, zone.side));
}

let seq = 0;
const uid = () => `z${Date.now().toString(36)}${(seq++).toString(36)}`;

export interface BuildOptions {
  detail: 'basic' | 'full';
}

function elementsFor(c: Cabinet, part: ZonePart): CabinetElement[] {
  const out: CabinetElement[] = [];
  let i = 0;
  const mk = (kind: CabinetElement['kind'], y: number, variant?: string): CabinetElement => ({
    id: `${c.id}-e${i++}`,
    kind,
    y,
    x0: 0,
    x1: 0,
    variant,
  });
  const bodyH = Math.max(200, c.height - c.plinth - 2 * PANEL);
  if (part.drawers.length) {
    const sum = part.drawers.reduce((s, h) => s + h, 0) || bodyH;
    let y = 0;
    for (const h of part.drawers) {
      const hh = (h / sum) * bodyH;
      out.push(mk('drawer', y + hh / 2, hh > 150 ? 'K' : hh > 100 ? 'M' : 'N'));
      y += hh;
    }
  }
  switch (part.interior) {
    case 'shelf':
      if (part.type === 'wall') out.push(mk('shelf', bodyH * 0.5));
      else if (part.type === 'base') out.push(mk('shelf', bodyH * 0.55));
      else out.push(mk('shelf', bodyH * 0.5));
      break;
    case 'pantry': {
      const n = Math.max(2, Math.floor(bodyH / 350));
      for (let k = 1; k <= n; k++) out.push(mk('shelf', (bodyH * k) / (n + 1)));
      break;
    }
    case 'glass': {
      for (const f of [0.28, 0.5, 0.72]) out.push(mk('shelf', bodyH * f));
      break;
    }
    case 'rail': {
      // drążek: półka na górze + druga w połowie (wizualnie strefa ubrań)
      out.push(mk('shelf', bodyH * 0.72));
      out.push(mk('shelf', bodyH * 0.38));
      out.push(mk('divider', 0));
      break;
    }
    default:
      break;
  }
  return out;
}

function appliancesFor(part: ZonePart, c: Cabinet, zone: Zone, ctx: ZoneContext): Appliance[] {
  const a = zone.answers;
  const out: Appliance[] = [];
  for (const kind of part.appliances) {
    if (kind === 'tv') {
      // ekran nad szafką: dół ~100 mm nad blatem szafki RTV
      out.push({ kind, size: Number(a.tvSize ?? 65), y: (c.mountHeight ?? 0) + c.height + 500 });
    } else if (kind === 'hood') {
      if (zone.kind === 'kitchen-island') {
        out.push({ kind, ceiling: true, h: Math.max(150, ctx.wallHeight - 2310) });
      } else {
        out.push({ kind, h: Math.max(250, ctx.wallHeight - (c.plinth + c.height + 38 + 650) - 40) });
      }
    } else if (kind === 'sink') {
      out.push({ kind, w: Math.min(c.width - 120, 760) });
    } else if (kind === 'basin') {
      out.push({ kind, w: Math.min(c.width - 100, 600) });
    } else if (kind === 'fridge') {
      out.push({ kind });
    } else if (kind === 'mirror') {
      out.push({ kind });
    } else {
      out.push({ kind });
    }
  }
  return out;
}

function cabinetFromPart(
  part: ZonePart,
  zone: Zone,
  ctx: ZoneContext,
  opts: BuildOptions,
  place: { x: number; z: number; rotation: number },
): Cabinet {
  const c = baseCabinet(uid(), place.x, place.z);
  c.name = part.label;
  c.type = part.type;
  c.width = part.width;
  c.height = part.height;
  c.depth = part.depth;
  c.plinth = part.plinth;
  c.worktop = part.worktop;
  c.mountHeight = part.mountHeight > 0 ? part.mountHeight : undefined;
  c.rotation = place.rotation;
  c.zoneId = zone.id;
  c.zoneRole = part.feature ?? part.role;
  c.handle = zone.answers.fronts === 'handleless' ? 'none' : 'bar';
  c.detail = opts.detail;
  c.slidingPanels = part.slidingPanels;
  c.worktopDepth = part.worktopDepth;
  c.worktopShift = part.worktopShift;

  if (part.drawers.length) c.fronts = makeDrawerFronts(c, part.drawers);
  else if (part.doors > 0 && !part.slidingPanels) c.fronts = makeDoors(c, part.doors);
  else c.fronts = [];

  c.elements = elementsFor(c, part);
  c.appliances = appliancesFor(part, c, zone, ctx);
  return c;
}

/** Buduje szafki jednej strefy (deterministycznie z odpowiedzi). */
export function buildZoneCabinets(zone: Zone, room: Room, opts: BuildOptions): Cabinet[] {
  const ctx = zoneContext(room, zone.side);
  const plan = planZone(zone.kind, zone.answers, ctx);
  const frame = wallFrame(room, zone.side);
  const island = zone.kind === 'kitchen-island';
  const extra = island ? 1100 : 0;
  return plan.parts.map((part) => {
    const t = plan.start + part.at + part.width / 2;
    const pos = frame.place(t, part.depth, extra);
    return cabinetFromPart(part, zone, ctx, opts, { ...pos, rotation: frame.rotation });
  });
}

/**
 * Przebudowuje wszystkie strefy: szafki stref są odtwarzane od zera,
 * szafki ręczne (bez zoneId / osierocone) zostają nietknięte.
 */
export function buildAllZoneCabinets(
  cabinets: Cabinet[],
  zones: Zone[],
  room: Room,
  opts: BuildOptions,
): Cabinet[] {
  const ids = new Set(zones.map((z) => z.id));
  const manual = cabinets.filter((c) => !c.zoneId || !ids.has(c.zoneId));
  const generated = zones.flatMap((z) => buildZoneCabinets(z, room, opts));
  return [...manual, ...generated];
}

export function makeZone(kind: ZoneKind, side: WallSide, answers?: ZoneAnswers): Zone {
  const spec = zoneSpec(kind);
  return {
    id: uid(),
    kind,
    side,
    start: 0,
    answers: { ...spec.defaults, ...(answers ?? {}) },
    name: spec.label,
  };
}

/** Szafka strefy odpowiedzialna za dany element (kadrowanie kamery). */
export function featureCabinet(cabinets: Cabinet[], zone: Zone, feature?: string): Cabinet | undefined {
  if (!feature || feature === 'zone') {
    return cabinets.find((c) => c.zoneId === zone.id && c.type !== 'wall')
      ?? cabinets.find((c) => c.zoneId === zone.id);
  }
  return cabinets.find((c) => c.zoneId === zone.id && c.zoneRole === feature)
    ?? cabinets.find((c) => c.zoneId === zone.id && c.type === 'base');
}

/** Zestawienie materiałów strefy — do oferty. */
export function zoneSummary(cabinets: Cabinet[], zone: Zone) {
  const own = cabinets.filter((c) => c.zoneId === zone.id);
  const base = own.filter((c) => c.type === 'base');
  const tall = own.filter((c) => c.type === 'tall');
  const wall = own.filter((c) => c.type === 'wall');
  const fronts = own.reduce((s, c) => s + c.fronts.length, 0);
  const appliances = own.flatMap((c) => c.appliances ?? []);
  return {
    base: base.length,
    tall: tall.length,
    wall: wall.length,
    fronts,
    appliances: appliances.length,
    length: Math.round(own.filter((c) => c.type !== 'wall').reduce((s, c) => s + c.width, 0)),
  };
}
