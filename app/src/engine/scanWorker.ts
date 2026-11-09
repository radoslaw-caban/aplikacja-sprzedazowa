/**
 * Web Worker: import skanu z iPada/telefonu (PLY / PCD / XYZ).
 *
 * Osobny worker od E57, bo tamten ładuje dekoder WASM — tutaj wszystko jest
 * czystym JS-em. Parsowanie dużego PLY (100 MB) trzyma UI płynne.
 */

import { parsePointCloud, type ScanFormat } from './scanFormats';

export interface ScanImportRequest {
  format: ScanFormat;
  buffer: ArrayBuffer;
  maxPoints?: number;
}

self.onmessage = (e: MessageEvent) => {
  const { format, buffer, maxPoints } = e.data as ScanImportRequest;
  const post = (msg: object, transfer: Transferable[] = []) =>
    (self as unknown as Worker).postMessage(msg, transfer);
  try {
    const cloud = parsePointCloud(format, buffer, {
      maxPoints,
      onProgress: (f) => post({ type: 'progress', fraction: f }),
    });
    const transfer: Transferable[] = [cloud.positions.buffer];
    if (cloud.colors) transfer.push(cloud.colors.buffer);
    post({ type: 'done', cloud }, transfer);
  } catch (err) {
    post({ type: 'error', message: err instanceof Error ? err.message : String(err) });
  }
};