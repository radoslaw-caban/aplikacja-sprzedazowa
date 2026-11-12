#!/usr/bin/env node
/**
 * Poly Haven (CC0) → app/public/library/
 *
 * Wybór "gorące": Poly Haven nie wystawia sortowania "hot" w API, więc
 * przyjmujemy zamiennik — sortowanie po `download_count` w obrębie kategorii.
 * To ta sama treść, którą strona pokazuje jako najpopularniejszą.
 *
 * Struktura wyjścia:
 *   public/library/tex/<assetId>/<mapa>_1k.jpg   — pliki (współdzielone między kategoriami)
 *   public/library/hdri/<name>_1k.hdr
 *   public/library/models/<id>.glb
 *   public/library/index.json                    — manifest dla edytora
 *
 * Uruchomienie: node tools/fetch-polyhaven.mjs [--force]
 */
import { mkdir, writeFile, stat } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';

const API = 'https://api.polyhaven.com';
const OUT = path.resolve(process.cwd(), 'public/library');
const FORCE = process.argv.includes('--force');
const RES = '1k';
const MAX_MAP_BYTES = 3 * 1024 * 1024;
const MAX_HDRI_BYTES = 4 * 1024 * 1024;
const MAX_MODEL_BYTES = 3 * 1024 * 1024;

/** Kategorie edytora → kategorie Poly Haven. `limit` = ile "gorących" bierzemy. */
const TEXTURE_GROUPS = [
  { id: 'terrain', label: 'Ukształtowanie terenu', match: ['aerial', 'terrain'], limit: 10 },
  { id: 'rocks', label: 'Skałki i gleba', match: ['rock', 'gravel', 'dirty'], limit: 10 },
  { id: 'plants', label: 'Rośliny', match: ['bark', 'natural'], limit: 6 },
  { id: 'paving', label: 'Kostka brukowa', match: ['cobblestone', 'road', 'tiles'], limit: 10 },
  { id: 'fences', label: 'Ogrodzenia i bramy', match: ['metal', 'raw wood'], limit: 6 },
  { id: 'earthworks', label: 'Prace ziemne', match: ['sand', 'gravel', 'dirty'], limit: 6 },
  { id: 'walls', label: 'Budowanie ścian', match: ['brick', 'concrete', 'plaster-concrete'], limit: 8 },
  { id: 'roofing', label: 'Pokrycie dachu', match: ['roofing', 'tiles'], limit: 6 },
  { id: 'facades', label: 'Elewacje', match: ['plaster', 'concrete', 'plaster-concrete'], limit: 8 },
  { id: 'floors', label: 'Podłogi', match: ['wood', 'floor'], limit: 8 },
  { id: 'paint', label: 'Malowanie i tynki', match: ['clean', 'plaster', 'wall'], limit: 8 },
];

/** Pory dnia → konkretne HDRI (kolejność = preferencja, bierzemy pierwsze dostępne). */
const HDRI_GROUPS = [
  { id: 'studio', label: 'Studio (produkt)', names: ['studio_small_09', 'studio_small_03', 'brown_photostudio_02'] },
  { id: 'morning', label: 'Rano', names: ['kloofendal_43d_clear_puresky', 'spruit_sunrise', 'venice_sunset'] },
  { id: 'noon', label: 'Południe', names: ['kloppenheim_06_puresky', 'mpumalanga_veld_puresky', 'qwantani_puresky'] },
  { id: 'evening', label: 'Wieczór', names: ['sunset_jhbcentral', 'the_sky_is_on_fire', 'venice_sunset'] },
  { id: 'night', label: 'Noc', names: ['moonless_golf', 'dikhololo_night', 'satara_night'] },
  { id: 'overcast', label: 'Zachmurzenie', names: ['kloofendal_48d_partly_cloudy_puresky', 'syferfontein_18d_clear_puresky'] },
];

/** Modele natury: rośliny, skały, ziemia. */
const MODEL_GROUPS = [
  { id: 'nature-plants', label: 'Rośliny 3D', match: ['plants', 'trees', 'ground cover'], limit: 8 },
  { id: 'nature-rocks', label: 'Skały 3D', match: ['rocks'], limit: 6 },
];

const MAP_KEYS = { diff: 'Diffuse', nor: 'nor_gl', rough: 'Rough' };

const j = async (url) => {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`${r.status} ${url}`);
  return r.json();
};

async function download(url, dest) {
  if (!FORCE && existsSync(dest)) {
    const s = await stat(dest);
    if (s.size > 1024) return s.size;
  }
  const r = await fetch(url);
  if (!r.ok) throw new Error(`${r.status} ${url}`);
  const buf = Buffer.from(await r.arrayBuffer());
  await mkdir(path.dirname(dest), { recursive: true });
  await writeFile(dest, buf);
  return buf.length;
}

/** Zwraca URL-e map (diff/nor/rough) dla zasobu, albo null gdy któraś brakuje. */
async function textureMaps(assetId) {
  const files = await j(`${API}/files/${assetId}`);
  const out = {};
  for (const [key, apiKey] of Object.entries(MAP_KEYS)) {
    const variant = files[apiKey]?.[RES];
    const ext = variant && ['jpg', 'png'].find((e) => variant[e]);
    if (!ext) return null;
    const meta = variant[ext];
    if (meta.size > MAX_MAP_BYTES) return null;
    out[key] = { url: meta.url, ext, size: meta.size };
  }
  return out;
}

async function buildTextures(assets) {
  const manifest = [];
  const cache = new Map(); // assetId → { maps: {diff: 'tex/id/diff_1k.jpg'} }

  for (const group of TEXTURE_GROUPS) {
    const candidates = Object.entries(assets)
      .filter(([, a]) => group.match.some((m) => (a.categories || []).includes(m)))
      .sort((a, b) => (b[1].download_count || 0) - (a[1].download_count || 0))
      .slice(0, group.limit * 3); // zapas — część odpadnie na brakach map

    let added = 0;
    for (const [id, a] of candidates) {
      if (added >= group.limit) break;
      try {
        let cached = cache.get(id);
        if (!cached) {
          const maps = await textureMaps(id);
          if (!maps) continue;
          const stored = {};
          for (const [key, m] of Object.entries(maps)) {
            const rel = `tex/${id}/${key}_${RES}.${m.ext}`;
            await download(m.url, path.join(OUT, rel));
            stored[key] = rel;
          }
          cached = { maps: stored, dims: a.dimensions };
          cache.set(id, cached);
        }
        manifest.push({
          id: `${group.id}:${id}`,
          assetId: id,
          name: a.name,
          group: group.id,
          dims: cached.dims,
          thumb: a.thumbnail_url,
          maps: cached.maps,
          popularity: a.download_count || 0,
        });
        added++;
        console.log(`  ✓ ${group.id}/${id}`);
      } catch (e) {
        console.warn(`  ! ${id}: ${e.message}`);
      }
    }
  }
  return manifest;
}

async function buildHdris(assets) {
  const out = [];
  for (const group of HDRI_GROUPS) {
    for (const name of group.names) {
      if (!assets[name]) continue;
      try {
        const files = await j(`${API}/files/${name}`);
        const variant = files.hdri?.[RES];
        const meta = variant && variant.hdr;
        if (!meta || meta.size > MAX_HDRI_BYTES) continue;
        const rel = `hdri/${name}_${RES}.hdr`;
        await download(meta.url, path.join(OUT, rel));
        out.push({
          id: `hdri:${name}`,
          assetId: name,
          group: group.id,
          label: group.label,
          name: assets[name].name,
          file: rel,
          size: meta.size,
        });
        console.log(`  ✓ hdri/${name} — ${group.label}`);
        break;
      } catch (e) {
        console.warn(`  ! hdri ${name}: ${e.message}`);
      }
    }
  }
  return out;
}

async function buildModels(assets) {
  const out = [];
  const seen = new Set();
  for (const group of MODEL_GROUPS) {
    const candidates = Object.entries(assets)
      .filter(([, a]) => group.match.some((m) => (a.categories || []).includes(m)))
      .sort((a, b) => (b[1].download_count || 0) - (a[1].download_count || 0))
      .slice(0, group.limit * 3);

    let added = 0;
    for (const [id, a] of candidates) {
      if (added >= group.limit) break;
      if (seen.has(id)) continue;
      try {
        const files = await j(`${API}/files/${id}`);
        const variant = files.gltf?.[RES] || files.gltf?.['2k'] || files.gltf?.['1k'];
        const ext = variant && ['glb', 'gltf'].find((e) => variant[e]);
        if (!ext) continue;
        const meta = variant[ext];
        if (meta.size > MAX_MODEL_BYTES) continue;
        const rel = `models/${id}.${ext}`;
        await download(meta.url, path.join(OUT, rel));
        seen.add(id);
        out.push({
          id: `${group.id}:${id}`,
          assetId: id,
          name: a.name,
          group: group.id,
          file: rel,
          size: meta.size,
        });
        added++;
        console.log(`  ✓ model ${group.id}/${id}`);
      } catch (e) {
        console.warn(`  ! model ${id}: ${e.message}`);
      }
    }
  }
  return out;
}

async function main() {
  console.log('Poly Haven → public/library (CC0)');
  await mkdir(OUT, { recursive: true });

  const [textures, hdris, models] = await Promise.all([
    j(`${API}/assets?t=textures`),
    j(`${API}/assets?t=hdris`),
    j(`${API}/assets?t=models`),
  ]);

  console.log('— tekstury');
  const tex = await buildTextures(textures);
  console.log('— HDRI (pory dnia)');
  const hd = await buildHdris(hdris);
  console.log('— modele natury');
  const mod = await buildModels(models);

  const manifest = {
    generatedAt: new Date().toISOString(),
    license: 'CC0 1.0 — Poly Haven',
    licenseUrl: 'https://polyhaven.com/license',
    attribution: 'Zasoby: Poly Haven (polyhaven.com), licencja CC0 — atrybucja nieobowiązkowa.',
    selection: 'Najpopularniejsze (download_count) w każdej kategorii, rozdzielczość 1k.',
    groups: TEXTURE_GROUPS.map((g) => ({ id: g.id, label: g.label })),
    hdriGroups: HDRI_GROUPS.map((g) => ({ id: g.id, label: g.label })),
    textures: tex,
    hdris: hd,
    models: mod,
  };
  await writeFile(path.join(OUT, 'index.json'), JSON.stringify(manifest, null, 1));
  console.log(`\nGotowe: ${tex.length} tekstur, ${hd.length} HDRI, ${mod.length} modeli`);
}

main().catch((e) => {
  console.error('BŁĄD:', e);
  process.exit(1);
});
