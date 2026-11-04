import { useCallback, useEffect, useRef, useState } from 'react';
import { createEngine } from './engine';
import type { PointCloudData } from './engine/RenderEngine';
import PlyWorker from './engine/plyWorker?worker';
import { buildCabinet, innerDepth, innerWidth } from './design/generator';
import {
  ELEMENT_TEMPLATES,
  LIBRARY_GROUPS,
  appendToRowBySide,
  attachX,
  byGroup,
  snapX,
  summarize,
  type CabinetTemplate,
  type ElementTemplate,
} from './design/library';
import { baseCabinet, makeDoors, type Cabinet } from './design/types';
import OrganizerPanel from './ui/OrganizerPanel';
import SettingsPanel from './ui/SettingsPanel';
import CabinetThumb from './ui/CabinetThumb';
import { makeLayout } from './design/organizer';
import { isTyping, loadSettings, matchesKey, saveSettings, type Settings } from './design/settings';
import { downloadJSON, parseProject, serializeProject } from './design/project';
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
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [ready, setReady] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState('');
  const [tab, setTab] = useState<Tab>('layout');
  const [cabinets, setCabinets] = useState<Cabinet[]>(() => [baseCabinet('cab1', 300, 0)]);
  const [selection, setSelection] = useState<Selection | null>(null);
  const [activeId, setActiveId] = useState<string | null>(null);
  const [orgFor, setOrgFor] = useState<string | null>(null);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [libOpen, setLibOpen] = useState(true);
  const [settings, setSettings] = useState<Settings>(() => loadSettings());

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

  // ---- ustawienia → silnik + localStorage ----
  useEffect(() => {
    saveSettings(settings);
    engineRef.current?.setViewSettings?.({
      distance: settings.camera.distance,
      fov: settings.camera.fov,
      autoRotate: settings.autoRotate,
      frontsVisible: settings.showFronts,
    });
  }, [settings]);

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
    [cabinets, settings.showFronts],
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

  /** Dodaje szafkę dociągniętą do wskazanego końca mebla. */
  const addCabinet = (t: CabinetTemplate, side: 'left' | 'right' = 'right') => {
    const c = appendToRowBySide(cabinets, t, side, 0);
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

  // ---- projekt: zapis / odczyt ----
  const saveProject = () => {
    const data = serializeProject(cabinets, settings.client);
    const name = settings.client.name
      ? `projekt-${settings.client.name.replace(/\s+/g, '-').toLowerCase()}`
      : 'projekt';
    downloadJSON(name, data);
    setStatus('Projekt zapisany');
  };

  const loadProject = async (file: File) => {
    try {
      const p = parseProject(await file.text());
      setCabinets(p.cabinets);
      setSettings((s) => ({ ...s, client: { ...s.client, ...p.client } }));
      setActiveId(p.cabinets[0]?.id ?? null);
      setSelection(null);
      setStatus(`Wczytano: ${p.cabinets.length} szafek`);
      setTimeout(() => engineRef.current?.frameDesign?.(), 150);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  // ---- skróty klawiszowe (wszystkie edytowalne w ustawieniach) ----
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (isTyping(e) || settingsOpen) return;
      const sc = settings.shortcuts;
      const hit = (id: string) => matchesKey(e, sc[id] ?? '');

      if (hit('tab.layout')) {
        setTab('layout');
        e.preventDefault();
      } else if (hit('tab.interior')) {
        if (active) enterInterior(active);
        e.preventDefault();
      } else if (hit('fronts.toggle')) {
        setSettings((s) => ({ ...s, showFronts: !s.showFronts }));
        e.preventDefault();
      } else if (hit('fronts.open')) {
        if (active) patchCabinet(active.id, { fronts: active.fronts.map((f) => ({ ...f, open: 1 })) });
        e.preventDefault();
      } else if (hit('fronts.close')) {
        if (active) patchCabinet(active.id, { fronts: active.fronts.map((f) => ({ ...f, open: 0 })) });
        e.preventDefault();
      } else if (hit('settings.open')) {
        setSettingsOpen(true);
        e.preventDefault();
      } else if (hit('project.save')) {
        saveProject();
        e.preventDefault();
      } else if (hit('project.load')) {
        fileInputRef.current?.click();
        e.preventDefault();
      } else if (hit('view.frame')) {
        engineRef.current?.frameDesign?.();
        e.preventDefault();
      } else if (hit('view.front')) {
        if (active) engineRef.current?.frameInterior?.(active, 'front');
        e.preventDefault();
      } else if (hit('view.drawer')) {
        if (active) engineRef.current?.frameInterior?.(active, 'drawer');
        e.preventDefault();
      } else if (hit('library.toggle')) {
        setLibOpen((v) => !v);
        e.preventDefault();
      } else if (hit('element.delete')) {
        if (selection?.elementId) removeElement(selection.elementId);
        e.preventDefault();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [settings, settingsOpen, active, selection, cabinets]);

  const selElement = active?.elements.find((e) => e.id === selection?.elementId);
  const selFront = active?.fronts.find((f) => f.id === selection?.frontId);
  const summary = active ? summarize(active) : null;

  return (
    <div className="app">
      <input
        ref={fileInputRef}
        type="file"
        accept=".json"
        style={{ display: 'none' }}
        onChange={(e) => {
          const f = e.target.files?.[0];
          if (f) loadProject(f);
          e.target.value = '';
        }}
      />

      <header>
        <button className="gear" title="Ustawienia (S)" onClick={() => setSettingsOpen(true)}>
          ⚙
        </button>
        <h1>Projektant szafek</h1>
        <div className="header-right">
          <div className="modes">
            <button className={tab === 'layout' ? 'on' : ''} onClick={() => setTab('layout')}>
              Układ
            </button>
            <button className={tab === 'interior' ? 'on' : ''} onClick={() => active && enterInterior(active)}>
              Wnętrze
            </button>
          </div>
          <span className="badge ok">{status || (ready ? 'gotowe' : 'ładowanie…')}</span>
        </div>
      </header>

      <div className="main">
        {libOpen && (
          <aside className="sidebar">
            {tab === 'layout'
              ? LIBRARY_GROUPS.map((g) => (
                  <div className="sb-group" key={g}>
                    <div className="sb-title">{g}</div>
                    {byGroup(g).map((t) => (
                      <div
                        key={t.key}
                        className="sb-item"
                        draggable
                        onDragStart={(e) => e.dataTransfer.setData('text/cabinet', t.key)}
                        onDragEnd={() => addCabinet(t, 'right')}
                        onClick={() => addCabinet(t, 'right')}
                        title={`${t.label} — klik lub przeciągnij na pole robocze`}
                      >
                        <CabinetThumb t={t} size={46} />
                        <span>{t.label}</span>
                      </div>
                    ))}
                  </div>
                ))
              : (
                <>
                  <div className="sb-group">
                    <div className="sb-title">Elementy → {active?.name}</div>
                    {ELEMENT_TEMPLATES.map((t) => (
                      <div key={t.key} className="sb-item" onClick={() => addElement(t)}>
                        <span className="sb-glyph">▦</span>
                        <span>{t.label}</span>
                      </div>
                    ))}
                  </div>
                  <div className="sb-group">
                    <div className="sb-title">Szafki</div>
                    {cabinets.map((c) => (
                      <div
                        key={c.id}
                        className={`sb-item ${c.id === active?.id ? 'sel' : ''}`}
                        onClick={() => enterInterior(c)}
                      >
                        <span className="sb-glyph">▮</span>
                        <span>{c.name}</span>
                      </div>
                    ))}
                  </div>
                </>
              )}
          </aside>
        )}

        <div
          className="stage"
          onDragOver={(e) => e.preventDefault()}
          onDrop={(e) => {
            e.preventDefault();
            const key = e.dataTransfer.getData('text/cabinet');
            if (!key) return;
            const t = LIBRARY_GROUPS.flatMap((g) => byGroup(g)).find((x) => x.key === key);
            if (t) addCabinet(t, 'right');
          }}
        >
          <canvas ref={canvasRef} />
          {!ready && !error && <div className="loader">Ładowanie…</div>}
          {error && <div className="loader error">⚠️ {error}</div>}
          <p className="hint">
            {tab === 'layout'
              ? `Układ · D: fronty ${settings.showFronts ? 'widoczne' : 'ukryte'} · S: ustawienia`
              : 'Wnętrze · kliknij element, aby go edytować'}
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
                        patchCabinet(active.id, {
                          width: w,
                          fronts: active.fronts.length ? makeDoors({ ...active, width: w }, active.fronts.length) : [],
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
                  <div className="bubble-row2">
                    <button
                      onClick={() =>
                        setCabinets((cs) => {
                          const c = cs.find((x) => x.id === active.id);
                          if (!c) return cs;
                          return cs.map((x) => (x.id === c.id ? { ...x, x: attachX(cs, c, 'left') } : x));
                        })
                      }
                    >
                      ◀ Do lewej
                    </button>
                    <button
                      onClick={() =>
                        setCabinets((cs) => {
                          const c = cs.find((x) => x.id === active.id);
                          if (!c) return cs;
                          return cs.map((x) => (x.id === c.id ? { ...x, x: attachX(cs, c, 'right') } : x));
                        })
                      }
                    >
                      Do prawej ▶
                    </button>
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
      </div>

      {settingsOpen && (
        <SettingsPanel
          settings={settings}
          onChange={setSettings}
          onClose={() => setSettingsOpen(false)}
          onSaveProject={saveProject}
          onLoadProject={loadProject}
        />
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

      {!libOpen && <button className="lib-open" onClick={() => setLibOpen(true)}>Biblioteka ▴</button>}
    </div>
  );
}
