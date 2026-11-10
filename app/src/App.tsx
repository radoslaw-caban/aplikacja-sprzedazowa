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
import { baseCabinet, makeDoors, type Cabinet, type Cutout, type SceneBox } from './design/types';
import { collidesWithCabinets, elementCollides, findFreeY, collectSnapPoints, nearestSnap, snapToLines } from './design/collision';
import { defaultRoom, roomBoxes, snapToWalls, cornerSnap, type WallSide } from './design/room';
import { GROUP_LABELS } from './design/library';
import { computeRuns, worktopBoxes, plinthBoxes } from './design/runs';
import { exteriorBoxes } from './design/exterior';
import RoomDialog, { type RoomDraft } from './ui/RoomDialog';
import { LIGHT_TEMPLATES, type LightTemplate } from './design/lighting';
import { LIGHTING_PROPOSALS, recommendation } from './design/lightingPlan';
import { styleById, nextStyle, type ViewStyle } from './design/viewStyles';
import { loadProjects, saveProjects, makeProject, activeProjectId, setActiveProjectId, type Project } from './design/projects';
import { parseGlb, type Cluster } from './design/parseGLB';
import { loadFiles, addFile, humanSize, FILE_KINDS, type ClientFile } from './design/files';
import { toCabinet, ROLE_OPTIONS, parseCabinetParts, type ParsedCabinet } from './design/parseModel';
import { HANDLE_SPECS, RUNNER_SPECS } from './design/hardware';
import { stepFromPrecision, toUnit, fromUnit } from './design/units';
import OrganizerPanel from './ui/OrganizerPanel';
import SettingsPanel from './ui/SettingsPanel';
import CabinetThumb from './ui/CabinetThumb';
import CutoutMenu from './ui/CutoutMenu';
import ScanPanel, { type ScanMeta } from './ui/ScanPanel';
import { detectFormat } from './engine/scanFormats';
import type { CloudTransform } from './engine/RenderEngine';
import { makeLayout } from './design/organizer';
import { isTyping, loadSettings, matchesKey, saveSettings, type Settings } from './design/settings';
import { downloadJSON, parseProject, serializeProject } from './design/project';
import './App.css';

const CLOUD_URL = `${import.meta.env.BASE_URL}dom-chmura.ply`;
/** domyślna transformacja skanu (metry, bez obrotu) */
const NO_TRANSFORM: CloudTransform = { scale: 1, rotationY: 0, offset: [0, 0, 0] };
const COLORS = ['#e8e2d8', '#c9a06a', '#b08968', '#2f3437', '#5b6b73', '#8d9b6a'];

type Tab = 'layout' | 'interior' | 'lights';

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
  const [cloudVisible, setCloudVisible] = useState(false);
  const [scanOpen, setScanOpen] = useState(false);
  const [scanFile, setScanFile] = useState<File | null>(null);
  const [scanMeta, setScanMeta] = useState<ScanMeta | null>(null);
  const [cloudTransform, setCloudTransform] = useState<CloudTransform>(NO_TRANSFORM);
  const [cloudDims, setCloudDims] = useState<{ x: number; y: number; z: number } | null>(null);
  const [exterior, setExterior] = useState(true);
  const [roof, setRoof] = useState(false);
  const [wallGhost, setWallGhost] = useState(true);
  const [lights, setLights] = useState<SceneBox[]>([]);
  const [projects, setProjects] = useState<Project[]>([]);
  const [projectId, setProjectId] = useState<string | null>(null);
  const [style, setStyle] = useState<ViewStyle>('realistic');
  const [uiHidden, setUiHidden] = useState(false);
  const hideBars = uiHidden;
  const barStyle = hideBars ? ({ display: 'none' } as const) : undefined;
  const [toast, setToast] = useState<string | null>(null);
  const [lightPanel, setLightPanel] = useState(false);
  const [parsed, setParsed] = useState<ParsedCabinet | null>(null);
  const [parseNote, setParseNote] = useState<string | null>(null);
  const [clusters, setClusters] = useState<Cluster[]>([]);
  const [frozen, setFrozen] = useState(false);
  const [files, setFiles] = useState<ClientFile[]>([]);
  const [fileIdx, setFileIdx] = useState(0);
  const [fileViewer, setFileViewer] = useState(false);
  const [filesOpen, setFilesOpen] = useState(false);
  const [locked, setLocked] = useState(true);

  /** Rozczytuje pojedynczą szafkę wybraną z modelu. */
  const parseCabinetPartsFromCluster = (cl: Cluster): ParsedCabinet =>
    parseCabinetParts(cl.parts, { up: 'y' });

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

  // ---- chmura: ładowana leniwie, dopiero gdy użytkownik włączy ----
  const cloudLoaded = useRef(false);
  useEffect(() => {
    if (!ready || !cloudVisible || cloudLoaded.current) return;
    cloudLoaded.current = true;
    const worker = new PlyWorker();
    worker.onmessage = (e: MessageEvent) => {
      const d = e.data;
      if (d.type === 'done') {
        engineRef.current?.loadPointCloud(d as PointCloudData).then(() => {
          engineRef.current?.setCloudTransform?.(cloudTransform);
          engineRef.current?.setCloudVisible?.(cloudVisible);
          setStatus(`Skan: ${d.pointCount.toLocaleString('pl-PL')} pkt`);
          setCloudDims(dimsOf());
        });
      }
      worker.terminate();
    };
    fetch(CLOUD_URL)
      .then((r) => (r.ok ? r.arrayBuffer() : Promise.reject(new Error(`PLY ${r.status}`))))
      .then((b) => worker.postMessage({ buffer: b }, [b]))
      .catch(() => worker.terminate());
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ready, cloudVisible]);

  /** Wymiary chmury po transformacji (metry → do panelu). */
  const dimsOf = useCallback(() => {
    const b = engineRef.current?.getCloudBounds?.() ?? engineRef.current?.getModelBounds?.();
    if (!b) return null;
    return {
      x: b.max[0] - b.min[0],
      y: b.max[1] - b.min[1],
      z: b.max[2] - b.min[2],
    };
  }, []);

  /** Import skanu z iPada: chmura punktów już sparsowana w workerze. */
  const applyScanCloud = useCallback(
    (cloud: { positions: Float32Array; colors?: Uint8Array; pointCount: number }, meta: ScanMeta, t: CloudTransform) => {
      const engine = engineRef.current;
      if (!engine) return;
      cloudLoaded.current = true; // nie nadpisuj plikiem demo
      engine
        .loadPointCloud(cloud as PointCloudData)
        .then(() => {
          engine.setCloudTransform?.(t);
          engine.setCloudVisible?.(true);
          engine.frameCloud?.();
          setCloudTransform(t);
          setScanMeta(meta);
          setCloudVisible(true);
          setCloudDims(dimsOf());
          setStatus(`${meta.name} · ${meta.pointCount.toLocaleString('pl-PL')} pkt · ${meta.format}`);
        })
        .catch((e) => setError(e instanceof Error ? e.message : String(e)));
    },
    [dimsOf],
  );

  /** Import siatki (GLB/OBJ/STL) — skan z apki, która eksportuje model. */
  const applyScanMesh = useCallback(
    (file: File) => {
      const format = detectFormat(file.name);
      const engine = engineRef.current;
      if (!engine || !format) return;
      // skan z iPada to albo chmura, albo siatka — nie oba naraz
      engine.clearCloud?.();
      cloudLoaded.current = true;
      setCloudVisible(false);
      file
        .arrayBuffer()
        .then((buf) => engine.loadMeshBuffer?.(buf, format, file.name))
        .then(() => {
          setScanMeta({
            name: file.name,
            format,
            pointCount: 0,
            rawCount: 0,
            stride: 1,
            bboxMin: [0, 0, 0],
            bboxMax: [0, 0, 0],
          });
          setCloudDims(dimsOf());
          setStatus(`Siatka: ${file.name}`);
        })
        .catch((e) => setError(e instanceof Error ? e.message : String(e)));
    },
    [dimsOf],
  );

  /** Transformacja skanu → silnik (jednostka, obrót, przesunięcie). */
  useEffect(() => {
    if (!ready) return;
    engineRef.current?.setCloudTransform?.(cloudTransform);
    const t = window.setTimeout(() => setCloudDims(dimsOf()), 60);
    return () => window.clearTimeout(t);
  }, [cloudTransform, ready, engineEpoch, dimsOf]);

  // ---- poziom detalu okuć: zastosuj do wszystkich szafek ----
  useEffect(() => {
    setCabinets((cs) =>
      cs.every((c) => c.detail === settings.hardwareDetail)
        ? cs
        : cs.map((c) => ({ ...c, detail: settings.hardwareDetail })),
    );
  }, [settings.hardwareDetail]);

  // ---- PROJEKTY: wczytanie, zapis, przełączanie gestem ----
  const didInit = useRef(false);
  useEffect(() => {
    if (didInit.current) return;
    didInit.current = true;
    const list = loadProjects();
    if (list.length) {
      const saved = activeProjectId();
      const cur = list.find((p) => p.id === saved) ?? list[0];
      setProjects(list);
      setProjectId(cur.id);
      setActiveProjectId(cur.id);
      setLocked(cur.locked ?? true);
      setCabinets(cur.data.cabinets);
      setLights(cur.data.lights);
      setRoom(cur.data.room);
    } else {
      // brak zapisanych — tworzymy Projekt 1 od razu, żeby pierwszy gest działał
      const p = makeProject('Projekt 1', room, cabinets, lights);
      setProjects([p]);
      setProjectId(p.id);
      setActiveProjectId(p.id);
      saveProjects([p]);
    }
  }, []);

  /** Zapisuje bieżący stan do listy projektów. */
  const snapshot = useCallback(
    (id: string | null) => {
      if (!id) return;
      setProjects((list) =>
        list.map((p) =>
          p.id === id
            ? { ...p, updatedAt: Date.now(), locked, data: { cabinets, lights, room } }
            : p,
        ),
      );
    },
    [cabinets, lights, room, locked],
  );

  useEffect(() => {
    if (!projectId) return;
    const t = setTimeout(() => snapshot(projectId), 600);
    return () => clearTimeout(t);
  }, [projectId, cabinets, lights, room, snapshot]);

  useEffect(() => {
    if (projects.length) saveProjects(projects);
  }, [projects]);

  useEffect(() => {
    if (projectId) setActiveProjectId(projectId);
  }, [projectId]);

  const flash = (msg: string) => {
    setToast(msg);
    window.setTimeout(() => setToast((t) => (t === msg ? null : t)), 1800);
  };

  /** Przełącza projekt (kierunek: +1 w dół, -1 w górę). */
  const switchProject = useCallback(
    (dir: 1 | -1) => {
      if (!projects.length) {
        const p = makeProject('Projekt 1', room, cabinets, lights);
        setProjects([p]);
        setProjectId(p.id);
        flash('Utworzono Projekt 1');
        return;
      }
      const i = projects.findIndex((p) => p.id === projectId);
      const next = (i < 0 ? 0 : i) + dir;
      if (next < 0) {
        // nowy projekt na początku
        const p = makeProject(`Projekt ${projects.length + 1}`, room);
        setProjects((l) => [...l, p]);
        setProjectId(p.id);
        setCabinets([]);
        setLights([]);
        setLocked(true);
        flash(`Nowy: ${p.name}`);
        return;
      }
      if (next >= projects.length) {
        const p = makeProject(`Projekt ${projects.length + 1}`, room);
        setProjects((l) => [...l, p]);
        setProjectId(p.id);
        setCabinets([]);
        setLights([]);
        setLocked(true);
        flash(`Nowy: ${p.name}`);
        return;
      }
      const target = projects[next];
      setProjectId(target.id);
      setLocked(target.locked ?? true);
      setCabinets(target.data.cabinets);
      setLights(target.data.lights);
      setRoom(target.data.room);
      flash(`${target.name}`);
      window.setTimeout(() => engineRef.current?.frameDesign?.(), 250);
    },
    [projects, projectId, room, cabinets, lights],
  );

  /** Przełącza plik klienta (kierunek: +1 w prawo, -1 w lewo). */
  const switchFile = useCallback(
    (dir: 1 | -1) => {
      if (!files.length) {
        flash('Brak plików — dodaj umowę, skan lub rzut');
        return;
      }
      setFileViewer(true);
      setFileIdx((i) => {
        const n = (i + dir + files.length) % files.length;
        flash(files[n].name);
        return n;
      });
    },
    [files],
  );

  /** Przełącza styl widoku. */
  const switchStyle = useCallback(
    (dir: 1 | -1) => {
      setStyle((cur) => {
        const nx = nextStyle(cur, dir);
        flash(styleById(nx).label);
        return nx;
      });
    },
    [],
  );

  // ---- Esc zamyka podgląd pliku ----
  useEffect(() => {
    if (!fileViewer) return;
    const onEsc = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setFileViewer(false);
    };
    window.addEventListener('keydown', onEsc);
    return () => window.removeEventListener('keydown', onEsc);
  }, [fileViewer]);

  // ---- pliki klienta: wczytanie dla aktywnego projektu ----
  useEffect(() => {
    if (!projectId) return;
    setFiles(loadFiles(projectId));
    setFileIdx(0);
  }, [projectId]);

  // ---- zamrożenie obrazu ----
  useEffect(() => {
    engineRef.current?.setFrozen?.(frozen);
    engineRef.current?.setControlsEnabled?.(!frozen && !moveMode);
  }, [frozen, moveMode, ready, engineEpoch]);

  const currentFile = files[fileIdx] ?? null;
  // aktualne akcje dla handlera klawiatury (bez stale closure)
  const actionsRef = useRef<{
    project: (d: 1 | -1) => void;
    file: (d: 1 | -1) => void;
    style: (d: 1 | -1) => void;
  }>({ project: () => {}, file: () => {}, style: () => {} });
  useEffect(() => {
    actionsRef.current = { project: switchProject, file: switchFile, style: switchStyle };
  });

  // ---- styl widoku → silnik ----
  useEffect(() => {
    const spec = styleById(style);
    engineRef.current?.applyStyle?.(spec);
    engineRef.current?.setWallGhost?.(spec.wallGhost);
  }, [style, ready, engineEpoch]);

  // ---- HDRI (realizm) ----
  useEffect(() => {
    if (!ready) return;
    const spec = styleById(style);
    if (spec.materials !== 'pbr') return;
    // HDRI po chwili — nie blokuje pierwszego renderu
    const t = window.setTimeout(() => {
      engineRef.current?.loadHDRI?.(`${import.meta.env.BASE_URL}hdri/sky.hdr`);
    }, 800);
    return () => window.clearTimeout(t);
  }, [ready, style, engineEpoch]);

  // ---- TRYB NAWIGACJI: tylko przy zamrożonym obrazie jeden palec przewija.
  //       Blokada projektu NIE rusza kamery — chroni wyłącznie przed edycją. ----
  const navMode = frozen;

  useEffect(() => {
    engineRef.current?.setControlsEnabled?.(!navMode && !moveMode);
  }, [navMode, moveMode, ready, engineEpoch]);

  useEffect(() => {
    const el = canvasRef.current?.parentElement ?? canvasRef.current;
    if (!el) return;
    let sx = 0;
    let sy = 0;
    let active = false;
    let moved = false;

    const takePoint = (t: Touch) => ({ x: t.clientX, y: t.clientY });

    const down = (e: TouchEvent) => {
      // w trybie nawigacji wystarczy jeden palec; w trybie edycji dwa (jeden obraca scenę)
      if (navMode) {
        if (e.touches.length !== 1) return;
        const p = takePoint(e.touches[0]);
        sx = p.x;
        sy = p.y;
        active = true;
        moved = false;
        return;
      }
      if (e.touches.length !== 2) return;
      active = true;
      sx = (e.touches[0].clientX + e.touches[1].clientX) / 2;
      sy = (e.touches[0].clientY + e.touches[1].clientY) / 2;
    };

    const move = (e: TouchEvent) => {
      if (!active || !navMode || !e.touches.length) return;
      const p = takePoint(e.touches[0]);
      if (Math.hypot(p.x - sx, p.y - sy) > 12) moved = true;
    };

    const up = (e: TouchEvent) => {
      if (!active) return;
      active = false;
      const t = e.changedTouches[0];
      if (!t) return;
      const dx = t.clientX - sx;
      const dy = t.clientY - sy;
      const threshold = navMode ? 45 : 70;
      if (!navMode && !moved && Math.abs(dx) < 12 && Math.abs(dy) < 12) return;
      if (Math.abs(dy) > Math.abs(dx) && Math.abs(dy) > threshold) switchProject(dy > 0 ? -1 : 1);
      else if (Math.abs(dx) > threshold) switchFile(dx > 0 ? -1 : 1);
    };

    el.addEventListener('touchstart', down, { passive: true });
    el.addEventListener('touchmove', move, { passive: true });
    el.addEventListener('touchend', up, { passive: true });
    return () => {
      el.removeEventListener('touchstart', down);
      el.removeEventListener('touchmove', move);
      el.removeEventListener('touchend', up);
    };
  }, [switchProject, switchFile, navMode]);

  // ---- Paski: jedno źródło prawdy. ☰ / H chowa i pokazuje NATYCHMIAST,
  //      bez timerów i bez wracania po dotknięciu ekranu. ----
  // ---- tryb przesuwania: kamera zablokowana, żeby nie uciekała z szafką ----
  useEffect(() => {
    engineRef.current?.setControlsEnabled?.(!moveMode);
    if (!moveMode) {
      dragRef.current = null;
      setCarrying(null);
      engineRef.current?.clearGuides?.();
    }
  }, [moveMode]);

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
      ...lights,
    ];
  }, [cabinets, settings.showFronts, settings.worktop, settings.plinth, exterior, roof, room, lights]);

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
      // W trybie M nie ruszamy przyciskiem: jedno kliknięcie podnosi szafkę,
      // drugie odkłada. Kamera jest wyłączona, więc nie ucieka razem z szafką.
      if (moveMode) e.stopPropagation();
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
        // trzymaj szafkę w obrębie pomieszczenia (nie ucieka poza ściany)
        const halfW = c.rotation === 90 || c.rotation === 270 ? c.depth / 2 : c.width / 2;
        const halfD = c.rotation === 90 || c.rotation === 270 ? c.width / 2 : c.depth / 2;
        const limX = Math.max(0, room.width / 2 - halfW);
        const limZ = Math.max(0, room.depth / 2 - halfD);
        const cx = Math.max(-limX, Math.min(limX, gx - drag.dx));
        const cz = Math.max(-limZ, Math.min(limZ, gz - drag.dz));
        let test: Cabinet = { ...c, x: cx, z: cz };
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
      // w trybie M szafka pozostaje „w ręce" — odkłada ją dopiero klik
      if (moveMode) return;
      dragRef.current = null;
      engineRef.current?.clearGuides?.();
    };

    const onClick = (e: MouseEvent) => {
      if (moveMode) {
        if (!carrying) {
          if (startCarry(e as unknown as PointerEvent)) {
            engineRef.current?.setControlsEnabled?.(false);
            setStatus('Szafka podniesiona — przesuń kursor i kliknij, żeby odłożyć');
          }
        } else {
          dragRef.current = null;
          setCarrying(null);
          engineRef.current?.clearGuides?.();
          engineRef.current?.setControlsEnabled?.(true);
          setStatus('Szafka odłożona');
        }
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
  const guardLocked = () => {
    if (locked) {
      flash('Projekt zablokowany — odblokuj, żeby edytować');
      return false;
    }
    return true;
  };

  const patchCabinet = (id: string, patch: Partial<Cabinet>) =>
    setCabinets((cs) => cs.map((c) => (c.id === id ? { ...c, ...patch } : c)));

  /** Import modelu szafki → rozczytanie części i parametryzacja. */
  const importCabinetModel = async (file: File) => {
    const ext = (file.name.match(/\.[a-z0-9]+$/i)?.[0] ?? '').toLowerCase();
    if (!['.glb', '.gltf'].includes(ext)) {
      setStatus(
        `Format ${ext || 'nieznany'} nie jest obsługiwany przy rozczytywaniu. ` +
          'Wyeksportuj szafkę z SketchUp jako glTF/GLB (Plik → Eksport → glTF) i wczytaj ponownie.',
      );
      return;
    }
    try {
      setStatus('Rozczytuję model…');
      const buf = await file.arrayBuffer();
      const res = await parseGlb(buf);
      setParsed(res.parsed);
      setParseNote(res.unitNote ?? null);
      setClusters(res.clusters);
      setStatus(
        `Rozczytano ${res.parsed.parts.length} brył: ${res.parsed.width}×${res.parsed.height}×${res.parsed.depth} mm`,
      );
    } catch (e) {
      setStatus(`Nie udało się rozczytać: ${e instanceof Error ? e.message : String(e)}`);
    }
  };

  // import modelu z adresu URL: ?cabinetGlb=https://...
  useEffect(() => {
    if (!ready) return;
    const url = new URLSearchParams(window.location.search).get('cabinetGlb');
    if (!url) return;
    (async () => {
      try {
        setStatus('Pobieram model…');
        const res = await fetch(url);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const buf = await res.arrayBuffer();
        const r = await parseGlb(buf);
        setParsed(r.parsed);
        setParseNote(r.unitNote ?? null);
        setClusters(r.clusters);
        setStatus(`Rozczytano ${r.parsed.parts.length} brył`);
      } catch (e) {
        setStatus(`Model z URL: ${e instanceof Error ? e.message : String(e)}`);
      }
    })();
  }, [ready, engineEpoch]);

  /** Zamienia rozczytany model na szafkę w projekcie. */
  const useParsedCabinet = () => {
    if (!parsed) return;
    const cab = toCabinet(parsed, `Model ${cabinets.length + 1}`, `c${Date.now().toString(36)}`);
    const ref = active ?? cabinets[cabinets.length - 1];
    const placed = ref
      ? { ...cab, x: ref.x + (ref.width + cab.width) / 2, z: ref.z, rotation: ref.rotation }
      : cab;
    setCabinets((cs) => [...cs, placed]);
    setSelectedId(placed.id);
    setParsed(null);
    setStatus('Szafka utworzona z modelu — sprawdź wymiary i elementy');
  };

  /** Dodaje oprawę oświetleniową nad zaznaczoną szafką (albo w środku pokoju). */
  const addLight = (t: LightTemplate) => {
    const base = active;
    const x = base?.x ?? 0;
    const z = base?.z ?? 0;
    const w = base?.width ?? 600;
    let y = 2600;
    if (t.group === 'podszafkowe') y = base ? (base.mountHeight ?? 1500) - 20 : 1400;
    if (t.group === 'cokół') y = 40;
    if (t.group === 'wyspa') y = 1500;
    if (t.group === 'ściana') y = base ? 1500 : 1200;
    if (t.group === 'sufit') y = 2600;
    const made = t.make(x, y, z, w).map((b) => ({ ...b, id: `${b.id}-${Math.random().toString(36).slice(2, 6)}` }));
    setLights((ls) => [...ls, ...made]);
    setStatus(`Dodano: ${t.label} (${t.temp})`);
  };

  const addCabinet = (t: CabinetTemplate, side: 'left' | 'right' = 'right') => {
    if (!guardLocked()) return;
    const c = t.make();
    // Punkt odniesienia: zaznaczona szafka, inaczej ostatnia dodana.
    const ref = cabinets.find((x) => x.id === selectedId) ?? cabinets[cabinets.length - 1];

    if (!ref) {
      const wall = snapToWalls(room, c.width, c.depth, c.x, -room.depth / 2 + c.depth / 2);
      const placed: Cabinet = { ...c, x: wall.x, z: wall.z, rotation: wall.rotation, detail: settings.hardwareDetail };
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
      detail: settings.hardwareDetail,
      handle: settings.hardwareDetail === 'full' ? 'bar' : 'bar',
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
      // strzałki: ↑/↓ projekt, ←/→ plik (działa też przy zablokowanym projekcie)
      else if (e.key === 'ArrowUp') { actionsRef.current.project(-1); e.preventDefault(); }
      else if (e.key === 'ArrowDown') { actionsRef.current.project(1); e.preventDefault(); }
      else if (e.key === 'ArrowLeft') { actionsRef.current.file(-1); e.preventDefault(); }
      else if (e.key === 'ArrowRight') { actionsRef.current.file(1); e.preventDefault(); }
      // projekty i style widoku
      else if (e.key === 'PageDown') { actionsRef.current.project(1); e.preventDefault(); }
      else if (e.key === 'PageUp') { actionsRef.current.project(-1); e.preventDefault(); }
      else if (e.key === ']') { actionsRef.current.style(1); e.preventDefault(); }
      else if (e.key === '[') { actionsRef.current.style(-1); e.preventDefault(); }
      else if (e.key.toLowerCase() === 'h') { setUiHidden((v) => !v); e.preventDefault(); }
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
    <div className={`app${uiHidden ? ' ui-hidden' : ''}`}>
      <input
        ref={fileInputRef} type="file" accept=".json" style={{ display: 'none' }}
        onChange={(e) => { const f = e.target.files?.[0]; if (f) loadProject(f); e.target.value = ''; }}
      />

      <button
        className={`ui-handle ${uiHidden ? '' : 'pinned'}`}
        title="Pokaż/ukryj paski narzędzi (H)"
        onClick={() => {
          setUiHidden((v) => !v);
          flash(uiHidden ? 'Paski widoczne' : 'Paski ukryte — ☰ przywraca');
        }}
      >
        {uiHidden ? '☰' : '▣'}
      </button>

      <header style={barStyle}>
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
            className={`chip ${scanMeta ? 'on' : ''}`}
            title="Import skanu z iPada/telefonu — PLY, PCD, XYZ, GLB, OBJ, STL"
            onClick={() => setScanOpen(true)}
          >
            ⇪ Skan
          </button>
          <button
            className={`chip ${settings.autoRotate ? 'on' : ''}`}
            title="Auto-orbitowanie pola roboczego (O)"
            onClick={() => setSettings((s) => ({ ...s, autoRotate: !s.autoRotate }))}
          >
            ⟳ {settings.autoRotate ? 'Orbita WŁ' : 'Orbita WYŁ'}
          </button>
          <button
            className="chip"
            title="Styl widoku — gest poziomy lub klawisz ] (następny) / [ (poprzedni)"
            onClick={() => switchStyle(1)}
          >
            ◐ {styleById(style).label}
          </button>
          <button
            className="chip"
            title="Projekt — gest pionowy lub klawisz PageDown / PageUp"
            onClick={() => switchProject(1)}
          >
            ▤ {projects.find((p) => p.id === projectId)?.name ?? 'Projekt 1'} ({projects.length || 1})
          </button>
          <button
            className={`chip ${frozen ? 'on' : ''}`}
            title="Zamroź obraz — potem przesuwaj w górę/dół (projekty) i w lewo/prawo (pliki)"
            onClick={() => setFrozen((v) => !v)}
          >
            {frozen ? '❄ Zamrożone' : '❄ Zamroź'}
          </button>
          <button
            className={`chip ${locked ? 'on' : ''}`}
            title="Blokada projektu — chroni przed przypadkową edycją"
            onClick={() => {
              setLocked((v) => !v);
              flash(locked ? 'Projekt odblokowany' : 'Projekt zablokowany');
            }}
          >
            {locked ? '🔒 Zablokowany' : '🔓 Otwarty'}
          </button>
          <button className="chip" title="Pliki klienta: umowy, skany, rzuty" onClick={() => setFilesOpen(true)}>
            📎 Pliki ({files.length})
          </button>
          <button className="chip" title="Automat oświetlenia sufitowego" onClick={() => setLightPanel(true)}>
            ✦ Auto-światło
          </button>
          <label className="chip" title="Import modelu szafki (GLB) — automatyczne rozczytanie części">
            ⇩ Model szafki
            <input
              type="file"
              style={{ display: 'none' }}
              onChange={(e) => {
                const f = e.target.files?.[0];
                if (f) void importCabinetModel(f);
                e.currentTarget.value = '';
              }}
            />
          </label>
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
            <button className={tab === 'lights' ? 'on' : ''} onClick={() => setTab('lights')}>Oświetlenie</button>
          </div>
          <span className="badge ok">{status || (ready ? 'gotowe' : 'ładowanie…')}</span>
        </div>
      </header>

      <div className="main">
        {libOpen && (
          <aside className="sidebar" style={barStyle}>
            {tab === 'lights' && (
              <>
                {(['podszafkowe', 'cokół', 'sufit', 'ściana', 'wyspa'] as const).map((grp) => {
                  const items = LIGHT_TEMPLATES.filter((t) => t.group === grp);
                  if (!items.length) return null;
                  return (
                    <div className="sb-group" key={grp}>
                      <div className="sb-title">{grp === 'cokół' ? 'Cokół' : grp}</div>
                      {items.map((t) => (
                        <div key={t.key} className="sb-item" onClick={() => addLight(t)} title={t.hint}>
                          <span className="sb-thumb" style={{ background: t.color }} />
                          <span className="sb-label">{t.label}</span>
                          <span className="sb-tag">{t.temp}</span>
                        </div>
                      ))}
                    </div>
                  );
                })}
              </>
            )}

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
            if (key) {
              const t = LIBRARY_GROUPS.flatMap((g) => byGroup(g)).find((x) => x.key === key);
              if (t) addCabinet(t, 'right');
              return;
            }
            // plik skanu przeciągnięty na scenę — panel dostanie go i wczyta od razu
            const f = e.dataTransfer.files?.[0];
            if (!f) return;
            if (!detectFormat(f.name)) {
              setStatus(`Nieznany plik: ${f.name}`);
              return;
            }
            setScanFile(f);
            setScanOpen(true);
          }}
        >
          <canvas ref={canvasRef} />
          {!ready && !error && <div className="loader">Ładowanie…</div>}
          {error && <div className="loader error">⚠️ {error}</div>}
          <p className="hint" style={barStyle}>
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
            <div className="inspect" style={barStyle}>
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
              <div className="precise">
                <label>Uchwyt</label>
                <select
                  value={active.handle ?? 'bar'}
                  onChange={(e) => patchCabinet(active.id, { handle: e.target.value as never })}
                >
                  {(Object.keys(HANDLE_SPECS) as (keyof typeof HANDLE_SPECS)[]).map((k) => (
                    <option key={k} value={k}>{HANDLE_SPECS[k].label}</option>
                  ))}
                  <option value="none">Bez uchwytu</option>
                </select>
              </div>
              <div className="precise">
                <label>Prowadnice</label>
                <select
                  value={active.runner ?? 'legrabox'}
                  onChange={(e) => patchCabinet(active.id, { runner: e.target.value as never })}
                >
                  {(Object.keys(RUNNER_SPECS) as (keyof typeof RUNNER_SPECS)[]).map((k) => (
                    <option key={k} value={k}>{RUNNER_SPECS[k].label}</option>
                  ))}
                  <option value="none">Bez prowadnic</option>
                </select>
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
            <div className="inspect" style={barStyle}>
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

      {toast && <div className="toast">{toast}</div>}

      {fileViewer && currentFile && (
        <div className="file-viewer">
          <div className="fv-bar">
            <span className="fv-icon">
              {FILE_KINDS.find((k) => k.id === currentFile.kind)?.icon ?? '◇'}
            </span>
            <span className="fv-name">{currentFile.name}</span>
            <span className="fv-meta">
              {FILE_KINDS.find((k) => k.id === currentFile.kind)?.label} · {humanSize(currentFile.size)} ·{' '}
              {fileIdx + 1}/{files.length}
            </span>
            <span className="fv-nav">
              <button onClick={() => switchFile(-1)} title="Poprzedni plik (←)">◀</button>
              <button onClick={() => switchFile(1)} title="Następny plik (→)">▶</button>
              <button onClick={() => setFileViewer(false)} title="Wróć do sceny (Esc)">✕</button>
            </span>
          </div>

          <div className="fv-body">
            {currentFile.dataUrl?.startsWith('data:image') && (
              <img src={currentFile.dataUrl} alt={currentFile.name} />
            )}
            {currentFile.dataUrl?.startsWith('data:application/pdf') && (
              <iframe src={currentFile.dataUrl} title={currentFile.name} />
            )}
            {!currentFile.dataUrl && (
              <div className="fv-empty">
                <div className="fv-big">{FILE_KINDS.find((k) => k.id === currentFile.kind)?.icon ?? '◇'}</div>
                <h3>{currentFile.name}</h3>
                <p>
                  {humanSize(currentFile.size)} · {FILE_KINDS.find((k) => k.id === currentFile.kind)?.label}
                </p>
                <p className="fv-note">
                  Plik jest większy niż 3 MB, więc aplikacja trzyma tylko jego opis
                  (nie kopiuje danych do pamięci przeglądarki).
                </p>
                {currentFile.url && (
                  <a className="primary" href={currentFile.url} target="_blank" rel="noreferrer">
                    Otwórz plik
                  </a>
                )}
              </div>
            )}
          </div>
        </div>
      )}

      {/* Strzałki na ekranie — iPad nie ma klawiatury */}
      <div className="nav-pad" aria-label="Nawigacja projektów i plików">
        <button
          className="nav-pad-up"
          title="Poprzedni projekt (↑)"
          onClick={() => actionsRef.current.project(-1)}
        >▲</button>
        <button
          className="nav-pad-left"
          title="Poprzedni plik (←)"
          onClick={() => actionsRef.current.file(-1)}
        >◀</button>
        <button
          className="nav-pad-right"
          title="Następny plik (→)"
          onClick={() => actionsRef.current.file(1)}
        >▶</button>
        <button
          className="nav-pad-down"
          title="Następny projekt (↓)"
          onClick={() => actionsRef.current.project(1)}
        >▼</button>
        <span className="nav-pad-label">↕ projekt · ↔ plik</span>
      </div>

      {!fileViewer && currentFile && (
        <div className="file-chip" onClick={() => setFilesOpen(true)} title="Aktywny plik — ← / → zmienia">
          <span className="file-chip-icon">
            {FILE_KINDS.find((k) => k.id === currentFile.kind)?.icon ?? '◇'}
          </span>
          <span className="file-chip-body">
            <b>{currentFile.name}</b>
            <small>
              {FILE_KINDS.find((k) => k.id === currentFile.kind)?.label} · {humanSize(currentFile.size)} ·{' '}
              {fileIdx + 1}/{files.length}
            </small>
          </span>
          <span className="file-chip-nav">
            <button
              onClick={(e) => { e.stopPropagation(); switchFile(-1); }}
              title="Poprzedni plik (←)"
            >‹</button>
            <button
              onClick={(e) => { e.stopPropagation(); switchFile(1); }}
              title="Następny plik (→)"
            >›</button>
          </span>
        </div>
      )}

      {frozen && (
        <div className="frozen-badge">
          ❄ obraz zamrożony · ↕ projekt · ↔ plik
        </div>
      )}

      {filesOpen && (
        <div className="modal-backdrop" onClick={() => setFilesOpen(false)}>
          <div className="modal modal-wide glass" onClick={(e) => e.stopPropagation()}>
            <h2>Pliki klienta</h2>
            <p className="modal-sub">
              Umowy, skany pomieszczeń, rzuty, zdjęcia i pomiary. Gest w poziomie przełącza pliki.
            </p>

            <label className="drop-zone">
              + Dodaj plik (PDF, E57, DWG, JPG…)
              <input
                type="file"
                multiple
                style={{ display: 'none' }}
                onChange={async (e) => {
                  const list = e.target.files;
                  if (!list || !projectId) return;
                  for (const f of Array.from(list)) await addFile(projectId, f);
                  const fresh = loadFiles(projectId);
                  setFiles(fresh);
                  setFileIdx(0);
                  flash(`Plik aktywny: ${fresh[0]?.name ?? '—'}`);
                  flash(`Dodano ${list.length} plik(ów)`);
                  e.currentTarget.value = '';
                }}
              />
            </label>

            <div className="file-list">
              {files.length === 0 && <div className="file-empty">Brak plików w tym projekcie</div>}
              {files.map((f, i) => (
                <div
                  key={f.id}
                  className={`file-row ${i === fileIdx ? 'sel' : ''}`}
                  onClick={() => setFileIdx(i)}
                >
                  <span className="file-icon">
                    {FILE_KINDS.find((k) => k.id === f.kind)?.icon ?? '◇'}
                  </span>
                  <span className="file-name">{f.name}</span>
                  <span className="file-kind">{FILE_KINDS.find((k) => k.id === f.kind)?.label}</span>
                  <span className="file-size">{humanSize(f.size)}</span>
                </div>
              ))}
            </div>

            {currentFile?.dataUrl && (
              <div className="file-preview">
                {currentFile.dataUrl.startsWith('data:image') ? (
                  <img src={currentFile.dataUrl} alt={currentFile.name} />
                ) : (
                  <a href={currentFile.dataUrl} download={currentFile.name} target="_blank" rel="noreferrer">
                    Otwórz {currentFile.name}
                  </a>
                )}
              </div>
            )}

            <div className="modal-actions">
              <button className="ghost" onClick={() => setFilesOpen(false)}>Zamknij</button>
            </div>
          </div>
        </div>
      )}

      {parsed && (
        <div className="modal-backdrop" onClick={() => setParsed(null)}>
          <div className="modal modal-wide" onClick={(e) => e.stopPropagation()}>
            <h2>Rozczytany model szafki</h2>
            <p className="modal-sub">
              {parsed.width} × {parsed.height} × {parsed.depth} mm · płyta {parsed.panel} mm ·{' '}
              {parsed.parts.length} brył
              {parseNote ? ` · ${parseNote}` : ''}
            </p>
            {parsed.warnings.length > 0 && (
              <p className="modal-hint" style={{ color: '#e0a33c' }}>
                {parsed.warnings.join(' · ')}
              </p>
            )}
            {clusters.length > 1 && (
              <div className="cluster-bar">
                <span>Model zawiera {clusters.length} szafek — wybierz jedną:</span>
                <div className="cluster-list">
                  {clusters.slice(0, 12).map((cl) => (
                    <button
                      key={cl.id}
                      onClick={() => {
                        const sub = parseCabinetPartsFromCluster(cl);
                        setParsed(sub);
                      }}
                    >
                      {cl.label}
                    </button>
                  ))}
                </div>
              </div>
            )}
            <div className="part-table">
              <div className="part-row part-head">
                <span>Element</span><span>Wymiary [mm]</span><span>Grub.</span><span>Pewność</span>
              </div>
              <div className="part-scroll">
                {parsed.parts.map((pt, i) => (
                  <div className="part-row" key={i}>
                    <span className="part-name">
                      <select
                        value={pt.role}
                        onChange={(e) => {
                          const role = e.target.value as typeof pt.role;
                          setParsed({
                            ...parsed,
                            parts: parsed.parts.map((x, k) => (k === i ? { ...x, role } : x)),
                          });
                        }}
                      >
                        {ROLE_OPTIONS.map((r) => (
                          <option key={r.id} value={r.id}>{r.label}</option>
                        ))}
                      </select>
                      <b>{pt.label}</b>
                    </span>
                    <span>
                      {Math.round(pt.size[0])}×{Math.round(pt.size[1])}×{Math.round(pt.size[2])}
                    </span>
                    <span>{pt.thickness.toFixed(1)}</span>
                    <span className={pt.confidence > 0.8 ? 'ok' : pt.confidence > 0.55 ? 'mid' : 'low'}>
                      {Math.round(pt.confidence * 100)}%
                    </span>
                  </div>
                ))}
              </div>
            </div>
            <div className="modal-actions">
              <button className="ghost" onClick={() => setParsed(null)}>Anuluj</button>
              <button className="primary" onClick={useParsedCabinet}>Utwórz szafkę parametryczną</button>
            </div>
          </div>
        </div>
      )}

      {lightPanel && (
        <div className="modal-backdrop" onClick={() => setLightPanel(false)}>
          <div className="modal modal-wide" onClick={(e) => e.stopPropagation()}>
            <h2>Automat oświetlenia sufitowego</h2>
            <p className="modal-sub">{recommendation(room).note}</p>
            <div className="prop-list">
              {LIGHTING_PROPOSALS.map((pr) => (
                <div key={pr.id} className="prop">
                  <div className="prop-head">
                    <b>{pr.name}</b>
                    <button
                      className="primary"
                      onClick={() => {
                        const made = pr
                          .lights(active?.x ?? 0, room.wallHeight - 30, active?.z ?? 0, active?.width ?? 600)
                          .map((b) => ({ ...b, id: `${b.id}-${Math.random().toString(36).slice(2, 6)}` }));
                        setLights((ls) => [...ls.filter((l) => l.cabinetId !== 'auto'), ...made.map((b) => ({ ...b, cabinetId: 'auto' }))]);
                        setLightPanel(false);
                        flash(`Zastosowano: ${pr.name}`);
                      }}
                    >
                      Zastosuj
                    </button>
                  </div>
                  <div className="prop-desc">{pr.description}</div>
                  <div className="prop-trend">Trend: {pr.trend}</div>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}

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

      {scanOpen && (
        <ScanPanel
          pendingFile={scanFile}
          onPendingConsumed={() => setScanFile(null)}
          meta={scanMeta}
          transform={cloudTransform}
          dims={cloudDims}
          onCloud={applyScanCloud}
          onMesh={applyScanMesh}
          onTransform={setCloudTransform}
          onFrame={() =>
            (scanMeta?.pointCount ? engineRef.current?.frameCloud?.() : engineRef.current?.frameDesign?.())
          }
          onClose={() => setScanOpen(false)}
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
