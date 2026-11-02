/**
 * Web Worker: import E57 przez dekoder WASM (e57-js / libE57).
 * Pliki 5 GB / 20–50 mln pkt czytane porcjami + decymacja (stride),
 * żeby zmieścić się w pamięci tabletu.
 */

interface E57Point {
  cartesianX: number;
  cartesianY: number;
  cartesianZ: number;
  colorRed?: number;
  colorGreen?: number;
  colorBlue?: number;
}

interface VectorPoint {
  size(): number;
  get(i: number): E57Point;
  delete?(): void;
}

/** Maksymalna liczba punktów wczytanych do renderu (reszta pomijana). */
const MAX_POINTS = 8_000_000;
const CHUNK = 200_000;

self.onmessage = async (e: MessageEvent) => {
  const { buffer } = e.data as { buffer: ArrayBuffer };
  const post = (msg: object, transfer: Transferable[] = []) =>
    (self as unknown as Worker).postMessage(msg, transfer);

  try {
    // e57-js sprawdza `typeof window` aby wybrać ścieżkę przeglądarkową zamiast
    // Node/NODEFS — w Workerze `window` nie istnieje, więc podstawiamy self.
    (self as unknown as { window: unknown }).window = self;
    const base = import.meta.env.BASE_URL || '/';
    // dekoder WASM serwowany statycznie z /e57js/
    const mod = await import(/* @vite-ignore */ `${base}e57js/index.browser.mjs`);
    const E57 = mod.E57;
    const E57Reader = mod.E57Reader;
    await E57.Init();

    const reader = E57Reader.FromBuffer(new Uint8Array(buffer));
    const scanCount = Number(reader.GetData3DCount());
    if (!scanCount) throw new Error('Plik E57 nie zawiera skanów (data3D)');

    // policz łączną liczbę punktów i ustal krok decymacji
    let total = 0;
    for (let s = 0; s < scanCount; s++) {
      total += Number(reader.GetScan(s).GetHeader().pointCount);
    }
    const stride = Math.max(1, Math.ceil(total / MAX_POINTS));
    const expected = Math.ceil(total / stride);
    post({ type: 'meta', totalPoints: total, stride, expected });

    const positions = new Float32Array(expected * 3);
    let colors: Uint8Array | undefined;
    let out = 0;
    let seen = 0;
    let hasColor = true;

    const push = (pts: VectorPoint) => {
      const n = pts.size();
      for (let i = 0; i < n; i++) {
        const idx = seen + i;
        if (idx % stride !== 0) continue;
        const p = pts.get(i);
        const x = p.cartesianX;
        const y = p.cartesianY;
        const z = p.cartesianZ;
        if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(z)) continue;
        if (out >= expected) continue;
        if (!colors && hasColor) colors = new Uint8Array(expected * 3);
        positions[out * 3] = x;
        positions[out * 3 + 1] = y;
        positions[out * 3 + 2] = z;
        if (hasColor && colors) {
          const r = p.colorRed;
          const g = p.colorGreen;
          const b = p.colorBlue;
          if (r === undefined || g === undefined || b === undefined) {
            hasColor = false;
            colors = undefined;
          } else {
            colors[out * 3] = r;
            colors[out * 3 + 1] = g;
            colors[out * 3 + 2] = b;
          }
        }
        out++;
      }
      seen += n;
      post({ type: 'progress', loadedPoints: out, totalPoints: expected });
    };

    for (let s = 0; s < scanCount; s++) {
      const scan = reader.GetScan(s);
      const chunks = Math.ceil(Number(scan.GetHeader().pointCount) / CHUNK);
      for (let c = 0; c < chunks; c++) {
        const pts = scan.ReadPointsSync(CHUNK, true) as VectorPoint;
        push(pts);
        pts.delete?.();
      }
    }

    if (out === 0) throw new Error('Nie udało się odczytać punktów z pliku');

    const finalPositions = positions.subarray(0, out * 3);
    const finalColors = colors ? colors.subarray(0, out * 3) : undefined;
    const transfer: Transferable[] = [finalPositions.buffer];
    if (finalColors) transfer.push(finalColors.buffer);
    post({ type: 'done', positions: finalPositions, colors: finalColors, pointCount: out }, transfer);
    reader.Close();
  } catch (err) {
    post({ type: 'error', message: err instanceof Error ? err.message : String(err) });
  }
};