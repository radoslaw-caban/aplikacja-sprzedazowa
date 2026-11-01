import { E57Parser } from './E57Parser';

/**
 * Web Worker: parsowanie E57 w tle (UI nie zamarza przy 5 GB / 20–50 mln pkt).
 * Odbiera ArrayBuffer (transferable, zero-copy), zwraca Float32Array/Uint8Array (transfer).
 */

self.onmessage = (e: MessageEvent) => {
  const { buffer } = e.data as { buffer: ArrayBuffer };
  const post = (msg: object, transfer: Transferable[] = []) =>
    (self as unknown as Worker).postMessage(msg, transfer);
  try {
    const parser = new E57Parser(buffer);

    const scans = parser.parseScans((p) => post({ type: 'progress', ...p }));
    if (!scans.length) {
      post({ type: 'error', message: 'Nie znaleziono skanów w pliku E57' });
      return;
    }
    // scal wszystkie skany w jedną chmurę
    const total = scans.reduce((a, s) => a + s.pointCount, 0);
    const positions = new Float32Array(total * 3);
    let colors: Uint8Array | undefined = scans.some((s) => s.colors) ? new Uint8Array(total * 3) : undefined;
    let off = 0;
    const bboxMin: [number, number, number] = [Infinity, Infinity, Infinity];
    const bboxMax: [number, number, number] = [-Infinity, -Infinity, -Infinity];
    for (const s of scans) {
      positions.set(s.positions, off * 3);
      if (colors && s.colors) colors.set(s.colors, off * 3);
      for (let k = 0; k < 3; k++) {
        bboxMin[k] = Math.min(bboxMin[k], s.bboxMin[k]);
        bboxMax[k] = Math.max(bboxMax[k], s.bboxMax[k]);
      }
      off += s.pointCount;
    }
    const transfer: Transferable[] = [positions.buffer];
    if (colors) transfer.push(colors.buffer);
    post({ type: 'done', positions, colors, pointCount: total, bboxMin, bboxMax }, transfer);
  } catch (err) {
    post({ type: 'error', message: err instanceof Error ? err.message : String(err) });
  }
};
