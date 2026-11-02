import { useCallback, useEffect, useRef, useState } from 'react';
import { createEngine } from './engine';
import type { PointCloudData } from './engine/RenderEngine';
import PlyWorker from './engine/plyWorker?worker';
import { buildCabinet, innerDepth, innerWidth } from './design/generator';
import {
  ELEMENT_TEMPLATES,
  LIBRARY_GROUPS,
  appendToRow,
  byGroup,
  snapX,
  summarize,
  type CabinetTemplate,
  type ElementTemplate,
} from './design/library';
import { baseCabinet, makeDoors, type Cabinet } from './design/types';
import OrganizerPanel from './ui/OrganizerPanel';
import { makeLayout } from './design/organizer';
import './App.css';

const CLOUD_URL = `${import.meta.env.BASE_URL}dom-chmura.ply`;
const COLORS = ['#e8e2d8', '#c9a06a', '#b08968', '#2f3437', '#5b6b73', '#8d9b6a'];

type Tab = 'layout' | 'interior';

interface Selection {
  cabinetId: string;
  elementId?: string;
  frontId?: string;
  kind?: string;
  x: number;
  y: number;
}

export default function App() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const engineRef = useRef<ReturnType<typeof createEngine> | null>(null);
  const [ready, setReady] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState('');
  const [tab, setTab] = useState<Tab>('layout');
  const [cabinets, setCabinets] = useState<Cabinet[]>(() => [baseCabinet('cab1', 300, 0)]);
  const [selection, setSelection] = useState<Selection | null>(null);
  const [activeId, setActiveId] = useState<string | null>(null);
  const [orgFor, setOrgFor] = useState<string | null>(null);

  const active = cabinets.find((c) => c.id === activeId) ?? cabinets[0];

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

  // ---- render ----
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
            rotationY: (b.rotationY ?? 0) + c.rotation,
          };
        });
      }),
    [cabinets],
  );

  useEffect(() => {
    if (!ready) return;
    engineRef.current?.renderBoxes?.(boxes());
  }, [ready, boxes]);

  useEffect(() => {
    if (!ready) return;
    const f = () => engineRef.current?.frameDesign?.();
    const t1 = setTimeout(f, 300);
    const t2 = setTimeout(f, 2500);
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
      setActiveId(hit.cabinetId);
      setSelection({
        cabinetId: hit.cabinetId,
        elementId: hit.elementId,
        frontId: hit.frontId,
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
  const patchCabinet = (id: string, patch: Partial<Cabinet>) =>
    setCabinets((cs) => cs.map((c) => (c.id === id ? { ...c, ...patch } : c)));

  const addCabinet = (t: CabinetTemplate) => {
    const c = appendToRow(cabinets, t, 0);
    setCabinets((cs) => [...cs, c]);
    setActiveId(c.id);
  };

  const addElement = (t: ElementTemplate) => {
    if (!active) return;
    setCabinets((cs) =>
      cs.map((c) =>
        c.id !== active.id
          ? c
          : {
              ...c,
              elements: [
                ...c.elements,
                {
                  id: `e${Math.random().toString(36).slice(2, 8)}`,
                  kind: t.kind,
                  variant: t.variant,
                  y: 100 + c.elements.length * 180,
                  x0: 0,
                  x1: 0,
                },
              ],
            },
      ),
    );
  };

  const patchElement = (elId: string, patch: Record<string, unknown>) => {
    if (!active) return;
    setCabinets((cs) =>
      cs.map((c) =>
        c.id !== active.id
          ? c
          : { ...c, elements: c.elements.map((e) => (e.id === elId ? { ...e, ...patch } : e)) },
      ),
    );
  };

  const removeElement = (elId: string) => {
    if (!active) return;
    setCabinets((cs) =>
      cs.map((c) => (c.id !== active.id ? c : { ...c, elements: c.elements.filter((e) => e.id !== elId) })),
    );
    setSelection(null);
  };

  /** Wejście do wnętrza: otwórz fronty i ustaw kamerę (przed szafkę / do szuflady). */
  const enterInterior = (cab: Cabinet, elementY?: number) => {
    setActiveId(cab.id);
    setTab('interior');
    const opened = { ...cab, fronts: cab.fronts.map((f) => ({ ...f, open: 1 })) };
    patchCabinet(cab.id, { fronts: opened.fronts });
    setTimeout(
      () => engineRef.current?.frameInterior?.(opened, elementY !== undefined ? 'drawer' : 'front', elementY),
      130,
    );
  };

  const selElement = active?.elements.find((e) => e.id === selection?.elementId);
  const selFront = active?.fronts.find((f) => f.id === selection?.frontId);
  const summary = active ? summarize(active) : null;

  return (
    <div className="app">
      <header>
        <h1>Projektant szafek</h1>
        <div className="header-right">
          <div className="modes">
            <button className={tab === 'layout' ? 'on' : ''} onClick={() => setTab('layout')}>
              Układ
            </button>
            <button
              className={tab === 'interior' ? 'on' : ''}
              onClick={() => active && enterInterior(active)}
            >
              Wnętrze
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
        <p className="hint">
          {tab === 'layout'
            ? 'Układ: kliknij szafkę, aby wybrać · przeciągnij, aby obrócić'
            : 'Wnętrze: fronty otwarte · kliknij element, aby go edytować'}
        </p>

        {tab === 'interior' && active && (
          <div className="interior-bar">
            <strong>{active.name}</strong>
            <div className="modes">
              <button onClick={() => engineRef.current?.frameInterior?.(active, 'front')}>Przed szafkę</button>
              <button onClick={() => engineRef.current?.frameInterior?.(active, 'drawer')}>Do szuflady</button>
              <button
                onClick={() =>
                  patchCabinet(active.id, { fronts: active.fronts.map((f) => ({ ...f, open: 0 })) })
                }
              >
                Zamknij fronty
              </button>
            </div>
            {summary && (
              <span className="sum">
                półki {summary.shelves} · szuflady {summary.drawers} · przegrody {summary.dividers} · płyta{' '}
                {summary.panelArea.toFixed(2)} m²
              </span>
            )}
          </div>
        )}

        {selection && active && (
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
                : selFront
                  ? selFront.kind === 'door'
                    ? 'Front (drzwi)'
                    : 'Front szuflady'
                  : active.name}
            </div>

            {selFront && (
              <>
                <button
                  onClick={() =>
                    patchCabinet(active.id, {
                      fronts: active.fronts.map((f) =>
                        f.id === selFront.id ? { ...f, open: f.open > 0.5 ? 0 : 1 } : f,
                      ),
                    })
                  }
                >
                  {selFront.open > 0.5 ? 'Zamknij front' : 'Otwórz front'}
                </button>
                <button onClick={() => enterInterior(active)}>Wejdź do wnętrza →</button>
              </>
            )}

            {selElement && (
              <>
                <button onClick={() => patchElement(selElement.id, { holes: !selElement.holes })}>
                  {selElement.holes ? 'Usuń otwory' : 'Wiercenie (32 mm)'}
                </button>
                <div className="bubble-row2">
                  <button onClick={() => patchElement(selElement.id, { y: selElement.y + 32 })}>↑ Wyżej</button>
                  <button onClick={() => patchElement(selElement.id, { y: Math.max(0, selElement.y - 32) })}>
                    ↓ Niżej
                  </button>
                </div>
                <button onClick={() => enterInterior(active, selElement.y)}>Kamera do szuflady</button>
                {(selElement.kind === 'drawer' ||
                  selElement.kind === 'innerDrawer' ||
                  selElement.kind === 'drawerSystem') && (
                  <button onClick={() => setOrgFor(selElement.id)}>🧩 Pojemniki…</button>
                )}
                <div className="bubble-colors">
                  {COLORS.map((col) => (
                    <button
                      key={col}
                      className="dot"
                      style={{ background: col }}
                      onClick={() => patchElement(selElement.id, { color: col })}
                    />
                  ))}
                </div>
                <button className="danger" onClick={() => removeElement(selElement.id)}>Usuń element</button>
              </>
            )}

            {!selElement && !selFront && (
              <>
                <div className="bubble-row">
                  <label>Szer.</label>
                  <input
                    type="range" min={300} max={1200} step={10}
                    value={active.width}
                    onChange={(e) => {
                      const w = +e.target.value;
                      const next = { ...active, width: w };
                      patchCabinet(active.id, {
                        width: w,
                        fronts: active.fronts.length ? makeDoors(next, active.fronts.length) : [],
                      });
                    }}
                  />
                  <span className="val">{active.width}</span>
                </div>
                <div className="bubble-row">
                  <label>Głęb.</label>
                  <input
                    type="range" min={300} max={650} step={10}
                    value={active.depth}
                    onChange={(e) => patchCabinet(active.id, { depth: +e.target.value })}
                  />
                  <span className="val">{active.depth}</span>
                </div>
                <div className="bubble-row">
                  <label>Fronty</label>
                  <input
                    type="range" min={0} max={3} step={1}
                    value={active.fronts.length}
                    onChange={(e) => patchCabinet(active.id, { fronts: makeDoors(active, +e.target.value) })}
                  />
                  <span className="val">{active.fronts.length}</span>
                </div>
                <div className="bubble-colors">
                  {COLORS.map((col) => (
                    <button
                      key={col}
                      className="dot"
                      style={{ background: col }}
                      onClick={() => patchCabinet(active.id, { color: col })}
                    />
                  ))}
                </div>
                <button onClick={() => enterInterior(active)}>Otwórz i wejdź do wnętrza</button>
                <button
                  onClick={() =>
                    setCabinets((cs) => {
                      const c = cs.find((x) => x.id === active.id);
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
                    setCabinets((cs) => cs.filter((c) => c.id !== active.id));
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

      {tab === 'layout' ? (
        <div className="library">
          {LIBRARY_GROUPS.map((g) => (
            <div className="lib-section" key={g}>
              <div className="lib-title">{g}</div>
              <div className="lib-items">
                {byGroup(g).map((t) => (
                  <div key={t.key} className="lib-item" onClick={() => addCabinet(t)}>
                    {t.label}
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      ) : (
        <div className="library">
          <div className="lib-section">
            <div className="lib-title">Elementy wnętrza → {active?.name}</div>
            <div className="lib-items">
              {ELEMENT_TEMPLATES.map((t) => (
                <div key={t.key} className="lib-item" onClick={() => addElement(t)}>
                  {t.label}
                </div>
              ))}
            </div>
          </div>
          <div className="lib-section">
            <div className="lib-title">Szafki</div>
            <div className="lib-items">
              {cabinets.map((c) => (
                <div
                  key={c.id}
                  className={`lib-item ${c.id === active?.id ? 'sel' : ''}`}
                  onClick={() => enterInterior(c)}
                >
                  {c.name}
                </div>
              ))}
            </div>
          </div>
        </div>
      )}

      {orgFor && active && selElement && (
        <OrganizerPanel
          innerW={innerWidth(active) - 20}
          innerD={innerDepth(active) - 30}
          layout={selElement.organizer ?? makeLayout(innerWidth(active) - 20, innerDepth(active) - 30, 50)}
          onChange={(l) => patchElement(selElement.id, { organizer: l })}
          onClose={() => setOrgFor(null)}
        />
      )}
    </div>
  );
}
