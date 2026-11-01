import { parsePly } from './plyParser';

/** Web Worker: parsowanie PLY w tle. */
self.onmessage = (e: MessageEvent) => {
  const { buffer } = e.data as { buffer: ArrayBuffer };
  try {
    const cloud = parsePly(buffer);
    const transfer: Transferable[] = [cloud.positions.buffer];
    if (cloud.colors) transfer.push(cloud.colors.buffer);
    (self as unknown as Worker).postMessage({ type: 'done', ...cloud }, transfer);
  } catch (err) {
    (self as unknown as Worker).postMessage({
      type: 'error',
      message: err instanceof Error ? err.message : String(err),
    });
  }
};
