import { GAP, PANEL, WORKTOP, type Cabinet, type SceneBox } from './types';
import type { ApplianceKind } from './zonePlan';

/**
 * Bryły urządzeń i AGD — w układzie LOKALNYM szafki
 * (x od środka, y od podłogi, z od środka, front = +z).
 * Rysowane przez generator razem z korpusem, więc dziedziczą obrót i pozycję.
 */
export interface Appliance {
  kind: ApplianceKind;
  /** nadpisania wymiarów (mm) */
  w?: number;
  h?: number;
  d?: number;
  x?: number;
  y?: number;
  /** telewizor: przekątna w calach */
  size?: number;
  /** pozycja w głąb (lokalne z, mm) — np. TV na ścianie za szafką */
  z?: number;
  /** okap sufitowy nad wyspą (bez szafki) */
  ceiling?: boolean;
}

const STEEL = '#b9bcc1';
const DARK = '#15181c';
const GLASS = '#22262c';

export function applianceBoxes(c: Cabinet): SceneBox[] {
  const out: SceneBox[] = [];
  const mm = c.plinth;
  const top = mm + c.height + WORKTOP; // górna płaszczyzna blatu
  const zFront = c.depth / 2 + GAP + PANEL / 2;
  /** panele AGD 4 mm przed frontem — brak z-fightingu z drzwiami */
  const zFace = zFront + 4;

  const push = (
    kind: SceneBox['kind'],
    size: [number, number, number],
    pos: [number, number, number],
    extra: Partial<SceneBox> = {},
  ) =>
    out.push({
      id: `${c.id}:ag:${out.length}`,
      kind,
      cabinetId: c.id,
      size,
      position: pos,
      outline: false,
      ...extra,
    });

  const cyl = (
    size: [number, number, number],
    pos: [number, number, number],
    extra: Partial<SceneBox> = {},
  ) => push('panel', size, pos, { shape: 'cylinder', ...extra });

  for (const a of c.appliances ?? []) {
    switch (a.kind) {
      case 'sink': {
        const w = a.w ?? Math.min(c.width - 120, 760);
        const d = a.d ?? 430;
        const zc = 10;
        // kołnierz zlewu na blacie
        push('panel', [w, 10, d], [0, top + 5, zc], { color: STEEL, mat: 'metal', bevel: 2 });
        // komora
        push('panel', [w - 90, 160, d - 110], [0, top - 80, zc], { color: '#30363d', mat: 'metal' });
        push('panel', [w - 110, 6, d - 130], [0, top - 156, zc], { color: '#22262c' });
        // bateria
        push('panel', [40, 40, 40], [0, top + 30, -c.depth / 2 + 110], { color: STEEL, mat: 'metal' });
        cyl( [26, 240, 26], [0, top + 150, -c.depth / 2 + 110], { color: STEEL, mat: 'metal' });
        cyl( [24, 24, 200], [0, top + 265, -c.depth / 2 + 210], {
          color: STEEL, mat: 'metal', rotationX: 90,
        } as Partial<SceneBox>);
        break;
      }
      case 'hob': {
        const w = a.w ?? Math.min(c.width - 60, 800);
        const d = a.d ?? 480;
        push('panel', [w, 6, d], [0, top + 3, 10], { color: GLASS, mat: 'glass', bevel: 2 });
        const r = w >= 760 ? 95 : 80;
        const dx = w / 4.2;
        const dz = d / 4.6;
        for (const [sx, sz] of [[-1, -1], [1, -1], [-1, 1], [1, 1]] as const) {
          cyl( [r * 2, 3, r * 2], [sx * dx, top + 7, sz * dz], {
            color: '#3b4048', emissive: '#2a0f06', emissiveIntensity: 0.25,
          });
        }
        break;
      }
      case 'oven': {
        const y = a.y ?? mm + (c.type === 'tall' ? 860 : 120);
        push('panel', [Math.min(560, c.width - 40), 590, 22], [0, y + 295, zFace], {
          color: DARK, mat: 'glass', bevel: 2,
        });
        push('panel', [500, 18, 30], [0, y + 555, zFace + 22], { color: STEEL, mat: 'metal' });
        push('panel', [380, 120, 6], [0, y + 300, zFace + 13], { color: '#0d0f12', opacity: 0.9 });
        break;
      }
      case 'microwave': {
        const y = a.y ?? mm + (c.type === 'tall' ? 1490 : 480);
        push('panel', [Math.min(520, c.width - 60), 360, 20], [0, y + 180, zFace], {
          color: DARK, mat: 'glass', bevel: 2,
        });
        push('panel', [420, 16, 26], [0, y + 350, zFace + 20], { color: STEEL, mat: 'metal' });
        break;
      }
      case 'fridge': {
        const h = c.height - mm - 20;
        const w = c.width - 20;
        push('panel', [w, h, 22], [0, mm + h / 2 + 10, zFace], {
          color: '#c3c8ce', mat: 'metal', bevel: 2,
        });
        if (c.width >= 880) {
          // side-by-side: dwie bryły + szuflada zamrażarki
          push('panel', [4, h * 0.98, 26], [0, mm + h / 2 + 20, zFace + 2], { color: '#8d8a83' });
        }
        push('panel', [18, h * 0.55, 26], [-w / 2 + 40, mm + h * 0.55, zFace + 20], { color: STEEL, mat: 'metal' });
        push('panel', [18, h * 0.55, 26], [w / 2 - 40, mm + h * 0.55, zFace + 20], { color: STEEL, mat: 'metal' });
        break;
      }
      case 'hood': {
        const w = a.w ?? Math.min(c.width, 900);
        if (a.ceiling) {
          // okap sufitowy nad wyspą: czasza 2250, kanał do sufitu
          const y = a.y ?? 2250;
          push('panel', [w, 60, 520], [0, y, 0], { color: STEEL, mat: 'metal', bevel: 3 });
          push('panel', [w - 80, 12, 440], [0, y - 36, 0], { color: '#9ea3aa', mat: 'metal' });
          push('panel', [280, a.h ?? 300, 280], [0, y + 60 + (a.h ?? 300) / 2, 0], {
            color: '#cfd2d6', mat: 'metal',
          });
          break;
        }
        const canopyY = top + 650;
        push('panel', [w, 70, 500], [0, canopyY, -c.depth / 2 + 300], {
          color: STEEL, mat: 'metal', bevel: 3,
        });
        push('panel', [300, 24, 420], [0, canopyY - 47, -c.depth / 2 + 300], { color: STEEL, mat: 'metal' });
        push('panel', [280, a.h ?? 700, 260], [0, canopyY + (a.h ?? 700) / 2 + 30, -c.depth / 2 + 320], {
          color: '#cfd2d6', mat: 'metal',
        });
        break;
      }
      case 'dishwasher': {
        const h = c.height - 10;
        push('panel', [c.width - 8, h - 20, 20], [0, mm + h / 2, zFace], { color: '#c9ccd1', mat: 'metal', bevel: 2 });
        push('panel', [c.width - 16, 40, 24], [0, mm + h - 45, zFace + 12], { color: '#8f939a', mat: 'metal' });
        push('panel', [c.width - 120, 10, 26], [0, mm + h - 75, zFace + 14], { color: DARK });
        break;
      }
      case 'washer': {
        push('panel', [c.width - 8, c.height - 20, 20], [0, mm + c.height / 2, zFace], {
          color: '#e4e2dd', bevel: 2,
        });
        cyl( [380, 30, 380], [0, mm + c.height / 2, zFace + 14], {
          color: '#1e2227', mat: 'glass',
        } as Partial<SceneBox>);
        break;
      }
      case 'tv': {
        const diag = a.size ?? 65;
        const tw = a.w ?? diag * 22.1;
        const th = a.h ?? tw * 0.5625;
        const y = a.y ?? mm + c.height + 700;
        const z = a.z ?? -c.depth / 2 - 30;
        push('panel', [tw, th, 36], [0, y, z], { color: '#0b0d10', mat: 'glass', bevel: 2 });
        push('panel', [tw - 24, th - 24, 4], [0, y, z + 20], { color: '#10161e', emissive: '#0a1a2a', emissiveIntensity: 0.4 });
        push('panel', [180, 26, 120], [0, y - th / 2 - 13, z], { color: STEEL, mat: 'metal' });
        break;
      }
      case 'mirror': {
        const w = a.w ?? Math.min(c.width - 40, 900);
        const h = a.h ?? Math.min(c.height - 20, 700);
        const y = a.y ?? (c.mountHeight ?? 0) + h / 2;
        push('panel', [w, h, 18], [0, y, c.depth / 2 + 10], {
          color: '#a9c2cf', mat: 'glass', opacity: 0.85,
        });
        push('panel', [w + 20, 12, 30], [0, y + h / 2 + 6, c.depth / 2 + 18], {
          color: '#e8eef2', emissive: '#cfe6ff', emissiveIntensity: 0.8,
        });
        break;
      }
      case 'basin': {
        const w = a.w ?? Math.min(c.width - 100, 600);
        push('panel', [w, 130, 400], [0, top + 65, 10], { color: '#f2f1ec', mat: 'ceramic', bevel: 4 });
        push('panel', [w - 120, 60, 300], [0, top + 100, 10], { color: '#dcdad4', mat: 'ceramic' });
        cyl( [26, 220, 26], [0, top + 170, -c.depth / 2 + 90], { color: STEEL, mat: 'metal' });
        cyl( [22, 22, 180], [0, top + 275, -c.depth / 2 + 180], { color: STEEL, mat: 'metal', rotationX: 90 } as Partial<SceneBox>);
        break;
      }
      case 'bin':
      default:
        break;
    }
  }
  return out;
}
