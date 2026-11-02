import {
  BACK_PANEL,
  GAP,
  PANEL,
  PLINTH,
  type Cabinet,
  type CabinetElement,
  type SceneBox,
} from './types';
import { organizerBoxes } from './organizer';

/**
 * Generator geometrii: szafka + elementy → lista brył (mm).
 * Deterministyczny, bez zależności od silnika graficznego.
 * Wszystkie bryły opisane w układzie szafki; renderer dokłada pozycję szafki.
 */

const D = PANEL; // grubość płyty

/** Wewnętrzna szerokość korpusu (światło) w mm. */
export function innerWidth(c: Cabinet) {
  return c.width - 2 * D;
}

/** Wewnętrzna wysokość: dolna szafka ma cokół, górna nie. */
export function innerHeight(c: Cabinet) {
  const plinth = c.type === 'base' ? PLINTH : 0;
  return c.height - plinth - 2 * D;
}

/** Dolna krawędź korpusu nad podłogą (cokół). */
export function bodyBottom(c: Cabinet) {
  return c.type === 'base' ? PLINTH : 0;
}

export function buildCabinet(c: Cabinet): SceneBox[] {
  const boxes: SceneBox[] = [];
  const W = c.width;
  const H = c.height;
  const Dp = c.depth;
  const plinth = c.type === 'base' ? PLINTH : 0;
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
      ...extra,
    });
  };

  // --- cokół (wpuszczony o 40 mm z przodu) ---
  if (plinth > 0) {
    push('panel', [W - 20, plinth, Dp - 40], [0, plinth / 2, -20]);
  }

  // --- boki ---
  push('panel', [D, bodyH, Dp], [-(W - D) / 2, bodyY + bodyH / 2, 0]);
  push('panel', [D, bodyH, Dp], [(W - D) / 2, bodyY + bodyH / 2, 0]);

  // --- spód i wieniec ---
  push('panel', [W - 2 * D, D, Dp], [0, bodyY + D / 2, 0]);
  push('panel', [W - 2 * D, D, Dp], [0, bodyY + bodyH - D / 2, 0]);

  // --- plecy (HDF) ---
  push('panel', [W - 2 * D, bodyH - 2 * D, BACK_PANEL], [0, bodyY + bodyH / 2, -(Dp - BACK_PANEL) / 2], {
    opacity: 0.85,
  });

  // --- blat (tylko dolne i słupki) ---
  if (c.type !== 'wall') {
    push('panel', [W + 20, 38, Dp + 20], [0, H + 19, 10]);
  }

  // --- fronty (drzwi) ---
  if (c.doors > 0) {
    const frontH = bodyH - 2 * GAP;
    const frontW = (W - GAP * (c.doors + 1)) / c.doors;
    for (let i = 0; i < c.doors; i++) {
      const x = -(W - GAP) / 2 + GAP + frontW / 2 + i * (frontW + GAP);
      push('front', [frontW, frontH, D], [x, bodyY + bodyH / 2, Dp / 2 + GAP + D / 2], {
        color: c.color ?? '#b08968',
      });
      // uchwyt
      push('handle', [128, 12, 12], [x, bodyY + bodyH - 70, Dp / 2 + GAP + D + 6], {
        color: '#8a8f98',
      });
    }
  }

  // --- elementy wnętrza ---
  for (const el of c.elements) {
    boxes.push(...buildElement(c, el));
  }

  return boxes;
}

function buildElement(c: Cabinet, el: CabinetElement): SceneBox[] {
  const out: SceneBox[] = [];
  const innerW = innerWidth(c);
  const baseY = bodyBottom(c) + D;
  const y = baseY + el.y;
  const spanX = el.x1 > el.x0 ? el.x1 - el.x0 : innerW;
  const x0 = el.x1 > el.x0 ? el.x0 : 0;
  const cx = -(innerW / 2) + x0 + spanX / 2;
  const depthInner = c.depth - D - 10;
  const color = el.color ?? c.color;
  const add = (kind: SceneBox['kind'], size: [number, number, number], pos: [number, number, number], extra: Partial<SceneBox> = {}) =>
    out.push({
      id: `${el.id}:${kind}:${out.length}`,
      kind,
      cabinetId: c.id,
      elementId: el.id,
      size,
      position: pos,
      color,
      ...extra,
    });

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
    case 'drawer': {
      const h = 140;
      // dno szuflady + 4 boki
      add('drawer', [spanX - 20, D, depthInner - 20], [cx, y, 0], { opacity: 0.95 });
      add('drawer', [spanX - 20, 90, D], [cx, y + 45, -(depthInner - 20) / 2 + D / 2]);
      add('drawer', [D, 90, depthInner - 20], [cx - (spanX - 20) / 2 + D / 2, y + 45, 0]);
      add('drawer', [D, 90, depthInner - 20], [cx + (spanX - 20) / 2 - D / 2, y + 45, 0]);
      // front szuflady
      add('handle', [spanX - 6, h, D], [cx, y + h / 2, c.depth / 2 + GAP + D / 2]);
      add('handle', [128, 12, 12], [cx, y + h - 25, c.depth / 2 + GAP + D + 6], { color: '#8a8f98' });
      // pojemniki w szufladzie
      if (el.organizer?.items.length) {
        const boxes = organizerBoxes(el.organizer, spanX - 20, depthInner - 20, el.color);
        for (const b of boxes) {
          add('organizer', b.size, [cx + b.pos[0], y + D / 2 + b.pos[1], b.pos[2]], {
            color: b.color,
            opacity: b.opacity,
          });
        }
      }
      break;
    }
    case 'innerDrawer': {
      add('innerDrawer', [spanX - 20, D, depthInner - 40], [cx, y, -10], { opacity: 0.95 });
      add('innerDrawer', [spanX - 20, 70, D], [cx, y + 35, -(depthInner - 40) / 2 + D / 2], {});
      break;
    }
    case 'drawerSystem': {
      // system szuflad: 3 szuflady o równych wysokościach w świetle
      const total = innerHeight(c) - el.y - 20;
      const n = el.variant === '2' ? 2 : el.variant === '4' ? 4 : 3;
      const gapY = 6;
      const h = (total - gapY * (n - 1)) / n;
      for (let i = 0; i < n; i++) {
        const yy = y + i * (h + gapY) + h / 2;
        add('drawerSystem', [spanX - 10, h - 20, depthInner - 30], [cx, yy, 0], { opacity: 0.95 });
        add('handle', [spanX - 6, h - 8, D], [cx, yy, c.depth / 2 + GAP + D / 2]);
        add('handle', [140, 12, 12], [cx, yy + h / 2 - 30, c.depth / 2 + GAP + D + 6], { color: '#8a8f98' });
      }
      break;
    }
    case 'cornerBasket': {
      // kosz narożny: dwa półkola obrócone o 90°
      const r = Math.min(spanX, depthInner) / 2;
      add('cornerBasket', [r * 2, 110, r * 2], [cx, y + 55, 0], { shape: 'cylinder', opacity: 0.9 });
      break;
    }
    case 'cutlery': {
      // wkład na sztućce: płaska taca z przegrodami
      add('cutlery', [spanX - 40, 40, depthInner - 80], [cx, y + 20, 0], { opacity: 0.9 });
      for (let i = 1; i < 4; i++) {
        add('cutlery', [D, 40, depthInner - 80], [cx - (spanX - 40) / 2 + ((spanX - 40) / 4) * i, y + 20, 0], {
          opacity: 0.8,
        });
      }
      break;
    }
  }

  // otwory montażowe (system 32 mm) — tylko gdy włączone
  if (el.holes) {
    const rows = Math.floor(spanX / 32);
    for (let i = 0; i < rows; i++) {
      add('hole', [8, 13, 8], [cx - spanX / 2 + 16 + i * 32, y + 60, depthInner / 2], { shape: 'cylinder' });
    }
  }

  return out;
}
