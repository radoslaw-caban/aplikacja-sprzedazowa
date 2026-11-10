import type { SceneBox } from './types';
import type { Room } from './room';

/**
 * Otoczenie krajobrazowe: pasmo gór w tle, las na horyzoncie, kępy trawy.
 *
 * Wszystko proceduralne, ale oparte na regułach krajobrazu:
 *  - góry: stożki o rosnącej wysokości i szarości zależnej od odległości,
 *    z czapami śnieżnymi i coraz bledszym kolorem (perspektywa powietrzna)
 *  - las: pierścienie drzew o malejącej gęstości i rosnącym rozmyciu
 *  - trawa: kępy (skrzyżowane płaszczyzny) wokół budynku, gęstość maleje z odległością
 */

function rnd(seed: number) {
  // deterministyczny generator — ten sam krajobraz przy każdym otwarciu
  let s = seed % 2147483647;
  if (s <= 0) s += 2147483646;
  return () => {
    s = (s * 16807) % 2147483647;
    return (s - 1) / 2147483646;
  };
}

const box = (
  id: string,
  size: [number, number, number],
  position: [number, number, number],
  color: string,
  extra: Partial<SceneBox> = {},
): SceneBox => ({ id, kind: 'scene', cabinetId: 'scene', size, position, color, outline: false, ...extra });

/** Pasmo gór — kilka pierścieni stożków o rosnącej odległości i bladości. */
export function mountainBoxes(_room: Room, seed = 7): SceneBox[] {
  const out: SceneBox[] = [];
  const r = rnd(seed);
  const rings = [
    { dist: 150000, count: 18, hMin: 14000, hMax: 26000, tint: 0.75 },
    { dist: 230000, count: 16, hMin: 20000, hMax: 34000, tint: 0.5 },
    { dist: 320000, count: 14, hMin: 26000, hMax: 42000, tint: 0.3 },
  ];

  for (const ring of rings) {
    for (let i = 0; i < ring.count; i++) {
      const a = (i / ring.count) * Math.PI * 2 + r() * 0.16;
      const dist = ring.dist * (0.85 + r() * 0.3);
      const h = ring.hMin + r() * (ring.hMax - ring.hMin);
      const baseW = h * (1.3 + r() * 0.9);
      const x = Math.cos(a) * dist;
      const z = Math.sin(a) * dist;

      // kolor: im dalej, tym bardziej w niebiesko-szary (perspektywa powietrzna)
      const t = ring.tint;
      const shade = 0.55 + r() * 0.2;
      // im dalej, tym bardziej niebiesko-szare (perspektywa powietrzna)
      const near = { r: 74, g: 82, b: 96 };
      const far = { r: 132, g: 148, b: 168 };
      const mix = 1 - t;
      const col = {
        r: Math.round((near.r * shade) * (1 - mix) + far.r * mix),
        g: Math.round((near.g * shade) * (1 - mix) + far.g * mix),
        b: Math.round((near.b * shade) * (1 - mix) + far.b * mix),
      };
      const color = `rgb(${col.r},${col.g},${col.b})`;

      out.push(
        box(`mtn-${ring.dist}-${i}`, [baseW, h, baseW * (0.8 + r() * 0.4)], [x, h / 2 - 1200, z], color, {
          shape: 'cone',
          detail: 10,
          mat: 'rock',
        }),
      );

      // czapa śnieżna — mniejszy stożek na szczycie
      if (h > 11000) {
        const capH = h * 0.22;
        out.push(
          box(
            `mtn-snow-${ring.dist}-${i}`,
            [baseW * 0.3, capH, baseW * 0.26],
            [x, h - 1200 - capH / 2 + 60, z],
            `rgb(${230 + Math.round(r() * 20)},${235 + Math.round(r() * 15)},240)`,
            { shape: 'cone', detail: 8, mat: 'plaster' },
          ),
        );
      }
    }
  }
  return out;
}

/** Las na horyzoncie — stożki iglaków o rosnącej gęstości i rozmyciu. */
export function horizonForest(_room: Room, seed = 21): SceneBox[] {
  const out: SceneBox[] = [];
  const r = rnd(seed);
  const rings = [
    { dist: 62000, count: 30, size: 0.55 },
    { dist: 88000, count: 26, size: 0.45 },
    { dist: 118000, count: 22, size: 0.38 },
  ];
  for (const ring of rings) {
    for (let i = 0; i < ring.count; i++) {
      const a = (i / ring.count) * Math.PI * 2 + r() * 0.1;
      const d = ring.dist * (0.9 + r() * 0.25);
      const h = (5200 + r() * 3200) * ring.size;
      const w = h * (0.45 + r() * 0.12);
      const x = Math.cos(a) * d;
      const z = Math.sin(a) * d;
      const g = 60 + Math.round(r() * 30);
      out.push(
        box(`forest-${ring.dist}-${i}`, [w, h, w], [x, h / 2 - 170, z], `rgb(38,${g + 20},44)`, {
          shape: 'cone',
          detail: 6,
          mat: 'foliage',
        }),
      );
    }
  }
  return out;
}

/** Kępy trawy wokół budynku — skrzyżowane płaszczyzny z teksturą źdźbeł. */
export function grassTufts(room: Room, seed = 33): SceneBox[] {
  const out: SceneBox[] = [];
  const r = rnd(seed);
  const W = room.width;
  const D = room.depth;
  const zones = [
    { count: 260, spread: 9000, size: 420 },
    { count: 200, spread: 18000, size: 360 },
    { count: 120, spread: 30000, size: 300 },
  ];
  let n = 0;
  for (const z of zones) {
    for (let i = 0; i < z.count; i++) {
      // punkt wokół domu, ale poza jego obrysem
      const angle = r() * Math.PI * 2;
      const dist = z.spread * (0.35 + r() * 0.65);
      const x = Math.cos(angle) * (W / 2 + dist);
      const zz = Math.sin(angle) * (D / 2 + dist);
      // kępy także na samym trawniku (nie tylko poza obrysem domu)
      const s = z.size * (0.7 + r() * 0.8);
      out.push(
        box(`tuft-${n++}`, [s, s * 0.85, s], [x, -170 + (s * 0.85) / 2, zz], '#ffffff', {
          shape: 'tuft',
          mat: 'grass',
          rotationY: r() * 180,
        }),
      );
    }
  }
  return out;
}

/** Całość krajobrazu wokół posesji. */
export function landscapeBoxes(room: Room): SceneBox[] {
  return [...mountainBoxes(room), ...horizonForest(room), ...grassTufts(room)];
}

/**
 * Realistyczne (choć proceduralne) modele drzew w skali 1:1.
 * Iglaste: stożkowe piętra gałęzi na zwężającym się pniu (świerk/sosna).
 * Liściaste: pień z rozgałęzieniami i kilka nieregularnych koron.
 */
export function treeBoxes(x: number, z: number, height: number, kind: 'pine' | 'spruce' | 'deciduous', seed = 1): SceneBox[] {
  const r = rnd(seed);
  const out: SceneBox[] = [];
  const base = -170;
  const trunkH = height * (kind === 'deciduous' ? 0.45 : 0.32);
  const trunkW = height * (kind === 'deciduous' ? 0.05 : 0.042);

  // pień (lekko zwężony — dwa odcinki)
  out.push(box(`tree-${x}-${z}-trunk-a`, [trunkW, trunkH * 0.6, trunkW], [x, base + trunkH * 0.3, z], '#4a3626', { shape: 'cylinder', detail: 10, mat: 'wood-dark' }));
  out.push(box(`tree-${x}-${z}-trunk-b`, [trunkW * 0.72, trunkH * 0.5, trunkW * 0.72], [x, base + trunkH * 0.78, z], '#55402d', { shape: 'cylinder', detail: 10, mat: 'wood-dark' }));

  if (kind === 'deciduous') {
    // korona: 5 nieregularnych brył, coraz mniejszych ku górze
    const crownH = height - trunkH;
    const layers = 5;
    for (let i = 0; i < layers; i++) {
      const t = i / (layers - 1);
      const w = height * (0.52 - t * 0.28) * (0.85 + r() * 0.3);
      const yy = base + trunkH + crownH * (0.18 + t * 0.62);
      const ox = (r() - 0.5) * height * 0.12;
      const oz = (r() - 0.5) * height * 0.12;
      const g = 78 + Math.round(r() * 40);
      out.push(
        box(`tree-${x}-${z}-crown-${i}`, [w, crownH * 0.42, w], [x + ox, yy, z + oz], `rgb(${34 + Math.round(r() * 22)},${g + 22},${32 + Math.round(r() * 18)})`, {
          shape: 'sphere',
          mat: 'foliage',
          rotationY: r() * 180,
        }),
      );
    }
  } else {
    // iglaste: piętra stożków, coraz węższe ku górze
    const tiers = kind === 'spruce' ? 7 : 5;
    const crownH = height - trunkH;
    for (let i = 0; i < tiers; i++) {
      const t = i / tiers;
      const w = height * (0.42 - t * 0.3) * (0.9 + r() * 0.2);
      const th = (crownH / tiers) * 1.9;
      const yy = base + trunkH * 0.55 + (crownH * i) / tiers + th / 2;
      const g = 62 + Math.round(r() * 26);
      out.push(
        box(`tree-${x}-${z}-tier-${i}`, [w, th, w], [x, yy, z], `rgb(${28 + Math.round(r() * 16)},${g + 24},${34 + Math.round(r() * 16)})`, {
          shape: 'cone',
          detail: 9,
          mat: 'foliage',
        }),
      );
    }
    // czubek
    out.push(box(`tree-${x}-${z}-tip`, [height * 0.06, height * 0.14, height * 0.06], [x, base + height * 0.95, z], '#3f6b38', { shape: 'cone', detail: 8, mat: 'foliage' }));
  }
  return out;
}
