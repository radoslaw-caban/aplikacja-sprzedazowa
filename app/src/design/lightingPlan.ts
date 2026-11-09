import type { SceneBox } from './types';
import type { Room } from './room';
import { LIGHT_TEMPLATES } from './lighting';

/**
 * Automat oświetlenia sufitowego — kilka propozycji dla danego pomieszczenia.
 * Bazuje na trendach 2025/2026:
 *  - „warstwowe" światło (ambient + task + accent) zamiast jednej lampy sufitowej
 *  - światło niewidoczne (LED w zagłębieniu sufitu / cove lighting)
 *  - liniowe oprawy wpuszczane wzdłuż osi pomieszczenia
 *  - spoty kierowane na strefy robocze, nie równomierna siatka
 */

export interface LightingProposal {
  id: string;
  name: string;
  description: string;
  trend: string;
  lights: (x: number, y: number, z: number, width?: number) => SceneBox[];
}

const spot = LIGHT_TEMPLATES.find((t) => t.key === 'spot-ceiling')!;
const pendant = LIGHT_TEMPLATES.find((t) => t.key === 'pendant')!;
const plafond = LIGHT_TEMPLATES.find((t) => t.key === 'plafond')!;
const led = LIGHT_TEMPLATES.find((t) => t.key === 'led-undershelf')!;

function mk(id: string): string {
  return `${id}-${Math.random().toString(36).slice(2, 6)}`;
}

export const LIGHTING_PROPOSALS: LightingProposal[] = [
  {
    id: 'layered',
    name: 'Warstwowe (trend 2025)',
    description:
      'Trzy warstwy: ambient z sufitu (4 spoty po obwodzie), zadaniowe nad blatem (2 spoty) i liniowa listwa LED wzdłuż ściany z szafkami.',
    trend: 'Layered lighting — najczęściej polecany schemat w projektach kuchni 2025',
    lights: (x, y, z, width = 600) => {
      const out: SceneBox[] = [];
      // ambient: 4 spoty w narożnikach strefy
      const dx = Math.max(900, width * 0.9);
      const dz = 900;
      for (const sx of [-1, 1]) {
        for (const sz of [-1, 1]) {
          out.push(...spot.make(x + sx * dx, y, z + sz * dz, 82).map((b) => ({ ...b, id: mk(b.id) })));
        }
      }
      // zadaniowe: 2 spoty przed szafkami
      for (const sx of [-1, 1]) {
        out.push(...spot.make(x + sx * 350, y, z + 500, 82).map((b) => ({ ...b, id: mk(b.id) })));
      }
      // akcent: LED nad blatem
      out.push(...led.make(x, y - 700, z + 250, width).map((b) => ({ ...b, id: mk(b.id) })));
      return out;
    },
  },
  {
    id: 'cove',
    name: 'Cove lighting (LED w zagłębieniu)',
    description:
      'Światło niewidoczne: cztery odcinki LED w kasecie sufitu po obwodzie, plus jeden spot nad strefą pracy.',
    trend: 'Invisible lighting — ukryte źródło światła, widoczny tylko efekt poświaty',
    lights: (x, y, z, width = 600) => {
      const out: SceneBox[] = [];
      const half = Math.max(1200, width * 1.4);
      // cztery odcinki po obwodzie (wpuszczone 40 mm w sufit)
      const strips: [number, number, number, number][] = [
        [x, z - half, half * 2, 60],
        [x, z + half, half * 2, 60],
        [x - half, z, 60, half * 2],
        [x + half, z, 60, half * 2],
      ];
      for (const [sx, sz, w] of strips) {
        out.push(...led.make(sx, y - 60, sz, w).map((b) => ({ ...b, id: mk(b.id) })));
      }
      out.push(...spot.make(x, y, z, 82).map((b) => ({ ...b, id: mk(b.id) })));
      return out;
    },
  },
  {
    id: 'linear',
    name: 'Liniowy (profil wpuszczany)',
    description: 'Dwa równoległe profile liniowe wzdłuż dłuższej osi pomieszczenia — równomierne, miękkie światło.',
    trend: 'Linear recessed — dominujący motyw sufitów w kuchniach otwartych',
    lights: (x, y, z, width = 600) => {
      const out: SceneBox[] = [];
      const half = Math.max(1500, width * 1.2);
      for (const sx of [-1, 1]) {
        out.push(...led.make(x + sx * 400, y - 40, z, half).map((b) => ({ ...b, id: mk(b.id) })));
      }
      return out;
    },
  },
  {
    id: 'perimeter',
    name: 'Obwodowy + lampa nad wyspą',
    description: 'Spoty po obwodzie (co 1,2 m) doświetlające fronty i jednа lampa wisząca nad strefą centralną.',
    trend: 'Perimeter spots + statement pendant — czytelne strefy funkcjonalne',
    lights: (x, y, z, width = 600) => {
      const out: SceneBox[] = [];
      const w = Math.max(2400, width * 1.6);
      const n = Math.max(2, Math.round(w / 1200));
      for (let i = 0; i < n; i++) {
        const t = (i + 0.5) / n - 0.5;
        out.push(...spot.make(x + t * w, y, z - w / 3, 82).map((b) => ({ ...b, id: mk(b.id) })));
        out.push(...spot.make(x + t * w, y, z + w / 3, 82).map((b) => ({ ...b, id: mk(b.id) })));
      }
      out.push(...pendant.make(x, y - 900, z, 250).map((b) => ({ ...b, id: mk(b.id) })));
      return out;
    },
  },
  {
    id: 'minimal',
    name: 'Minimal (plafon + 4 spoty)',
    description: 'Jeden plafon centralny i cztery spoty kierunkowe — najprostszy wariant, najmniej punktów świetlnych.',
    trend: 'Quiet minimalism — mniej opraw, lepsza jakość światła',
    lights: (x, y, z, width = 600) => {
      const out: SceneBox[] = [];
      out.push(...plafond.make(x, y, z, 300).map((b) => ({ ...b, id: mk(b.id) })));
      const r = Math.max(900, width);
      for (const sx of [-1, 1]) {
        for (const sz of [-1, 1]) {
          out.push(...spot.make(x + sx * r, y, z + sz * r, 82).map((b) => ({ ...b, id: mk(b.id) })));
        }
      }
      return out;
    },
  },
];

/** Proponuje liczbę punktów zależnie od powierzchni (norma: 1 punkt / 1,5–2 m²). */
export function recommendation(room: Room) {
  const area = (room.width * room.depth) / 1e6;
  const lumens = Math.round(area * 200); // ~200 lm/m² dla kuchni
  return {
    area: Math.round(area * 100) / 100,
    spots: Math.max(4, Math.round(area / 1.75)),
    lumens,
    note: `Dla ${area.toFixed(1)} m²: ok. ${lumens} lm łącznie (≈200 lm/m²), czyli ${Math.max(4, Math.round(area / 1.75))} punktów kierunkowych.`,
  };
}
