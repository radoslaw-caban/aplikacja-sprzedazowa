import {
  BACK_PANEL,
  GAP,
  PANEL,
  type Cabinet,
  type CabinetElement,
  type Front,
  type SceneBox,
} from './types';
import { organizerBoxes } from './organizer';

/**
 * Generator geometrii wg realnej konstrukcji bezramowej (EU):
 * boki pełne (na całą wysokość korpusu), dno i wieniec między bokami,
 * plecy 4 mm wpuszczone, blat 38 mm z nawisem, cokół wpuszczony.
 * Wszystko w mm, deterministycznie, bez zależności od silnika.
 */

const D = PANEL;

export function bodyBottom(c: Cabinet) {
  return c.type === 'base' ? c.plinth : 0;
}
export function innerWidth(c: Cabinet) {
  return c.width - 2 * D;
}
export function innerHeight(c: Cabinet) {
  return c.height - 2 * D;
}
/** Światło w głąb: szafka natywnie ma 500 mm wnętrza (niezależnie od korpusu). */
export const NATIVE_INTERIOR_DEPTH = 500;

export function innerDepth(c: Cabinet) {
  return Math.min(NATIVE_INTERIOR_DEPTH, c.depth - BACK_PANEL);
}

/** Głębokość nominalna szuflady wg szeregu Blum (NL). */
export function drawerNL(c: Cabinet) {
  const nl = [270, 300, 350, 400, 450, 500, 550, 600, 650];
  const usable = innerDepth(c) - 30;
  return nl.filter((n) => n <= usable).pop() ?? 270;
}

export function buildCabinet(c: Cabinet): SceneBox[] {
  const boxes: SceneBox[] = [];
  const W = c.width;
  const H = c.height;
  const Dp = c.depth;
  const plinth = c.type === 'base' ? c.plinth : 0;
  const bodyH = H - plinth;
  const bodyY = plinth;

  const push = (
    kind: SceneBox['kind'],
    size: [number, number, number],
    position: [number, number, number],
    extra: Partial<SceneBox> = {},
  ) => {
    boxes.push({
      id: `${c.id}:${kind}:${boxes.length}`,
      kind,
      cabinetId: c.id,
      size,
      position,
      color: c.color,
      outline: true,
      ...extra,
    });
  };

  // --- cokół i blat: OSOBNE obiekty (biegi) — renderowane w runs.ts ---

  // --- boki: pełna wysokość i głębokość ---
  push('panel', [D, bodyH, Dp], [-(W - D) / 2, bodyY + bodyH / 2, 0]);
  push('panel', [D, bodyH, Dp], [(W - D) / 2, bodyY + bodyH / 2, 0]);

  // --- dno i wieniec między bokami ---
  push('panel', [W - 2 * D, D, Dp], [0, bodyY + D / 2, 0]);
  push('panel', [W - 2 * D, D, Dp], [0, bodyY + bodyH - D / 2, 0]);

  // --- plecy 4 mm wpuszczone ---
  push('panel', [W - 2 * D, bodyH - 2 * D, BACK_PANEL], [0, bodyY + bodyH / 2, -(Dp - BACK_PANEL) / 2], {
    opacity: 0.9,
    outline: false,
  });

  // --- blat: osobny obiekt w biegu (runs.ts) ---

  // --- elementy wnętrza ---
  for (const el of c.elements) {
    boxes.push(...buildElement(c, el));
  }

  // --- fronty (otwierane) ---
  for (const f of c.fronts) {
    boxes.push(...buildFront(c, f));
  }

  // --- wycięcia / otwory / kieszenie ---
  for (const cut of c.cutouts ?? []) {
    boxes.push(...buildCutout(c, cut));
  }

  return boxes;
}

/**
 * Wycięcie: koło / prostokąt / gniazdo — kieszeń (nieprzelotowa) albo na wylot.
 * Rysowane jako ciemniejsza bryła w miejscu wycięcia (wizualizacja frezowania).
 */
function buildCutout(c: Cabinet, cut: import('./types').Cutout): SceneBox[] {
  const out: SceneBox[] = [];
  const isCircle = cut.shape === 'circle' || cut.shape === 'socket1' || cut.shape === 'socket2';
  const w = cut.shape === 'socket2' ? cut.w * 1.8 : cut.w;
  const d = cut.depth > 0 ? cut.depth : 18;

  // płaszczyzna wycięcia zależy od targetu
  const zFront = c.depth / 2 + GAP + D / 2;
  const yBase = c.type === 'base' ? c.plinth : 0;

  let pos: [number, number, number];
  if (cut.target === 'front') pos = [cut.x - c.width / 2, yBase + cut.y, zFront];
  else if (cut.target === 'top') pos = [cut.x - c.width / 2, yBase + c.height - D / 2, cut.z];
  else if (cut.target === 'bottom') pos = [cut.x - c.width / 2, yBase + D / 2, cut.z];
  else pos = [cut.x - c.width / 2, yBase + cut.y, cut.z];

  out.push({
    id: `${c.id}:cutout:${cut.id}`,
    kind: 'cutout',
    cabinetId: c.id,
    size: isCircle ? [w, cut.h, d] : [w, cut.h, d],
    position: pos,
    shape: isCircle ? 'cylinder' : 'box',
    color: cut.pocket ? '#1a1d22' : '#0a0c0f',
    opacity: cut.pocket ? 0.95 : 1,
    outline: false,
  });
  return out;
}

/** Drzwi obracają się wokół zawiasu, front szuflady wysuwa się do przodu. */
function buildFront(c: Cabinet, f: Front): SceneBox[] {
  const out: SceneBox[] = [];
  const w = f.x1 - f.x0;
  const h = f.y1 - f.y0;
  const cx = f.x0 + w / 2 - c.width / 2;
  const cy = (f.y0 + f.y1) / 2;
  const zFront = c.depth / 2 + GAP + D / 2;
  const color = c.color ?? '#b08968';

  const add = (
    kind: SceneBox['kind'],
    size: [number, number, number],
    pos: [number, number, number],
    extra: Partial<SceneBox> = {},
  ) =>
    out.push({
      id: `${f.id}:${kind}:${out.length}`,
      kind,
      cabinetId: c.id,
      frontId: f.id,
      size,
      position: pos,
      color,
      outline: true,
      ...extra,
    });

  if (f.kind === 'door') {
    // zawias po lewej stronie frontu; obrót wokół krawędzi
    const hingeX = f.x0 - c.width / 2;
    const angle = (f.open ?? 0) * (Math.PI / 2.2);
    const dx = cx - hingeX;
    const rx = hingeX + dx * Math.cos(angle);
    const rz = zFront + dx * Math.sin(angle);
    add('front', [w, h, D], [rx, cy, rz], {
      rotationY: (angle * 180) / Math.PI,
    });
    // uchwyt przy krawędzi przeciwnej do zawiasu
    const hx = w / 2 - 40;
    add('handle', [120, 12, 12], [
      rx + hx * Math.cos(angle),
      f.y1 - 70,
      rz + hx * Math.sin(angle) + 12,
    ], { rotationY: (angle * 180) / Math.PI, color: '#8a8f98' });
  } else {
    const slide = (f.open ?? 0) * drawerNL(c) * 0.9;
    add('front', [w, h, D], [cx, cy, zFront + slide]);
    add('handle', [120, 12, 12], [cx, f.y1 - 30, zFront + slide + 12], { color: '#8a8f98' });
  }
  return out;
}

function buildElement(c: Cabinet, el: CabinetElement): SceneBox[] {
  const out: SceneBox[] = [];
  const innerW = innerWidth(c);
  const baseY = bodyBottom(c) + D;
  const y = baseY + el.y;
  const spanX = el.x1 > el.x0 ? el.x1 - el.x0 : innerW;
  const x0 = el.x1 > el.x0 ? el.x0 : 0;
  const cx = -(innerW / 2) + x0 + spanX / 2;
  const depthInner = innerDepth(c) - 10;
  const color = el.color ?? c.color;

  const add = (
    kind: SceneBox['kind'],
    size: [number, number, number],
    pos: [number, number, number],
    extra: Partial<SceneBox> = {},
  ) =>
    out.push({
      id: `${el.id}:${kind}:${out.length}`,
      kind,
      cabinetId: c.id,
      elementId: el.id,
      size,
      position: pos,
      color,
      outline: true,
      ...extra,
    });

  const slide = (el.open ?? 0) * drawerNL(c) * 0.9;

  switch (el.kind) {
    case 'shelf': {
      add('shelf', [spanX, D, depthInner], [cx, y, 0]);
      break;
    }
    case 'divider': {
      const h = innerHeight(c) - el.y;
      add('divider', [D, h, depthInner], [cx, y + h / 2, 0]);
      break;
    }
    case 'drawer':
    case 'innerDrawer': {
      // wysokość boku wg systemu Blum: N 66,5 / M 90,5 / K 128,5
      const sideH = el.variant === 'N' ? 66.5 : el.variant === 'K' ? 128.5 : 90.5;
      const nl = drawerNL(c);
      const w = spanX - 20;
      const d = nl - 20;
      const z = -depthInner / 2 + d / 2 + slide;
      add(el.kind, [w, D, d], [cx, y + D / 2, z], { opacity: 0.95 });
      // boki metalowe 12,8 mm (jak LEGRABOX)
      add(el.kind, [12.8, sideH, d], [cx - w / 2 + 6.4, y + D + sideH / 2, z], { color: '#9aa3ae' });
      add(el.kind, [12.8, sideH, d], [cx + w / 2 - 6.4, y + D + sideH / 2, z], { color: '#9aa3ae' });
      add(el.kind, [w, sideH, 16], [cx, y + D + sideH / 2, z - d / 2 + 8], { color: '#9aa3ae' });
      if (el.organizer?.items.length) {
        for (const b of organizerBoxes(el.organizer, w - 30, d - 30, el.color)) {
          add('organizer', b.size, [cx + b.pos[0], y + D + b.pos[1], z + b.pos[2]], {
            color: b.color,
            opacity: b.opacity,
          });
        }
      }
      break;
    }
    case 'drawerSystem': {
      const n = el.variant === '2' ? 2 : el.variant === '4' ? 4 : 3;
      const total = innerHeight(c) - el.y - 10;
      const gapY = 6;
      const h = (total - gapY * (n - 1)) / n;
      const nl = drawerNL(c);
      const w = spanX - 16;
      const d = nl - 20;
      for (let i = 0; i < n; i++) {
        const yy = y + i * (h + gapY);
        const sideH = Math.min(h - 20, 128.5);
        const z = -depthInner / 2 + d / 2;
        add('drawerSystem', [w, D, d], [cx, yy + D / 2, z], { opacity: 0.95 });
        add('drawerSystem', [12.8, sideH, d], [cx - w / 2 + 6.4, yy + D + sideH / 2, z], { color: '#9aa3ae' });
        add('drawerSystem', [12.8, sideH, d], [cx + w / 2 - 6.4, yy + D + sideH / 2, z], { color: '#9aa3ae' });
      }
      break;
    }
    case 'cornerBasket': {
      const r = Math.min(spanX, depthInner) * 0.45;
      add('cornerBasket', [r * 2, 110, r * 2], [cx, y + 55, 0], { shape: 'cylinder', opacity: 0.9 });
      break;
    }
    case 'cutlery': {
      add('cutlery', [spanX - 40, 40, depthInner - 80], [cx, y + 20, 0], { opacity: 0.9 });
      for (let i = 1; i < 4; i++) {
        add('cutlery', [D, 40, depthInner - 80], [cx - (spanX - 40) / 2 + ((spanX - 40) / 4) * i, y + 20, 0], {
          opacity: 0.8,
          outline: false,
        });
      }
      break;
    }
  }

  if (el.holes) {
    const rows = Math.floor(spanX / 32);
    for (let i = 0; i < rows; i++) {
      add('hole', [8, 13, 8], [cx - spanX / 2 + 16 + i * 32, y + 60, depthInner / 2], {
        shape: 'cylinder',
        outline: false,
      });
    }
  }

  return out;
}
