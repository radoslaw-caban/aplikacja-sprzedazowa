import { useEffect, useRef, useState } from 'react';
import { createEngine } from './engine';
import type { PointCloudData, ProductConfig } from './engine/RenderEngine';
import E57Worker from './engine/e57Worker?worker';
import PlyWorker from './engine/plyWorker?worker';
import './App.css';

// Twój realny skan (X9 → CloudCompare → PLY) — demo domyślnie go ładuje
const CLOUD_URL = `${import.meta.env.BASE_URL}dom-chmura.ply`;

const COLORS = ['#c9a227', '#b0bec5', '#8d6e63', '#e53935', '#1e88e5', '#43a047'];
type Mode = 'cloud' | 'model';

export default function App() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const engineRef = useRef<ReturnType<typeof createEngine> | null>(null);
  const [ready, setReady] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [e57Progress, setE57Progress] = useState<{ loaded: number; total: number } | null>(null);
  const [status, setStatus] = useState<string>('');
  const [mode, setMode] = useState<Mode>('cloud');
  const [hasModel, setHasModel] = useState(false);
  const [panelOpen, setPanelOpen] = useState(true);
  const [config, setConfig] = useState<ProductConfig>({
    color: '#8d6e63',
    metalness: 0.3,
    roughness: 0.6,
    autoRotate: false,
    gizmoMode: 'translate',
    showModel: true,
    pointSize: 0.02,
  });

  useEffect(() => {
    const engine = createEngine();
    engineRef.current = engine;
    // uchwyt diagnostyczny — pozwala sprawdzić stan sceny z konsoli przeglądarki
    (window as unknown as { engine?: unknown }).engine = engine;
    const canvas = canvasRef.current!;
    let disposed = false;
    (async () => {
      await engine.init(canvas);
      if (disposed) return;
      engine.applyConfig(config);
      setReady(true);
    })().catch((e) => {
      console.error(e);
      setError(e?.message ?? 'Nieznany błąd');
    });
    return () => {
      disposed = true;
      engine.dispose();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    engineRef.current?.applyConfig(config);
  }, [config]);

  const set = (patch: Partial<ProductConfig>) => setConfig((c) => ({ ...c, ...patch }));

  const importE57 = async (file: File) => {
    setError(null);
    setStatus(`Czytam ${file.name} (${(file.size / 1e9).toFixed(2)} GB)…`);
    try {
      const buffer = await file.arrayBuffer();
      if (file.name.toLowerCase().endsWith('.ply')) return importPlyBuffer(buffer, file.name);
      setStatus('Parsowanie E57 w tle…');
      const worker = new E57Worker();
      worker.onmessage = (e: MessageEvent) => {
        const d = e.data;
        if (d.type === 'meta') {
          setStatus(
            `Skan: ${Number(d.totalPoints).toLocaleString('pl-PL')} pkt` +
              (d.stride > 1 ? ` → pobieram ${Number(d.expected).toLocaleString('pl-PL')} (co ${d.stride}.)` : ''),
          );
        } else if (d.type === 'progress') {
          setE57Progress({ loaded: d.loadedPoints, total: d.totalPoints });
        } else if (d.type === 'error') {
          setError(d.message);
          setE57Progress(null);
          setStatus('');
          worker.terminate();
        } else if (d.type === 'done') {
          const data: PointCloudData = d;
          engineRef.current?.loadPointCloud(data).then(() => {
            setE57Progress(null);
            setStatus(`Chmura: ${data.pointCount.toLocaleString('pl-PL')} pkt`);
            setMode('cloud');
          });
          worker.terminate();
        }
      };
      worker.postMessage({ buffer }, [buffer]);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      setStatus('');
    }
  };

  const importPlyBuffer = (buffer: ArrayBuffer, name: string) => {
    setStatus(`Parsowanie ${name}…`);
    const worker = new PlyWorker();
    worker.onmessage = (e: MessageEvent) => {
      const d = e.data;
      if (d.type === 'error') {
        setError(d.message);
        setStatus('');
      } else if (d.type === 'done') {
        const data: PointCloudData = d;
        engineRef.current?.loadPointCloud(data).then(() => {
          setStatus(`Chmura: ${data.pointCount.toLocaleString('pl-PL')} pkt`);
          setMode('cloud');
        });
      }
      worker.terminate();
    };
    worker.postMessage({ buffer }, [buffer]);
  };

  /** Import modelu GLB/GLTF z dysku (np. eksport z CabinetSense przez SketchUp). */
  const importModel = async (file: File) => {
    setError(null);
    setStatus(`Wczytuję model ${file.name}…`);
    try {
      const url = URL.createObjectURL(file);
      await engineRef.current!.loadModel(url);
      URL.revokeObjectURL(url);
      setHasModel(true);
      setStatus(`Model: ${file.name}`);
      setMode('model');
      // po pierwszym imporcie pokaż gizmo przesuwania
      set({ gizmoMode: 'translate', showModel: true });
    } catch (e) {
      setError(`Model: ${e instanceof Error ? e.message : String(e)}`);
      setStatus('');
    }
  };

  // demo: auto-ładowanie chmury domu po starcie
  useEffect(() => {
    if (!ready) return;
    if (new URLSearchParams(location.search).get('e57') === '1') {
      fetch(`${import.meta.env.BASE_URL}test.e57`)
        .then((r) => { if (!r.ok) throw new Error(`E57 ${r.status}`); return r.blob(); })
        .then((b) => importE57(new File([b], 'test.e57')))
        .catch((e) => setError(`E57 test: ${e.message}`));
      return;
    }
    fetch(CLOUD_URL)
      .then((r) => {
        if (!r.ok) throw new Error(`PLY ${r.status}`);
        return r.arrayBuffer();
      })
      .then((buf) => importPlyBuffer(buf, 'dom-chmura.ply'))
      .catch((e) => console.warn('Auto-load PLY:', e.message));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ready]);

  return (
    <div className="app">
      <header>
        <h1>Konfigurator 3D</h1>
        <div className="header-right">
          <div className="modes">
            <button className={mode === 'cloud' ? 'on' : ''} onClick={() => setMode('cloud')}>
              Chmura
            </button>
            <button
              className={mode === 'model' ? 'on' : ''}
              onClick={() => setMode('model')}
            >
              Model{hasModel ? '' : ' +'}
            </button>
          </div>
          <button className="panel-toggle" onClick={() => setPanelOpen((o) => !o)}>
            {panelOpen ? '▾' : '▸'}
          </button>
        </div>
      </header>

      <div className="stage">
        <canvas ref={canvasRef} />
        {!ready && !error && <div className="loader">Ładowanie…</div>}
        {error && <div className="loader error">⚠️ {error}</div>}
        {e57Progress && (
          <div className="e57-overlay">
            <div>Parsowanie E57: {e57Progress.loaded.toLocaleString('pl-PL')} / {e57Progress.total.toLocaleString('pl-PL')} pkt</div>
            <div className="bar"><div className="fill" style={{ width: `${(e57Progress.loaded / Math.max(1, e57Progress.total)) * 100}%` }} /></div>
          </div>
        )}
        {status && !error && <div className="status">{status}</div>}
        <p className="hint">Przeciągnij palcem / myszą · uszczypnij lub kółkiem, aby przybliżyć</p>
      </div>

      {panelOpen && (
        <div className="panel">
          {mode === 'cloud' && (
            <>
              <label className="row">
                <span>Punkty</span>
                <input
                  type="range" min={0.002} max={0.08} step={0.002}
                  value={config.pointSize}
                  onChange={(e) => set({ pointSize: +e.target.value })}
                />
              </label>
              <label className="import-btn">
                📂 Chmura (.e57 / .ply)
                <input
                  type="file"
                  accept=".e57,.ply"
                  style={{ display: 'none' }}
                  onChange={(e) => {
                    const f = e.target.files?.[0];
                    if (f) importE57(f);
                    e.target.value = '';
                  }}
                />
              </label>
            </>
          )}

          {mode === 'model' && (
            <>
              <div className="row">
                <span>Narzędzie</span>
                <div className="modes">
                  {(['translate', 'rotate', 'scale'] as const).map((m) => (
                    <button
                      key={m}
                      className={config.gizmoMode === m ? 'on' : ''}
                      onClick={() => set({ gizmoMode: m })}
                    >
                      {m === 'translate' ? 'Przesuń' : m === 'rotate' ? 'Obróć' : 'Skaluj'}
                    </button>
                  ))}
                </div>
              </div>

              <div className="row">
                <span>Widoczność</span>
                <button className="toggle" onClick={() => set({ showModel: !config.showModel })}>
                  Model: {config.showModel ? 'WIDOCZNY' : 'UKRYTY'}
                </button>
              </div>

              <div className="row">
                <span>Kolor</span>
                <div className="swatches">
                  {COLORS.map((c) => (
                    <button
                      key={c}
                      aria-label={c}
                      className={`swatch ${config.color === c ? 'active' : ''}`}
                      style={{ background: c }}
                      onClick={() => {
                        const engine = engineRef.current as unknown as { forceColor?: boolean };
                        if (engine) engine.forceColor = true;
                        set({ color: c });
                      }}
                    />
                  ))}
                </div>
              </div>

              <label className="import-btn model">
                📦 Model GLB (.glb / .gltf)
                <input
                  type="file"
                  accept=".glb,.gltf"
                  style={{ display: 'none' }}
                  onChange={(e) => {
                    const f = e.target.files?.[0];
                    if (f) importModel(f);
                    e.target.value = '';
                  }}
                />
              </label>
            </>
          )}
        </div>
      )}
    </div>
  );
}
