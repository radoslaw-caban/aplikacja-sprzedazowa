import { useEffect, useRef, useState } from 'react';
import {
  POINT_FORMATS,
  MESH_FORMATS,
  detectFormat,
  isPointFormat,
  guessUnit,
  type ScanCloud,
  type ScanFormat,
} from '../engine/scanFormats';
import type { CloudTransform } from '../engine/RenderEngine';
import ScanWorker from '../engine/scanWorker?worker';

export interface ScanMeta {
  name: string;
  format: ScanFormat;
  pointCount: number;
  rawCount: number;
  stride: number;
  /** bbox w jednostkach pliku */
  bboxMin: [number, number, number];
  bboxMax: [number, number, number];
}

interface Props {
  /** plik przekazany z zewnątrz (przeciągnięty na scenę) — wczytywany od razu */
  pendingFile?: File | null;
  onPendingConsumed?: () => void;
  meta: ScanMeta | null;
  transform: CloudTransform;
  /** wymiary po transformacji (metry) — z silnika */
  dims: { x: number; y: number; z: number } | null;
  onCloud: (cloud: ScanCloud, meta: ScanMeta, transform: CloudTransform) => void;
  onMesh: (file: File) => void;
  onTransform: (t: CloudTransform) => void;
  onFrame: () => void;
  onClose: () => void;
}

const UNIT_PRESET: Record<'m' | 'cm' | 'mm', number> = { m: 1, cm: 0.01, mm: 0.001 };

/**
 * Import skanu z iPada / telefonu (LiDAR / fotogrametria).
 * Nie udajemy, że przeglądarka ma dostęp do LiDAR-u — przyjmujemy gotowy plik
 * wyeksportowany przez apkę (3D Scanner App, Polycam, Scaniverse, Modelar):
 * chmurę punktów (PLY/PCD/XYZ) albo siatkę (GLB/GLTF/OBJ/STL).
 */
export default function ScanPanel({
  pendingFile,
  onPendingConsumed,
  meta,
  transform,
  dims,
  onCloud,
  onMesh,
  onTransform,
  onFrame,
  onClose,
}: Props) {
  const fileRef = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [progress, setProgress] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [dragOver, setDragOver] = useState(false);
  const workerRef = useRef<Worker | null>(null);

  useEffect(() => () => workerRef.current?.terminate(), []);

  // plik przeciągnięty na scenę: panel dostaje go i od razu przetwarza
  useEffect(() => {
    if (!pendingFile) return;
    handleFile(pendingFile);
    onPendingConsumed?.();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pendingFile]);

  /** Punkty: parsowanie w Web Workerze — duże PLY nie zamrozi UI. */
  const importPoints = (file: File, format: ScanFormat) => {
    setError(null);
    setBusy(`Czytam ${format.toUpperCase()}…`);
    setProgress(0);
    const worker = new ScanWorker();
    workerRef.current = worker;
    worker.onmessage = (e: MessageEvent) => {
      const d = e.data;
      if (d.type === 'progress') {
        setProgress(Math.round((d.fraction as number) * 100));
        return;
      }
      worker.terminate();
      workerRef.current = null;
      if (d.type === 'error') {
        setBusy(null);
        setError(d.message as string);
        return;
      }
      const cloud = d.cloud as ScanCloud;
      const guess = guessUnit(cloud.bboxMin, cloud.bboxMax);
      const t: CloudTransform = { ...transform, scale: guess.scale };
      const m: ScanMeta = {
        name: file.name,
        format,
        pointCount: cloud.pointCount,
        rawCount: cloud.rawCount,
        stride: cloud.stride,
        bboxMin: cloud.bboxMin,
        bboxMax: cloud.bboxMax,
      };
      setBusy(null);
      setProgress(100);
      onCloud(cloud, m, t);
    };
    file
      .arrayBuffer()
      .then((buf) => worker.postMessage({ format, buffer: buf }, [buf]))
      .catch((err) => {
        setBusy(null);
        setError(err instanceof Error ? err.message : String(err));
      });
  };

  const handleFile = (file: File) => {
    const format = detectFormat(file.name);
    if (!format) {
      setError(`Nieznany format: ${file.name}. Obsługiwane: PLY, PCD, XYZ, CSV, GLB, GLTF, OBJ, STL`);
      return;
    }
    if (isPointFormat(format)) importPoints(file, format);
    else {
      setError(null);
      setBusy(`Wczytuję siatkę ${format.toUpperCase()}…`);
      onMesh(file);
      setTimeout(() => setBusy(null), 1200);
    }
  };

  const setUnit = (u: 'm' | 'cm' | 'mm') => onTransform({ ...transform, scale: UNIT_PRESET[u] });
  const currentUnit: 'm' | 'cm' | 'mm' =
    Math.abs(transform.scale - 0.01) < 1e-6 ? 'cm' : Math.abs(transform.scale - 0.001) < 1e-6 ? 'mm' : 'm';

  const mm = (v: number) => Math.round(v * 1000);

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal modal-wide scan-modal" onClick={(e) => e.stopPropagation()}>
        <h2>Skan z iPada / telefonu</h2>
        <p className="modal-sub">
          Safari na iPadzie nie udostępnia LiDAR-u stronie WWW — dlatego importujemy plik z aplikacji
          skanującej. Świetnie działa: 3D Scanner App, Polycam (model), Scaniverse, Modelar.
        </p>

        <div
          className={`dropzone ${dragOver ? 'over' : ''}`}
          onDragOver={(e) => {
            e.preventDefault();
            setDragOver(true);
          }}
          onDragLeave={() => setDragOver(false)}
          onDrop={(e) => {
            e.preventDefault();
            setDragOver(false);
            const f = e.dataTransfer.files?.[0];
            if (f) handleFile(f);
          }}
          onClick={() => fileRef.current?.click()}
        >
          <strong>Przeciągnij plik skanu</strong>
          <span>PLY · PCD · XYZ/CSV · GLB · GLTF · OBJ · STL</span>
          <span className="dropzone-hint">albo kliknij, żeby wybrać z dysku / z „Plików” na iPadzie</span>
        </div>
        <input
          ref={fileRef}
          type="file"
          accept={[...POINT_FORMATS.map((f) => `.${f}`), ...MESH_FORMATS.map((f) => `.${f}`), '.txt', '.csv'].join(',')}
          style={{ display: 'none' }}
          onChange={(e) => {
            const f = e.target.files?.[0];
            if (f) handleFile(f);
            e.target.value = '';
          }}
        />

        {busy && (
          <div className="scan-progress">
            <span>{busy}</span>
            <div className="bar"><i style={{ width: `${progress}%` }} /></div>
          </div>
        )}
        {error && <p className="scan-error">⚠️ {error}</p>}

        {meta && (
          <>
            <div className="modal-section">Wczytany skan</div>
            <div className="scan-info">
              <span><b>{meta.name}</b></span>
              <span className="mono">{meta.format}</span>
              <span>
                {meta.pointCount > 0
                  ? `${meta.pointCount.toLocaleString('pl-PL')} pkt${meta.stride > 1 ? ` z ${meta.rawCount.toLocaleString('pl-PL')} (krok ${meta.stride})` : ''}`
                  : 'siatka trójkątów (bez chmury punktów)'}
              </span>
            </div>

            {meta.pointCount > 0 && (
            <>
            <div className="modal-section">Jednostka pliku</div>
            <div className="seg">
              {(['m', 'cm', 'mm'] as const).map((u) => (
                <button key={u} className={currentUnit === u ? 'on' : ''} onClick={() => setUnit(u)}>
                  {u}
                </button>
              ))}
            </div>
            <p className="modal-hint">
              Skan ARKit jest w metrach. Jeśli model wyszedł 1000× za duży/mały — przełącz jednostkę.
            </p>

            <div className="modal-section">Ustawienie w pomieszczeniu</div>
            <div className="scan-grid">
              <label>
                Obrót [°]
                <input
                  type="number"
                  step={15}
                  value={Math.round(transform.rotationY)}
                  onChange={(e) => onTransform({ ...transform, rotationY: +e.target.value })}
                />
              </label>
              <label>
                X [mm]
                <input
                  type="number"
                  step={50}
                  value={mm(transform.offset[0])}
                  onChange={(e) =>
                    onTransform({ ...transform, offset: [+e.target.value / 1000, transform.offset[1], transform.offset[2]] })
                  }
                />
              </label>
              <label>
                Y [mm]
                <input
                  type="number"
                  step={50}
                  value={mm(transform.offset[1])}
                  onChange={(e) =>
                    onTransform({ ...transform, offset: [transform.offset[0], +e.target.value / 1000, transform.offset[2]] })
                  }
                />
              </label>
              <label>
                Z [mm]
                <input
                  type="number"
                  step={50}
                  value={mm(transform.offset[2])}
                  onChange={(e) =>
                    onTransform({ ...transform, offset: [transform.offset[0], transform.offset[1], +e.target.value / 1000] })
                  }
                />
              </label>
            </div>
            </>
            )}
            {dims && (
              <p className="modal-hint">
                Wymiary skanu: <b>{mm(dims.x)} × {mm(dims.y)} × {mm(dims.z)} mm</b> — porównaj z realnym pomieszczeniem.
              </p>
            )}
          </>
        )}

        <div className="modal-actions">
          {meta && (
            <button className="ghost" onClick={onFrame}>
              {meta.pointCount > 0 ? 'Kadruj na skan' : 'Kadruj na siatkę'}
            </button>
          )}
          {meta && meta.pointCount > 0 && (
            <button className="ghost" onClick={() => onTransform({ scale: 1, rotationY: 0, offset: [0, 0, 0] })}>
              Reset transformacji
            </button>
          )}
          <button className="primary" onClick={onClose}>Zamknij</button>
        </div>
      </div>
    </div>
  );
}