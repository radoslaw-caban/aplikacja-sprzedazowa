import { useCallback, useEffect, useRef, useState } from 'react';
import { createEngine } from './engine';
import type { PointCloudData } from './engine/RenderEngine';
import PlyWorker from './engine/plyWorker?worker';
import { buildCabinet, innerDepth, innerWidth } from './design/generator';
import {
  ELEMENT_TEMPLATES,
  LIBRARY_GROUPS,
  attachX,
  byGroup,
  summarize,
  type CabinetTemplate,
  type ElementTemplate,
} from './design/library';
import { baseCabinet, makeDoors, type Cabinet, type Cutout } from './design/types';
import { collidesWithCabinets, elementCollides, findFreeY, collectSnapPoints, nearestSnap, snapToLines } from './design/collision';
import { defaultRoom, roomBoxes, snapToWalls, cornerSnap, type WallSide } from './design/room';
import { GROUP_LABELS } from './design/library';
import { computeRuns, worktopBoxes, plinthBoxes } from './design/runs';
import { exteriorBoxes } from './design/exterior';
import RoomDialog, { type RoomDraft } from './ui/RoomDialog';
import { stepFromPrecision, toUnit, fromUnit } from './design/units';
import OrganizerPanel from './ui/OrganizerPanel';
import SettingsPanel from './ui/SettingsPanel';
import CabinetThumb from './ui/CabinetThumb';
import CutoutMenu from './ui/CutoutMenu';
import { makeLayout } from './design/organizer';
import { isTyping, loadSettings, matchesKey, saveSettings, type Settings } from './design/settings';
import { downloadJSON, parseProject, serializeProject } from './design/project';
import './App.css';

const CLOUD_URL = `${import.meta.env.BASE_URL}dom-chmura.ply`;
const COLORS = ['#e8e2d8', '#c9a06a', '#b08968', '#2f3437', '#5b6b73', '#8d9b6a'];

type Tab = 'layout' | 'interior';

export default function App() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const engineRef = useRef<ReturnType<typeof createEngine> | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const dragRef = useRef<{ id: string; dx: number; dz: number } | null>(null);

  const [ready, setReady] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState('');
  const [tab, setTab] = useState<Tab>('layout');
  const [cabinets, setCabinets] = useState<Cabinet[]>(() => [baseCabinet('cab1', -1900, -2200)]);
  const [selectedId, setSelectedId] = useState<string | null>('cab1');
  const [selectedElement, setSelectedElement] = useState<string | null>(null);
  const [selectedCut, setSelectedCut] = useState<string | null>(null);
  const [orgFor, setOrgFor] = useState<string | null>(null);
  const [cutFor, setCutFor] = useState<string | null>(null);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [libOpen, setLibOpen] = useState(true);
  const [settings, setSettings] = useState<Settings>(() => loadSettings());
  const [room, setRoom] = useState(defaultRoom());
  const [roomDialog, setRoomDialog] = useState(false);
  const [moveMode, setMoveMode] = useState(false);
  const [cornerDir, setCornerDir] = useState<WallSide>('south');
  const [carrying, setCarrying] = useState<string | null>(null);
  const [engineEpoch, setEngineEpoch] = useState(0);
  const [cloudVisible, setCloudVisible] = useState(true);
  const [exterior, setExterior] = useState(true);
  const [roof, setRoof] = useState(false);
  const [wallGhost, setWallGhost] = useState(true);

  const active = cabinets.find((c) => c.id === selectedId) ?? undefined;
  const selElement = active?.elements.find((e) => e.id === selectedElement);
  const selCut = active?.cutouts.find((c) => c.id === selectedCut);

  // ---- silnik (restart przy zmianie silnika graficznego) ----
  useEffect(() => {
    setReady(false);
    const engine = createEngine(settings.engine, settings.engine === 'wireframe' ? 'wireframe' : 'pbr');
    engineRef.current = engine;
    (window as unknown as { engine?: unknown }).engine = engine;
    const canvas = canvasRef.current!;
    let disposed = false;
    (async () => {
      await engine.init(canvas);
      if (disposed) return;
      engine.applyConfig({ autoRotate: false });
      engine.renderRoom?.(roomBoxes(room), true);
      setReady(true);
    })().catch((e) => setError(e instanceof Error ? e.message : String(e)));
    return () => {
      disposed = true;
      engine.dispose();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [engineEpoch]);

  // ---- chmura (tło; w pomieszczeniu testowym opcjonalna) ----
  useEffect(() => {
    if (!ready) return;
    const worker = new PlyWorker();
    worker.onmessage = (e: MessageEvent) => {
      const d = e.data;
      if (d.type === 'done') {
        engineRef.current?.loadPointCloud(d as PointCloudData).then(() => {
          setStatus(`Skan: ${d.pointCount.toLocaleString('pl-PL')} pkt`);
        });
      }
      worker.terminate();
    };
    fetch(CLOUD_URL)
      .then((r) => (r.ok ? r.arrayBuffer() : Promise.reject(new Error(`PLY ${r.status}`))))
      .then((b) => worker.postMessage({ buffer: b }, [b]))
      .catch(() => worker.terminate());
  }, [ready]);

  // ---- ustawienia → silnik ----
  useEffect(() => {
    saveSettings(settings);
    engineRef.current?.setViewSettings?.({
      distance: settings.camera.distance,
      fov: settings.camera.fov,
      autoRotate: settings.autoRotate,
      frontsVisible: settings.showFronts,
    });
    engineRef.current?.setCloudVisible?.(cloudVisible);
    engineRef.current?.setWallGhost?.(wallGhost);
  }, [settings, cloudVisible, wallGhost]);

  // ---- render ----
  const boxes = useCallback(() => {
    const cab = cabinets.flatMap((c) => {
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
    });
    // blat i cokół: osobne obiekty łączone w biegi
    const runs = computeRuns(cabinets);
    return [
      ...cab,
      ...worktopBoxes(runs, settings.worktop),
      ...plinthBoxes(runs, settings.plinth),
      ...(exterior ? exteriorBoxes(room, { roof }) : []),
    ];
  }, [cabinets, settings.showFronts, settings.worktop, settings.plinth, exterior, roof, room]);

  // pokój przebudowywany przy zmianie wymiarów / przeznaczenia
  useEffect(() => {
    if (!ready) return;
    engineRef.current?.renderRoom?.(roomBoxes(room), true);
    engineRef.current?.frameDesign?.();
  }, [ready, room, engineEpoch]);

  useEffect(() => {
    if (!ready) return;
    engineRef.current?.renderBoxes?.(boxes());
    engineRef.current?.highlightCabinet?.(selectedId);
    engineRef.current?.setCloudVisible?.(cloudVisible);
    engineRef.current?.setViewSettings?.({
      distance: settings.camera.distance,
      fov: settings.camera.fov,
      autoRotate: settings.autoRotate,
      frontsVisible: settings.showFronts,
    });
  }, [ready, boxes, selectedId, cloudVisible, settings.camera, settings.autoRotate, settings.showFronts, engineEpoch]);

  useEffect(() => {
    if (!ready) return;
    const t = setTimeout(() => engineRef.current?.frameDesign?.(), 400);
    return () => clearTimeout(t);
  }, [ready]);

  // ---- interakcja: klik = zaznacz, dwuklik = wnętrze, M = przesuwanie z chwytem ----
  useEffect(() => {
    if (!ready) return;
    const canvas = canvasRef.current!;
    let down = { x: 0, y: 0, t: 0, moved: false };

    /** Start chwytu: szafka przykleja się DOKŁADNIE w miejscu kliknięcia. */
    const startCarry = (e: PointerEvent) => {
      const hit = engineRef.current?.pickAt?.(e.clientX, e.clientY);
      const floor = engineRef.current?.screenToFloor?.(e.clientX, e.clientY);
      if (!hit?.cabinetId || !floor) return false;
      const c = cabinets.find((x) => x.id === hit.cabinetId);
      if (!c) return false;
      // offset = wektor od środka szafki do punktu kliknięcia.
      // Bez przyciągania do punktów charakterystycznych — inaczej szafka skacze.
      dragRef.current = { id: c.id, dx: floor.x - c.x, dz: floor.z - c.z };
      setSelectedId(c.id);
      setCarrying(c.id);
      return true;
    };

    const onDown = (e: PointerEvent) => {
      down = { x: e.clientX, y: e.clientY, t: Date.now(), moved: false };
      if (!moveMode) return;
      startCarry(e);
      canvas.setPointerCapture?.(e.pointerId);
    };

    const onMove = (e: PointerEvent) => {
      if (Math.hypot(e.clientX - down.x, e.clientY - down.y) > 4) down.moved = true;
      const drag = dragRef.current;
      if (!drag) return;
      const floor = engineRef.current?.screenToFloor?.(e.clientX, e.clientY);
      if (!floor) return;
      setCabinets((cs) => {
        const c = cs.find((x) => x.id === drag.id);
        if (!c) return cs;
        const pts = collectSnapPoints(cs.filter((x) => x.id !== c.id));
        // Punkt chwytu = miejsce pod kursorem; to on się przyciąga, nie środek szafki.
        let gx = floor.x;
        let gz = floor.z;
        const spot = nearestSnap(pts, gx, gz, 140);
        if (spot) {
          gx = spot.x;
          gz = spot.z;
        } else {
          const lines = snapToLines(pts, gx, gz, 60);
          gx = lines.x;
          gz = lines.z;
        }
        let test: Cabinet = { ...c, x: gx - drag.dx, z: gz - drag.dz };
        // ściana: tylko gdy blisko, i tylko dla osi prostopadłej do ściany
        const distToWall = Math.min(
          Math.abs(test.z + room.depth / 2),
          Math.abs(test.z - room.depth / 2),
          Math.abs(test.x + room.width / 2),
          Math.abs(test.x - room.width / 2),
        );
        if (distToWall < 250) {
          const wall = snapToWalls(room, c.width, c.depth, test.x, test.z);
          test = { ...test, x: wall.x, z: wall.z, rotation: wall.rotation };
        }
        if (collidesWithCabinets(cs, test)) return cs;
        return cs.map((x) => (x.id === drag.id ? test : x));
      });
    };

    const onUp = () => {
      dragRef.current = null;
      engineRef.current?.clearGuides?.();
    };

    const onClick = (e: MouseEvent) => {
      if (moveMode) {
        // w trybie M: klik ustawia szafkę w miejscu docelowym
        if (!carrying) startCarry(e as unknown as PointerEvent);
        else setCarrying(null);
        return;
      }
      const hit = engineRef.current?.pickAt?.(e.clientX, e.clientY);
      if (!hit?.cabinetId) {
        setSelectedId(null);
        setSelectedElement(null);
        setSelectedCut(null);
        engineRef.current?.highlightCabinet?.(null);
        return;
      }
      setSelectedId(hit.cabinetId);
      setSelectedElement(hit.elementId ?? null);
      setSelectedCut(null);
    };

    const onDbl = (e: MouseEvent) => {
      const hit = engineRef.current?.pickAt?.(e.clientX, e.clientY);
      const c = cabinets.find((x) => x.id === hit?.cabinetId);
      if (c) enterInterior(c);
    };

    canvas.addEventListener('pointerdown', onDown);
    canvas.addEventListener('pointermove', onMove);
    canvas.addEventListener('pointerup', onUp);
    canvas.addEventListener('click', onClick);
    canvas.addEventListener('dblclick', onDbl);
    return () => {
      canvas.removeEventListener('pointerdown', onDown);
      canvas.removeEventListener('pointermove', onMove);
      canvas.removeEventListener('pointerup', onUp);
      canvas.removeEventListener('click', onClick);
      canvas.removeEventListener('dblclick', onDbl);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ready, moveMode, cabinets, room, carrying]);

  // ---- operacje ----
  const patchCabinet = (id: string, patch: Partial<Cabinet>) =>
    setCabinets((cs) => cs.map((c) => (c.id === id ? { ...c, ...patch } : c)));

  const addCabinet = (t: CabinetTemplate, side: 'left' | 'right' = 'right') => {
    const c = t.make();
    // Punkt odniesienia: zaznaczona szafka, inaczej ostatnia dodana.
    const ref = cabinets.find((x) => x.id === selectedId) ?? cabinets[cabinets.length - 1];

    if (!ref) {
      const wall = snapToWalls(room, c.width, c.depth, c.x, -room.depth / 2 + c.depth / 2);
      const placed: Cabinet = { ...c, x: wall.x, z: wall.z, rotation: wall.rotation };
      setCabinets([placed]);
      setSelectedId(placed.id);
      return;
    }

    // Dokładamy w tym samym rzędzie co szafka odniesienia (bez szczelin).
    const alongZ = ref.rotation === 90 || ref.rotation === 270;
    const sign = side === 'right' ? 1 : -1;
    const offset = (ref.width + c.width) / 2;
    const placed: Cabinet = {
      ...c,
      rotation: ref.rotation,
      x: alongZ ? ref.x : ref.x + sign * offset,
      z: alongZ ? ref.z + sign * offset : ref.z,
    };

    if (collidesWithCabinets(cabinets, placed)) {
      setStatus('Kolizja — brak miejsca');
      return;
    }
    setCabinets((cs) => [...cs, placed]);
    setSelectedId(placed.id);
  };

  /** Dodaje element tylko jeśli nie koliduje z istniejącym. */
  const addElement = (t: ElementTemplate) => {
    if (!active) {
      setStatus('Najpierw zaznacz szafkę');
      return;
    }
    const candidate = {
      id: `e${Math.random().toString(36).slice(2, 8)}`,
      kind: t.kind,
      variant: t.variant,
      y: 0,
      x0: 0,
      x1: 0,
    };
    const y = findFreeY(active, candidate);
    if (y === null || elementCollides(active, { ...candidate, y })) {
      setStatus(`Brak wolnego miejsca na „${t.label}"`);
      return;
    }
    setCabinets((cs) =>
      cs.map((c) => (c.id !== active.id ? c : { ...c, elements: [...c.elements, { ...candidate, y }] })),
    );
    setSelectedElement(candidate.id);
    setStatus(`Dodano: ${t.label}`);
  };

  const patchElement = (elId: string, patch: Record<string, unknown>) => {
    if (!active) return;
    if (patch.y !== undefined) {
      const el = active.elements.find((e) => e.id === elId);
      if (el && elementCollides(active, { ...el, y: patch.y as number }, elId)) {
        setStatus('Kolizja — element już tam jest');
        return;
      }
    }
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
    setSelectedElement(null);
  };

  const addCutout = (cut: Omit<Cutout, 'id'>) => {
    if (!active) return;
    const id = `cu${Math.random().toString(36).slice(2, 7)}`;
    setCabinets((cs) =>
      cs.map((c) => (c.id !== active.id ? c : { ...c, cutouts: [...c.cutouts, { ...cut, id }] })),
    );
    setSelectedCut(id);
    setStatus('Dodano wycięcie');
  };

  const patchCutout = (id: string, patch: Partial<Cutout>) => {
    if (!active) return;
    setCabinets((cs) =>
      cs.map((c) =>
        c.id !== active.id ? c : { ...c, cutouts: c.cutouts.map((k) => (k.id === id ? { ...k, ...patch } : k)) },
      ),
    );
  };

  const enterInterior = (cab: Cabinet, elementY?: number) => {
    setSelectedId(cab.id);
    setTab('interior');
    const opened = { ...cab, fronts: cab.fronts.map((f) => ({ ...f, open: 1 })) };
    patchCabinet(cab.id, { fronts: opened.fronts });
    setTimeout(
      () => engineRef.current?.frameInterior?.(opened, elementY !== undefined ? 'drawer' : 'front', elementY),
      130,
    );
  };

  /** Dociągnięcie do narożnika z wyborem ściany frontu. */
  const snapCorner = () => {
    if (!active) return;
    const s = cornerSnap(room, active.width, active.depth, active.x, active.z, cornerDir);
    const test = { ...active, ...s };
    if (collidesWithCabinets(cabinets, test)) {
      setStatus('Kolizja w narożniku');
      return;
    }
    patchCabinet(active.id, s);
    setStatus('Dociągnięto do narożnika');
  };

  // ---- projekt ----
  const saveProject = () => {
    downloadJSON(
      settings.client.name ? `projekt-${settings.client.name.replace(/\s+/g, '-').toLowerCase()}` : 'projekt',
      serializeProject(cabinets, settings.client),
    );
    setStatus('Projekt zapisany');
  };

  const loadProject = async (file: File) => {
    try {
      const p = parseProject(await file.text());
      setCabinets(p.cabinets);
      setSettings((s) => ({ ...s, client: { ...s.client, ...p.client } }));
      setSelectedId(p.cabinets[0]?.id ?? null);
      setStatus(`Wczytano: ${p.cabinets.length} szafek`);
      setTimeout(() => engineRef.current?.frameDesign?.(), 150);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  // ---- skróty ----
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (isTyping(e) || settingsOpen) return;
      const sc = settings.shortcuts;
      const hit = (id: string) => matchesKey(e, sc[id] ?? '');

      if (hit('tab.layout')) { setTab('layout'); e.preventDefault(); }
      else if (hit('tab.interior')) { if (active) enterInterior(active); e.preventDefault(); }
      else if (hit('fronts.toggle')) { setSettings((s) => ({ ...s, showFronts: !s.showFronts })); e.preventDefault(); }
      else if (hit('fronts.open')) { if (active) patchCabinet(active.id, { fronts: active.fronts.map((f) => ({ ...f, open: 1 })) }); e.preventDefault(); }
      else if (hit('fronts.close')) { if (active) patchCabinet(active.id, { fronts: active.fronts.map((f) => ({ ...f, open: 0 })) }); e.preventDefault(); }
      else if (hit('settings.open')) { setSettingsOpen(true); e.preventDefault(); }
      else if (hit('project.save')) { saveProject(); e.preventDefault(); }
      else if (hit('project.load')) { fileInputRef.current?.click(); e.preventDefault(); }
      else if (hit('view.frame')) { engineRef.current?.frameDesign?.(); e.preventDefault(); }
      else if (hit('view.front')) { if (active) engineRef.current?.frameInterior?.(active, 'front'); e.preventDefault(); }
      else if (hit('view.drawer')) { if (active) engineRef.current?.frameInterior?.(active, 'drawer'); e.preventDefault(); }
      else if (hit('library.toggle')) { setLibOpen((v) => !v); e.preventDefault(); }
      else if (hit('element.delete')) { if (selectedElement) removeElement(selectedElement); e.preventDefault(); }
      else if (hit('cabinet.move')) { setMoveMode((v) => !v); e.preventDefault(); }
      else if (hit('engine.cycle')) {
        setSettings((s) => ({ ...s, engine: s.engine === 'three' ? 'wireframe' : 'three' }));
        setEngineEpoch((x) => x + 1);
        e.preventDefault();
      }
      else if (hit('cloud.toggle')) { setCloudVisible((v) => !v); e.preventDefault(); }
      else if (hit('orbit.toggle')) { setSettings((s) => ({ ...s, autoRotate: !s.autoRotate })); e.preventDefault(); }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [settings, settingsOpen, active, selectedElement, cabinets]);

  const summary = active ? summarize(active) : null;
  const unitStep = stepFromPrecision(settings.units, settings.precision);
  const fmt = (mm: number) => `${toUnit(mm, settings.units).toFixed(settings.precision)}`;
  const unitLabel = settings.units;

  return (
    <div className="app">
      <input
        ref={fileInputRef} type="file" accept=".json" style={{ display: 'none' }}
        onChange={(e) => { const f = e.target.files?.[0]; if (f) loadProject(f); e.target.value = ''; }}
      />

      <header>
        <button className="gear" title="Ustawienia (S)" onClick={() => setSettingsOpen(true)}>⚙</button>
        <h1>Projektant szafek</h1>
        <div className="header-right">
          <button
            className={`chip ${cloudVisible ? 'on' : ''}`}
            title="Chmura punktów (C)"
            onClick={() => setCloudVisible((v) => !v)}
          >
            ☁ {cloudVisible ? 'Chmura WŁ' : 'Chmura WYŁ'}
          </button>
          <button
            className={`chip ${settings.autoRotate ? 'on' : ''}`}
            title="Auto-orbitowanie pola roboczego (O)"
            onClick={() => setSettings((s) => ({ ...s, autoRotate: !s.autoRotate }))}
          >
            ⟳ {settings.autoRotate ? 'Orbita WŁ' : 'Orbita WYŁ'}
          </button>
          <button className="chip" title="Rysuj pomieszczenie" onClick={() => setRoomDialog(true)}>
            ▭ Pomieszczenie
          </button>
          <button
            className={`chip ${exterior ? 'on' : ''}`}
            title="Otoczenie domu (podjazd, kostka, drzewa, dach)"
            onClick={() => setExterior((v) => !v)}
          >
            🏡 Otoczenie {exterior ? 'WŁ' : 'WYŁ'}
          </button>
          <button
            className={`chip ${wallGhost ? 'on' : ''}`}
            title="Ściany półprzezroczyste — widok roboczy wnętrza"
            onClick={() => setWallGhost((v) => !v)}
          >
            ▤ Ściany {wallGhost ? 'duch' : 'pełne'}
          </button>
          <button
            className={`chip ${roof ? 'on' : ''}`}
            title="Dach — domyślnie ukryty, żeby nie zasłaniał wnętrza"
            onClick={() => setRoof((v) => !v)}
          >
            ⌂ Dach {roof ? 'WŁ' : 'WYŁ'}
          </button>
          <button
            className={`chip ${moveMode ? 'on' : ''}`}
            title="Tryb przesuwania (M)"
            onClick={() => setMoveMode((v) => !v)}
          >
            ✥ {moveMode ? 'Przesuwanie WŁ' : 'Przesuwanie'}
          </button>
          <div className="modes">
            <button className={tab === 'layout' ? 'on' : ''} onClick={() => setTab('layout')}>Układ</button>
            <button className={tab === 'interior' ? 'on' : ''} onClick={() => active && enterInterior(active)}>Wnętrze</button>
          </div>
          <span className="badge ok">{status || (ready ? 'gotowe' : 'ładowanie…')}</span>
        </div>
      </header>

      <div className="main">
        {libOpen && (
          <aside className="sidebar">
            {tab === 'layout' ? (
              LIBRARY_GROUPS.map((g) => (
                <div className="sb-group" key={g}>
                  <div className="sb-title">{GROUP_LABELS[g] ?? g}</div>
                  {byGroup(g).map((t) => (
                    <div
                      key={t.key} className="sb-item" draggable
                      onDragStart={(e) => e.dataTransfer.setData('text/cabinet', t.key)}
                      onDragEnd={() => addCabinet(t, 'right')}
                      onClick={() => addCabinet(t, 'right')}
                      title={`${t.label} — klik lub przeciągnij`}
                    >
                      <CabinetThumb t={t} size={46} />
                      <span>{t.label}</span>
                    </div>
                  ))}
                </div>
              ))
            ) : (
              <>
                <div className="sb-group">
                  <div className="sb-title">Elementy → {active?.name ?? '(zaznacz szafkę)'}</div>
                  {ELEMENT_TEMPLATES.map((t) => (
                    <div key={t.key} className="sb-item" onClick={() => addElement(t)}>
                      <span className="sb-glyph">▦</span>
                      <span>{t.label}</span>
                    </div>
                  ))}
                  <div className="sb-item sb-add" onClick={() => active && setCutFor(active.id)}>
                    <span className="sb-glyph">◯</span>
                    <span>Dodaj wycięcie…</span>
                  </div>
                </div>
                <div className="sb-group">
                  <div className="sb-title">Szafki</div>
                  {cabinets.map((c) => (
                    <div key={c.id} className={`sb-item ${c.id === active?.id ? 'sel' : ''}`} onClick={() => enterInterior(c)}>
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
              ? `Klik = zaznacz · dwuklik = wnętrze · M = przesuwanie · D = fronty (${settings.showFronts ? 'wid.' : 'ukryte'})`
              : 'Kliknij element, aby go edytować · wycięcia z panelu po lewej'}
          </p>

          {tab === 'interior' && active && (
            <div className="interior-bar">
              <strong>{active.name}</strong>
              <div className="modes">
                <button onClick={() => engineRef.current?.frameInterior?.(active, 'front')}>Przed szafkę</button>
                <button onClick={() => engineRef.current?.frameInterior?.(active, 'drawer')}>Do szuflady</button>
                <button onClick={() => patchCabinet(active.id, { fronts: active.fronts.map((f) => ({ ...f, open: 0 })) })}>
                  Zamknij fronty
                </button>
              </div>
              {summary && (
                <span className="sum">
                  półki {summary.shelves} · szuflady {summary.drawers} · wycięcia {active.cutouts.length} · płyta{' '}
                  {summary.panelArea.toFixed(2)} m²
                </span>
              )}
            </div>
          )}

          {tab === 'layout' && active && (
            <div className="inspect">
              <div className="inspect-title">{active.name}</div>
              <div className="precise">
                <label>X [{unitLabel}]</label>
                <input
                  type="number" step={unitStep}
                  value={fmt(active.x)}
                  onChange={(e) => {
                    const mm = fromUnit(+e.target.value, settings.units);
                    patchCabinet(active.id, { x: mm });
                  }}
                />
              </div>
              <div className="precise">
                <label>Z [{unitLabel}]</label>
                <input
                  type="number" step={unitStep}
                  value={fmt(active.z)}
                  onChange={(e) => patchCabinet(active.id, { z: fromUnit(+e.target.value, settings.units) })}
                />
              </div>
              <div className="precise">
                <label>Szer. [{unitLabel}]</label>
                <input
                  type="number" step={unitStep}
                  value={fmt(active.width)}
                  onChange={(e) => {
                    const w = fromUnit(+e.target.value, settings.units);
                    patchCabinet(active.id, {
                      width: w,
                      fronts: active.fronts.length ? makeDoors({ ...active, width: w }, active.fronts.length) : [],
                    });
                  }}
                />
              </div>
              <div className="precise">
                <label>Obrót [°]</label>
                <input
                  type="number" step={1} value={active.rotation}
                  onChange={(e) => patchCabinet(active.id, { rotation: +e.target.value })}
                />
              </div>
              <div className="bubble-row">
                <label>Szer.</label>
                <input type="range" min={300} max={1200} step={10} value={active.width}
                  onChange={(e) => {
                    const w = +e.target.value;
                    patchCabinet(active.id, { width: w, fronts: active.fronts.length ? makeDoors({ ...active, width: w }, active.fronts.length) : [] });
                  }} />
                <span className="val">{active.width}</span>
              </div>
              <div className="bubble-row">
                <label>Głęb.</label>
                <input type="range" min={300} max={650} step={10} value={active.depth}
                  onChange={(e) => patchCabinet(active.id, { depth: +e.target.value })} />
                <span className="val">{active.depth}</span>
              </div>
              <div className="bubble-row">
                <label>Fronty</label>
                <input type="range" min={0} max={3} step={1} value={active.fronts.length}
                  onChange={(e) => patchCabinet(active.id, { fronts: makeDoors(active, +e.target.value) })} />
                <span className="val">{active.fronts.length}</span>
              </div>
              <div className="bubble-colors">
                {COLORS.map((col) => (
                  <button key={col} className="dot" style={{ background: col }}
                    onClick={() => patchCabinet(active.id, { color: col })} />
                ))}
              </div>
              <div className="bubble-row2">
                <button onClick={() => setCabinets((cs) => cs.map((x) => (x.id === active.id ? { ...x, x: attachX(cs, x, 'left') } : x)))}>◀ Lewa</button>
                <button onClick={() => setCabinets((cs) => cs.map((x) => (x.id === active.id ? { ...x, x: attachX(cs, x, 'right') } : x)))}>Prawa ▶</button>
              </div>
              <div className="bubble-row">
                <label>Narożnik</label>
                <select className="inspect-sel" value={cornerDir} onChange={(e) => setCornerDir(e.target.value as WallSide)}>
                  <option value="south">front na południe</option>
                  <option value="north">front na północ</option>
                  <option value="west">front na zachód</option>
                  <option value="east">front na wschód</option>
                </select>
              </div>
              <button onClick={snapCorner}>Dociągnij do narożnika</button>
              <button onClick={() => enterInterior(active)}>Wejdź do wnętrza →</button>
              <button className="danger" onClick={() => {
                setCabinets((cs) => cs.filter((c) => c.id !== active.id));
                setSelectedId(null);
              }}>Usuń szafkę</button>
            </div>
          )}

          {tab === 'interior' && active && selElement && (
            <div className="inspect">
              <div className="inspect-title">
                {ELEMENT_TEMPLATES.find((t) => t.kind === selElement.kind)?.label ?? selElement.kind}
              </div>
              <div className="bubble-row2">
                <button onClick={() => patchElement(selElement.id, { y: selElement.y + 32 })}>↑ Wyżej</button>
                <button onClick={() => patchElement(selElement.id, { y: Math.max(0, selElement.y - 32) })}>↓ Niżej</button>
              </div>
              <button onClick={() => patchElement(selElement.id, { holes: !selElement.holes })}>
                {selElement.holes ? 'Usuń otwory' : 'Wiercenie (32 mm)'}
              </button>
              <button onClick={() => setCutFor(active.id)}>◯ Dodaj wycięcie…</button>
              {(selElement.kind === 'drawer' || selElement.kind === 'innerDrawer' || selElement.kind === 'drawerSystem') && (
                <button onClick={() => setOrgFor(selElement.id)}>🧩 Pojemniki…</button>
              )}
              <button onClick={() => engineRef.current?.frameInterior?.(active, 'drawer', selElement.y)}>Kamera do szuflady</button>
              <button className="danger" onClick={() => removeElement(selElement.id)}>Usuń element</button>
            </div>
          )}
        </div>
      </div>

      {roomDialog && (
        <RoomDialog
          initial={{ width: room.width, depth: room.depth, height: room.wallHeight }}
          onCancel={() => setRoomDialog(false)}
          onConfirm={(d: RoomDraft) => {
            setRoom({
              ...room,
              width: d.width,
              depth: d.depth,
              wallHeight: d.height,
              purpose: d.purpose,
              name: d.name,
            } as never);
            setRoomDialog(false);
            setStatus(`Pomieszczenie: ${d.name} · ${(d.width * d.depth / 1e6).toFixed(2)} m² · ${d.purpose}`);
          }}
        />
      )}

      {settingsOpen && (
        <SettingsPanel
          settings={settings} onChange={setSettings} onClose={() => setSettingsOpen(false)}
          onSaveProject={saveProject} onLoadProject={loadProject}
        />
      )}

      {cutFor && active && (
        <CutoutMenu
          onAdd={addCutout}
          onClose={() => setCutFor(null)}
          selected={selCut}
          onUpdate={(patch) => selCut && patchCutout(selCut.id, patch)}
          onDelete={() => {
            if (!selCut) return;
            setCabinets((cs) => cs.map((c) => (c.id !== active.id ? c : { ...c, cutouts: c.cutouts.filter((k) => k.id !== selCut.id) })));
            setSelectedCut(null);
            setCutFor(null);
          }}
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
