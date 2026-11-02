import { useCallback, useEffect, useRef, useState } from 'react';
import { createEngine } from './engine';
import type { PointCloudData } from './engine/RenderEngine';
import E57Worker from './engine/e57Worker?worker';
import PlyWorker from './engine/plyWorker?worker';
import { buildCabinet } from './design/generator';
import {
  CABINET_TEMPLATES,
  ELEMENT_TEMPLATES,
  appendToRow,
  snapX,
  type CabinetTemplate,
  type ElementTemplate,
} from './design/library';
import { baseCabinet, type Cabinet } from './design/types';
import './App.css';

const CLOUD_URL = `${import.meta.env.BASE_URL}dom-chmura.ply`;
const COLORS = ['#c9a06a', '#b08968', '#e8e2d8', '#2f3437', '#5b6b73', '#8d9b6a'];

interface Selection {
  cabinetId: string;
  elementId?: string;
  kind?: string;
  x: number;
  y: number;
}
type Mode = 'design' | 'scene';

export default function App() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const engineRef = useRef<ReturnType<typeof createEngine> | null>(null);
  const [ready, setReady] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState('');
  const [mode, setMode] = useState<Mode>('design');
  const [cabinets, setCabinets] = useState<Cabinet[]>(() => [baseCabinet('cab1', 300, 0)]);
  const [selection, setSelection] = useState<Selection | null>(null);
  const [libOpen, setLibOpen] = useState(true);

  // ---- silnik ----
  useEffect(() => {
    const engine = createEngine();
    engineRef.current = engine;
    (window as unknown as { engine?: unknown }).engine = engine;
    const canvas = canvasRef.current!;
    let disposed = false;
    (async () => {
      await engine.init(canvas);
      if (disposed) return;
      engine.applyConfig({ autoRotate: false });
      setReady(true);
    })().catch((e) => setError(e instanceof Error ? e.message : String(e)));
    return () => {
      disposed = true;
      engine.dispose();
    };
  }, []);

  // ---- chmura (tło realityczne) ----
  useEffect(() => {
    if (!ready) return;
    const worker = new PlyWorker();
    worker.onmessage = (e: MessageEvent) => {
      const d = e.data;
      if (d.type === 'done') {
        engineRef.current?.loadPointCloud(d as PointCloudData).then(() => {
          setStatus(`Skan: ${d.pointCount.toLocaleString('pl-PL')} pkt`);
        });
      } else if (d.type === 'error') {
        setStatus(`Skan: ${d.message}`);
      }
      worker.terminate();
    };
    fetch(CLOUD_URL)
      .then((r) => {
        if (!r.ok) throw new Error(`PLY ${r.status}`);
        return r.arrayBuffer();
      })
      .then((b) => worker.postMessage({ buffer: b }, [b]))
      .catch((e) => setStatus(`Skan: ${e.message}`));
  }, [ready]);

  // ---- render projektu ----
  const boxes = useCallback(
    () =>
      cabinets.flatMap((c) => {
        const rad = (c.rotation * Math.PI) / 180;
        return buildCabinet(c).map((b) => {
          const x = b.position[0];
          const z = b.position[2];
          return {
            ...b,
            position: [
              x * Math.cos(rad) + z * Math.sin(rad) + c.x,
              b.position[1],
              -x * Math.sin(rad) + z * Math.cos(rad) + c.z,
            ] as [number, number, number],
            rotationY: c.rotation,
          };
        });
      }),
    [cabinets],
  );

  useEffect(() => {
    if (!ready) return;
    engineRef.current?.renderBoxes?.(boxes());
  }, [ready, boxes]);

  // pierwsze kadrowanie na projekt — także po wczytaniu chmury,
  // bo loadPointCloud przestawia kamerę na skan
  const framedRef = useRef(false);
  useEffect(() => {
    if (!ready) return;
    const frame = () => {
      engineRef.current?.frameDesign?.();
      framedRef.current = true;
    };
    const t1 = setTimeout(frame, 300);
    const t2 = setTimeout(frame, 2500);
    return () => {
      clearTimeout(t1);
      clearTimeout(t2);
    };
  }, [ready]);

  // ---- klik w scenę ----
  useEffect(() => {
    if (!ready) return;
    const canvas = canvasRef.current!;
    let down = { x: 0, y: 0, t: 0 };
    const onDown = (e: PointerEvent) => {
      down = { x: e.clientX, y: e.clientY, t: Date.now() };
    };
    const onUp = (e: PointerEvent) => {
      if (Math.hypot(e.clientX - down.x, e.clientY - down.y) > 6 || Date.now() - down.t > 600) return;
      const hit = engineRef.current?.pickAt?.(e.clientX, e.clientY);
      if (!hit || !hit.cabinetId) {
        setSelection(null);
        engineRef.current?.highlightElement?.(null);
        return;
      }
      setSelection({
        cabinetId: hit.cabinetId,
        elementId: hit.elementId,
        kind: hit.kind,
        x: hit.screen.x,
        y: hit.screen.y,
      });
      engineRef.current?.highlightElement?.(hit.elementId ?? null);
    };
    canvas.addEventListener('pointerdown', onDown);
    canvas.addEventListener('pointerup', onUp);
    return () => {
      canvas.removeEventListener('pointerdown', onDown);
      canvas.removeEventListener('pointerup', onUp);
    };
  }, [ready]);

  // ---- operacje ----
  const addCabinet = (t: CabinetTemplate) => setCabinets((cs) => [...cs, appendToRow(cs, t, 0)]);

  const addElement = (c: Cabinet, t: ElementTemplate) =>
    setCabinets((cs) =>
      cs.map((x) =>
        x.id !== c.id
          ? x
          : {
              ...x,
              elements: [
                ...x.elements,
                {
                  id: `${x.id}-${Math.random().toString(36).slice(2, 7)}`,
                  kind: t.kind,
                  variant: t.variant,
                  y: 120 + x.elements.length * 160,
                  x0: 0,
                  x1: 0,
                },
              ],
            },
      ),
    );

  const patchElement = (cabId: string, elId: string, patch: Record<string, unknown>) =>
    setCabinets((cs) =>
      cs.map((c) =>
        c.id !== cabId
          ? c
          : { ...c, elements: c.elements.map((e) => (e.id === elId ? { ...e, ...patch } : e)) },
      ),
    );

  const patchCabinet = (id: string, patch: Partial<Cabinet>) =>
    setCabinets((cs) => cs.map((c) => (c.id === id ? { ...c, ...patch } : c)));

  const removeElement = (cabId: string, elId: string) => {
    setCabinets((cs) =>
      cs.map((c) => (c.id !== cabId ? c : { ...c, elements: c.elements.filter((e) => e.id !== elId) })),
    );
    setSelection(null);
    engineRef.current?.highlightElement?.(null);
  };

  const importCloud = async (file: File) => {
    setError(null);
    setStatus(`Czytam ${file.name}…`);
    try {
      const buffer = await file.arrayBuffer();
      const isPly = file.name.toLowerCase().endsWith('.ply');
      const worker = isPly ? new PlyWorker() : new E57Worker();
      worker.onmessage = (e: MessageEvent) => {
        const d = e.data;
        if (d.type === 'error') {
          setError(d.message);
          setStatus('');
          worker.terminate();
        } else if (d.type === 'done') {
          engineRef.current?.loadPointCloud(d as PointCloudData).then(() => {
            setStatus(`Skan: ${d.pointCount.toLocaleString('pl-PL')} pkt`);
          });
          worker.terminate();
        } else if (d.type === 'progress') {
          setStatus(`Parsowanie: ${Number(d.loadedPoints).toLocaleString('pl-PL')} pkt`);
        }
      };
      worker.postMessage({ buffer }, [buffer]);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  const selCabinet = selection ? cabinets.find((c) => c.id === selection.cabinetId) : undefined;
  const selElement = selCabinet?.elements.find((e) => e.id === selection?.elementId);

  return (
    <div className="app">
      <header>
        <h1>Projektant szafek</h1>
        <div className="header-right">
          <div className="modes">
            <button className={mode === 'design' ? 'on' : ''} onClick={() => setMode('design')}>
              Projekt
            </button>
            <button className={mode === 'scene' ? 'on' : ''} onClick={() => setMode('scene')}>
              Skan
            </button>
          </div>
          <span className="badge ok">{status || (ready ? 'gotowe' : 'ładowanie…')}</span>
          <button className="chip" onClick={() => engineRef.current?.frameDesign?.()}>Kadruj</button>
        </div>
      </header>

      <div className="stage">
        <canvas ref={canvasRef} />
        {!ready && !error && <div className="loader">Ładowanie…</div>}
        {error && <div className="loader error">⚠️ {error}</div>}
        <p className="hint">Przeciągnij, aby obrócić · kliknij element, aby go edytować</p>

        {selection && selCabinet && (
          <div
            className="bubble"
            style={{
              left: Math.min(Math.max(selection.x, 110), window.innerWidth - 110),
              top: Math.max(selection.y - 12, 60),
            }}
          >
            <div className="bubble-title">
              {selElement
                ? ELEMENT_TEMPLATES.find((t) => t.kind === selElement.kind)?.label ?? selElement.kind
                : selCabinet.name}
            </div>

            {selElement ? (
              <>
                <button onClick={() => patchElement(selCabinet.id, selElement.id, { holes: !selElement.holes })}>
                  {selElement.holes ? 'Usuń otwory' : 'Wiercenie (32 mm)'}
                </button>
                <div className="bubble-row2">
                  <button onClick={() => patchElement(selCabinet.id, selElement.id, { y: selElement.y + 32 })}>
                    ↑ Wyżej
                  </button>
                  <button
                    onClick={() =>
                      patchElement(selCabinet.id, selElement.id, { y: Math.max(0, selElement.y - 32) })
                    }
                  >
                    ↓ Niżej
                  </button>
                </div>
                <div className="bubble-colors">
                  {COLORS.map((col) => (
                    <button
                      key={col}
                      className="dot"
                      style={{ background: col }}
                      onClick={() => patchElement(selCabinet.id, selElement.id, { color: col })}
                    />
                  ))}
                </div>
                <button className="danger" onClick={() => removeElement(selCabinet.id, selElement.id)}>
                  Usuń element
                </button>
              </>
            ) : (
              <>
                <div className="bubble-row">
                  <label>Szer.</label>
                  <input
                    type="range" min={300} max={1200} step={10}
                    value={selCabinet.width}
                    onChange={(e) => patchCabinet(selCabinet.id, { width: +e.target.value })}
                  />
                  <span className="val">{selCabinet.width}</span>
                </div>
                <div className="bubble-row">
                  <label>Głęb.</label>
                  <input
                    type="range" min={300} max={650} step={10}
                    value={selCabinet.depth}
                    onChange={(e) => patchCabinet(selCabinet.id, { depth: +e.target.value })}
                  />
                  <span className="val">{selCabinet.depth}</span>
                </div>
                <div className="bubble-row">
                  <label>Fronty</label>
                  <input
                    type="range" min={0} max={3} step={1}
                    value={selCabinet.doors}
                    onChange={(e) => patchCabinet(selCabinet.id, { doors: +e.target.value })}
                  />
                  <span className="val">{selCabinet.doors}</span>
                </div>
                <div className="bubble-colors">
                  {COLORS.map((col) => (
                    <button
                      key={col}
                      className="dot"
                      style={{ background: col }}
                      onClick={() => patchCabinet(selCabinet.id, { color: col })}
                    />
                  ))}
                </div>
                <button
                  onClick={() =>
                    setCabinets((cs) => {
                      const c = cs.find((x) => x.id === selCabinet.id);
                      if (!c) return cs;
                      const nx = snapX(cs, c);
                      return cs.map((x) => (x.id === c.id ? { ...x, x: nx } : x));
                    })
                  }
                >
                  Dociągnij do sąsiada
                </button>
                <button
                  className="danger"
                  onClick={() => {
                    setCabinets((cs) => cs.filter((c) => c.id !== selCabinet.id));
                    setSelection(null);
                  }}
                >
                  Usuń szafkę
                </button>
              </>
            )}
          </div>
        )}
      </div>

      {mode === 'scene' && (
        <div className="panel">
          <label className="import-btn">
            📂 Wczytaj skan (.e57 / .ply)
            <input
              type="file"
              accept=".e57,.ply"
              style={{ display: 'none' }}
              onChange={(e) => {
                const f = e.target.files?.[0];
                if (f) importCloud(f);
                e.target.value = '';
              }}
            />
          </label>
        </div>
      )}

      {mode === 'design' && libOpen && (
        <div className="library">
          <div className="lib-section">
            <div className="lib-title">Szafki</div>
            <div className="lib-items">
              {CABINET_TEMPLATES.map((t) => (
                <div key={t.key} className="lib-item" onClick={() => addCabinet(t)}>
                  {t.label}
                </div>
              ))}
            </div>
          </div>
          <div className="lib-section">
            <div className="lib-title">
              Elementy {selCabinet ? `→ ${selCabinet.name}` : '(kliknij szafkę)'}
            </div>
            <div className="lib-items">
              {ELEMENT_TEMPLATES.map((t) => (
                <div
                  key={t.key}
                  className={`lib-item ${selCabinet ? '' : 'dim'}`}
                  onClick={() => selCabinet && addElement(selCabinet, t)}
                >
                  {t.label}
                </div>
              ))}
            </div>
          </div>
          <button className="lib-toggle" onClick={() => setLibOpen(false)}>▾</button>
        </div>
      )}
      {mode === 'design' && !libOpen && (
        <button className="lib-open" onClick={() => setLibOpen(true)}>Biblioteka ▴</button>
      )}
    </div>
  );
}
