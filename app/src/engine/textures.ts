import * as THREE from 'three';

/**
 * Proceduralne tekstury PBR (canvas) — bez zewnętrznych plików.
 * Każda tekstura ma map + roughness, a drewno/kamień także bump.
 * Skala tekstury jest liczona w metrach, więc deski i płyty mają realny rozmiar.
 */

export type MatKind =
  | 'wood'
  | 'wood-dark'
  | 'laminate'
  | 'stone'
  | 'glass'
  | 'metal'
  | 'grass'
  | 'cobble'
  | 'plaster'
  | 'roof'
  | 'foliage'
  | 'deck'
  | 'brick'
  | 'rock';

function canvas(size = 512): [HTMLCanvasElement, CanvasRenderingContext2D] {
  const c = document.createElement('canvas');
  c.width = size;
  c.height = size;
  const ctx = c.getContext('2d')!;
  return [c, ctx];
}

/** Ziarno — subtelny szum na całej powierzchni. */
function grain(ctx: CanvasRenderingContext2D, size: number, alpha: number, scale = 1) {
  const img = ctx.getImageData(0, 0, size, size);
  for (let i = 0; i < img.data.length; i += 4) {
    const n = (Math.random() - 0.5) * 255 * alpha;
    img.data[i] += n * scale;
    img.data[i + 1] += n * scale;
    img.data[i + 2] += n * scale;
  }
  ctx.putImageData(img, 0, 0);
}

function woodTexture(base: string, dark: string, light: string): HTMLCanvasElement {
  const size = 1024;
  const [c, ctx] = canvas(size);
  ctx.fillStyle = base;
  ctx.fillRect(0, 0, size, size);

  // słoje — poziome, faliste linie
  for (let i = 0; i < 520; i++) {
    const y = Math.random() * size;
    const w = 0.6 + Math.random() * 2.4;
    ctx.strokeStyle = Math.random() > 0.5 ? dark : light;
    ctx.globalAlpha = 0.05 + Math.random() * 0.22;
    ctx.lineWidth = w;
    ctx.beginPath();
    for (let x = 0; x <= size; x += 8) {
      const yy = y + Math.sin((x / size) * Math.PI * (1 + Math.random() * 1.5)) * (2 + Math.random() * 5);
      if (x === 0) ctx.moveTo(x, yy);
      else ctx.lineTo(x, yy);
    }
    ctx.stroke();
  }
  ctx.globalAlpha = 1;

  // sęki
  for (let i = 0; i < 5; i++) {
    const kx = Math.random() * size;
    const ky = Math.random() * size;
    const r = 4 + Math.random() * 10;
    const g = ctx.createRadialGradient(kx, ky, 1, kx, ky, r);
    g.addColorStop(0, dark);
    g.addColorStop(1, 'transparent');
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.ellipse(kx, ky, r * 1.6, r, Math.random() * Math.PI, 0, Math.PI * 2);
    ctx.fill();
  }
  grain(ctx, size, 0.06);
  return c;
}

function stoneTexture(): HTMLCanvasElement {
  const size = 1024;
  const [c, ctx] = canvas(size);
  ctx.fillStyle = '#e8e6e1';
  ctx.fillRect(0, 0, size, size);
  // żyłki marmuru
  for (let i = 0; i < 48; i++) {
    ctx.strokeStyle = i % 3 ? '#b9b4ac' : '#8f8a82';
    ctx.globalAlpha = 0.10 + Math.random() * 0.25;
    ctx.lineWidth = 0.5 + Math.random() * 2.2;
    ctx.beginPath();
    let x = Math.random() * size;
    let y = -10;
    ctx.moveTo(x, y);
    while (y < size + 10) {
      x += (Math.random() - 0.5) * 26;
      y += 8 + Math.random() * 14;
      ctx.lineTo(x, y);
    }
    ctx.stroke();
  }
  ctx.globalAlpha = 1;
  grain(ctx, size, 0.03);
  return c;
}

function grassTexture(): HTMLCanvasElement {
  const size = 512;
  const [c, ctx] = canvas(size);
  ctx.fillStyle = '#2f4d28';
  ctx.fillRect(0, 0, size, size);
  // nierównomierne plamy — naturalna trawa nie jest jednolita
  for (let i = 0; i < 220; i++) {
    const x = Math.random() * size;
    const y = Math.random() * size;
    const r = 8 + Math.random() * 40;
    const g = ctx.createRadialGradient(x, y, 1, x, y, r);
    const dark = Math.random() > 0.5;
    g.addColorStop(0, dark ? 'rgba(30,62,26,.55)' : 'rgba(96,140,70,.35)');
    g.addColorStop(1, 'transparent');
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fill();
  }
  for (let i = 0; i < 26000; i++) {
    const x = Math.random() * size;
    const y = Math.random() * size;
    const h = 1.5 + Math.random() * 3.5;
    const g = 62 + Math.random() * 62;
    ctx.strokeStyle = `rgba(${25 + Math.random() * 40}, ${g}, ${25 + Math.random() * 30}, .85)`;
    ctx.lineWidth = 0.5 + Math.random() * 0.7;
    ctx.beginPath();
    ctx.moveTo(x, y);
    ctx.lineTo(x + (Math.random() - 0.5) * 3, y - h);
    ctx.stroke();
  }
  return c;
}

function cobbleTexture(): HTMLCanvasElement {
  const size = 512;
  const [c, ctx] = canvas(size);
  ctx.fillStyle = '#4d4d4d';
  ctx.fillRect(0, 0, size, size);
  const cols = 8;
  const rows = 16;
  const cw = size / cols;
  const ch = size / rows;
  for (let r = 0; r < rows; r++) {
    for (let col = 0; col < cols; col++) {
      const off = r % 2 ? cw / 2 : 0;
      const x = col * cw + off + 1.5;
      const y = r * ch + 1.5;
      const shade = 118 + Math.random() * 55;
      ctx.fillStyle = `rgb(${shade}, ${shade - 3}, ${shade - 8})`;
      ctx.beginPath();
      const rad = 3;
      ctx.roundRect(x, y, cw - 3, ch - 3, rad);
      ctx.fill();
    }
  }
  grain(ctx, size, 0.08);
  return c;
}

function plasterTexture(): HTMLCanvasElement {
  const size = 512;
  const [c, ctx] = canvas(size);
  ctx.fillStyle = '#efeeea';
  ctx.fillRect(0, 0, size, size);
  for (let i = 0; i < 4000; i++) {
    const x = Math.random() * size;
    const y = Math.random() * size;
    ctx.fillStyle = `rgba(${180 + Math.random() * 60},${180 + Math.random() * 60},${175 + Math.random() * 60},0.06)`;
    ctx.beginPath();
    ctx.arc(x, y, Math.random() * 3, 0, Math.PI * 2);
    ctx.fill();
  }
  grain(ctx, size, 0.02);
  return c;
}

function roofTexture(): HTMLCanvasElement {
  const size = 512;
  const [c, ctx] = canvas(size);
  ctx.fillStyle = '#5e211d';
  ctx.fillRect(0, 0, size, size);
  const rows = 16;
  const rh = size / rows;
  for (let r = 0; r < rows; r++) {
    const off = r % 2 ? 24 : 0;
    for (let col = -1; col < 10; col++) {
      const x = col * 56 + off;
      const y = r * rh;
      const shade = 0.85 + Math.random() * 0.3;
      ctx.fillStyle = `rgba(${Math.round(122 * shade)}, ${Math.round(47 * shade)}, ${Math.round(41 * shade)}, 1)`;
      ctx.beginPath();
      ctx.roundRect(x + 2, y + 2, 52, rh - 3, 4);
      ctx.fill();
      ctx.strokeStyle = 'rgba(0,0,0,.25)';
      ctx.stroke();
    }
  }
  return c;
}

function foliageTexture(): HTMLCanvasElement {
  const size = 512;
  const [c, ctx] = canvas(size);
  ctx.fillStyle = '#4a7a3c';
  ctx.fillRect(0, 0, size, size);
  for (let i = 0; i < 2500; i++) {
    const x = Math.random() * size;
    const y = Math.random() * size;
    const g = 110 + Math.random() * 105;
    ctx.fillStyle = `rgba(${45 + Math.random() * 50}, ${g}, ${35 + Math.random() * 45}, .85)`;
    ctx.beginPath();
    ctx.ellipse(x, y, 2 + Math.random() * 6, 1 + Math.random() * 4, Math.random() * Math.PI, 0, Math.PI * 2);
    ctx.fill();
  }
  return c;
}

function deckTexture(): HTMLCanvasElement {
  const size = 512;
  const [c, ctx] = canvas(size);
  ctx.fillStyle = '#8a6f4e';
  ctx.fillRect(0, 0, size, size);
  const planks = 8;
  const pw = size / planks;
  for (let i = 0; i < planks; i++) {
    const shade = 0.88 + Math.random() * 0.24;
    ctx.fillStyle = `rgba(${Math.round(138 * shade)}, ${Math.round(111 * shade)}, ${Math.round(78 * shade)}, 1)`;
    ctx.fillRect(i * pw + 1.5, 0, pw - 3, size);
    // słoje pionowe
    for (let k = 0; k < 40; k++) {
      ctx.strokeStyle = `rgba(90, 70, 46, ${0.05 + Math.random() * 0.1})`;
      ctx.lineWidth = 0.6 + Math.random();
      const x = i * pw + 3 + Math.random() * (pw - 6);
      ctx.beginPath();
      ctx.moveTo(x, 0);
      ctx.lineTo(x + (Math.random() - 0.5) * 6, size);
      ctx.stroke();
    }
  }
  return c;
}

/** Cache tekstur — każda generowana raz. */
const cache = new Map<MatKind, { map: THREE.Texture; rough?: THREE.Texture }>();

function toTexture(cv: HTMLCanvasElement, repeat = 1): THREE.Texture {
  const t = new THREE.CanvasTexture(cv);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.repeat.set(repeat, repeat);
  t.anisotropy = 8;
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

/** Zwraca tekstury dla danego rodzaju materiału. */
export function texturesFor(kind: MatKind): { map: THREE.Texture; bump?: THREE.Texture } {
  const hit = cache.get(kind);
  if (hit) return hit;

  let cv: HTMLCanvasElement;
  switch (kind) {
    case 'wood':
      cv = woodTexture('#b8ab97', '#8d8070', '#d8cfc0');
      break;
    case 'wood-dark':
      cv = woodTexture('#5f5040', '#403529', '#80715c');
      break;
    case 'laminate':
      cv = woodTexture('#cfc6b8', '#a89c8b', '#e6dfd3');
      break;
    case 'stone':
      cv = stoneTexture();
      break;
    case 'grass':
      cv = grassTexture();
      break;
    case 'cobble':
      cv = cobbleTexture();
      break;
    case 'roof':
      cv = roofTexture();
      break;
    case 'foliage':
      cv = foliageTexture();
      break;
    case 'deck':
      cv = deckTexture();
      break;
    case 'rock':
    case 'brick':
    case 'plaster':
    default:
      cv = plasterTexture();
      break;
  }
  const map = toTexture(cv);
  const bump = toTexture(cv);
  bump.colorSpace = THREE.NoColorSpace;
  const entry = { map, bump };
  cache.set(kind, entry);
  return entry;
}

/** Bazowy kolor i chropowatość dla rodzaju materiału. */
export function materialProps(kind: MatKind): {
  color: string;
  roughness: number;
  metalness: number;
  transparent?: boolean;
  opacity?: number;
} {
  switch (kind) {
    case 'wood':
      return { color: '#ffffff', roughness: 0.55, metalness: 0.02 };
    case 'wood-dark':
      return { color: '#ffffff', roughness: 0.5, metalness: 0.02 };
    case 'laminate':
      return { color: '#ffffff', roughness: 0.42, metalness: 0.02 };
    case 'stone':
      return { color: '#cfccc5', roughness: 0.55, metalness: 0.02 };
    case 'glass':
      return { color: '#a8d4e6', roughness: 0.05, metalness: 0.1, transparent: true, opacity: 0.35 };
    case 'metal':
      return { color: '#b9bcc1', roughness: 0.25, metalness: 0.9 };
    case 'grass':
      return { color: '#ffffff', roughness: 0.95, metalness: 0 };
    case 'cobble':
      return { color: '#ffffff', roughness: 0.75, metalness: 0.02 };
    case 'plaster':
      return { color: '#ffffff', roughness: 0.85, metalness: 0 };
    case 'roof':
      return { color: '#ffffff', roughness: 0.6, metalness: 0.03 };
    case 'foliage':
      return { color: '#ffffff', roughness: 0.9, metalness: 0 };
    case 'deck':
      return { color: '#ffffff', roughness: 0.7, metalness: 0.02 };
    case 'brick':
      return { color: '#ffffff', roughness: 0.8, metalness: 0 };
    case 'rock':
      return { color: '#6f7c8c', roughness: 0.95, metalness: 0 };
  }
}

/** Ile metrów ma jeden kafel tekstury — dla spójnej skali desek i płytek. */
export function textureScale(kind: MatKind): number {
  switch (kind) {
    case 'wood':
    case 'wood-dark':
      return 0.32;
    case 'laminate':
      return 0.5;
    case 'stone':
      return 1.2;
    case 'cobble':
      return 1.4;
    case 'grass':
      return 1.6;
    case 'deck':
      return 1.0;
    case 'roof':
      return 1.1;
    case 'foliage':
      return 0.8;
    default:
      return 1.2;
  }
}

/** Domyślny materiał dla rodzaju bryły (gdy SceneBox.mat nie jest ustawiony). */
export function matKindFor(kind: string): MatKind {
  switch (kind) {
    case 'front':
      return 'wood';
    case 'panel':
      return 'wood'; // widoczne boki korpusu w dekorze frontu
    case 'shelf':
    case 'drawer':
    case 'divider':
    case 'organizer':
      return 'laminate';
    case 'handle':
      return 'metal';
    case 'cutout':
    case 'hole':
      return 'plaster';
    case 'scene':
      return 'plaster';
    default:
      return 'laminate';
  }
}

/** Siła bump mapy — drewno i kamień najbardziej zyskują na fakturze. */
export function bumpScale(kind: MatKind): number {
  switch (kind) {
    case 'wood':
    case 'wood-dark':
      return 0.012;
    case 'stone':
      return 0.008;
    case 'laminate':
      return 0.006;
    case 'cobble':
      return 0.03;
    case 'grass':
      return 0.02;
    case 'roof':
      return 0.018;
    case 'foliage':
      return 0.025;
    case 'deck':
      return 0.014;
    default:
      return 0.004;
  }
}

/**
 * Normal mapa z wysokości (Sobel) — daje prawdziwe odbicia faktury,
 * czego bump map nie potrafi (bump tylko zaciemnia).
 */
function normalFrom(cv: HTMLCanvasElement, strength = 2.0): HTMLCanvasElement {
  // redukcja do 256 px — normalna mapa nie potrzebuje pełnej rozdzielczości
  const size = 256;
  const small = document.createElement('canvas');
  small.width = small.height = size;
  small.getContext('2d')!.drawImage(cv, 0, 0, size, size);
  cv = small;
  const src = cv.getContext('2d')!.getImageData(0, 0, size, size);
  const out = document.createElement('canvas');
  out.width = size;
  out.height = size;
  const ctx = out.getContext('2d')!;
  const img = ctx.createImageData(size, size);
  const lum = (x: number, y: number) => {
    const i = (((y + size) % size) * size + ((x + size) % size)) * 4;
    return (src.data[i] * 0.299 + src.data[i + 1] * 0.587 + src.data[i + 2] * 0.114) / 255;
  };
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const dx =
        lum(x - 1, y - 1) + 2 * lum(x - 1, y) + lum(x - 1, y + 1) -
        (lum(x + 1, y - 1) + 2 * lum(x + 1, y) + lum(x + 1, y + 1));
      const dy =
        lum(x - 1, y - 1) + 2 * lum(x, y - 1) + lum(x + 1, y - 1) -
        (lum(x - 1, y + 1) + 2 * lum(x, y + 1) + lum(x + 1, y + 1));
      const nx = dx * strength;
      const ny = dy * strength;
      const nz = 1;
      const len = Math.hypot(nx, ny, nz) || 1;
      const i = (y * size + x) * 4;
      img.data[i] = ((nx / len) * 0.5 + 0.5) * 255;
      img.data[i + 1] = ((ny / len) * 0.5 + 0.5) * 255;
      img.data[i + 2] = ((nz / len) * 0.5 + 0.5) * 255;
      img.data[i + 3] = 255;
    }
  }
  ctx.putImageData(img, 0, 0);
  return out;
}

/** Normal mapa dla materiału (cache). */
const normalCache = new Map<MatKind, THREE.Texture>();

export function normalMapFor(kind: MatKind): THREE.Texture {
  const hit = normalCache.get(kind);
  if (hit) return hit;
  const base = texturesFor(kind).map.image as HTMLCanvasElement;
  const strength = kind === 'cobble' ? 3.2 : kind === 'grass' || kind === 'foliage' ? 2.6 : 2.0;
  const t = new THREE.CanvasTexture(normalFrom(base, strength));
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = THREE.NoColorSpace;
  t.anisotropy = 8;
  normalCache.set(kind, t);
  return t;
}

/** Mapa chropowatości — powierzchnie nie są jednolite (plamy, przetarcia). */
const roughCache = new Map<MatKind, THREE.Texture>();

export function roughnessMapFor(kind: MatKind): THREE.Texture {
  const hit = roughCache.get(kind);
  if (hit) return hit;
  const size = 256;
  const c = document.createElement('canvas');
  c.width = c.height = size;
  const ctx = c.getContext('2d')!;
  ctx.fillStyle = '#b8b8b8';
  ctx.fillRect(0, 0, size, size);
  // plamy różnej chropowatości
  for (let i = 0; i < 140; i++) {
    const x = Math.random() * size;
    const y = Math.random() * size;
    const r = 20 + Math.random() * 90;
    const v = 150 + Math.random() * 90;
    const g = ctx.createRadialGradient(x, y, 1, x, y, r);
    g.addColorStop(0, `rgba(${v},${v},${v},.35)`);
    g.addColorStop(1, 'transparent');
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fill();
  }
  // drobne ziarno
  for (let i = 0; i < 20000; i++) {
    const v = 150 + Math.random() * 90;
    ctx.fillStyle = `rgba(${v},${v},${v},.12)`;
    ctx.fillRect(Math.random() * size, Math.random() * size, 2, 2);
  }
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = THREE.NoColorSpace;
  t.anisotropy = 8;
  roughCache.set(kind, t);
  return t;
}

/** Tekstura kępy trawy z przezroczystym tłem (do billboardów). */
let bladeTex: THREE.Texture | null = null;
export function grassBladeTexture(): THREE.Texture {
  if (bladeTex) return bladeTex;
  const size = 256;
  const c = document.createElement('canvas');
  c.width = c.height = size;
  const ctx = c.getContext('2d')!;
  ctx.clearRect(0, 0, size, size);
  for (let i = 0; i < 90; i++) {
    const x = size * (0.08 + Math.random() * 0.84);
    const h = size * (0.35 + Math.random() * 0.6);
    const w = 1.2 + Math.random() * 2.4;
    const bend = (Math.random() - 0.5) * 26;
    const g = 92 + Math.random() * 88;
    const grad = ctx.createLinearGradient(x, size, x, size - h);
    grad.addColorStop(0, `rgba(${26 + Math.random() * 20}, ${Math.round(g * 0.55)}, 24, 1)`);
    grad.addColorStop(1, `rgba(${70 + Math.random() * 50}, ${g}, ${45 + Math.random() * 40}, 1)`);
    ctx.fillStyle = grad;
    ctx.beginPath();
    ctx.moveTo(x, size);
    ctx.quadraticCurveTo(x + bend * 0.5, size - h * 0.55, x + bend, size - h);
    ctx.quadraticCurveTo(x + bend * 0.5 + w, size - h * 0.55, x + w, size);
    ctx.closePath();
    ctx.fill();
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 8;
  bladeTex = t;
  return t;
}
