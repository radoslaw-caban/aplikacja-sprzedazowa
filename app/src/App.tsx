import { useEffect, useRef, useState } from 'react';
import { createEngine } from './engine';
import type { PointCloudData, ProductConfig } from './engine/RenderEngine';
import E57Worker from './engine/e57Worker?worker';
import './App.css';

// Model demo (publiczny, darmowy glTF) — docelowo własne modele w assets/models/
const MODEL_URL =
  'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/Duck/glTF-Binary/Duck.glb';

const COLORS = ['#c9a227', '#b0bec5', '#8d6e63', '#e53935', '#1e88e5', '#43a047'];

export default function App() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const engineRef = useRef<ReturnType<typeof createEngine> | null>(null);
  const [ready, setReady] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [e57Progress, setE57Progress] = useState<{ loaded: number; total: number } | null>(null);
  const [status, setStatus] = useState<string>('');
  const [config, setConfig] = useState<ProductConfig>({
    color: '#c9a227',
    metalness: 0.7,
    roughness: 0.35,
    autoRotate: true,
  });

  useEffect(() => {
    const engine = createEngine();
    engineRef.current = engine;
    const canvas = canvasRef.current!;
    let disposed = false;
    (async () => {
      await engine.init(canvas);
      if (disposed) return;
      await engine.loadModel(MODEL_URL);
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
      setStatus('Parsowanie E57 w tle…');
      const worker = new E57Worker();
      worker.onmessage = (e: MessageEvent) => {
        const d = e.data;
        if (d.type === 'progress') {
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

  return (
    <div className="app">
      <header>
        <h1>Konfigurator 3D — demo</h1>
        <span className={`badge ${ready ? 'ok' : ''}`}>{ready ? 'silnik: three.js' : 'ładowanie…'}</span>
      </header>

      <div className="stage">
        <canvas ref={canvasRef} />
        {!ready && !error && <div className="loader">Ładowanie modelu…</div>}
        {error && <div className="loader error">⚠️ Błąd ładowania: {error}</div>}
        {e57Progress && (
          <div className="e57-overlay">
            <div>Parsowanie E57: {e57Progress.loaded.toLocaleString('pl-PL')} / {e57Progress.total.toLocaleString('pl-PL')} pkt</div>
            <div className="bar"><div className="fill" style={{ width: `${(e57Progress.loaded / Math.max(1, e57Progress.total)) * 100}%` }} /></div>
          </div>
        )}
        {status && !error && <div className="status">{status}</div>}
        <p className="hint">Przeciągnij palcem / myszą, aby obrócić · uszczypnij, aby przybliżyć</p>
      </div>

      <div className="panel">
        <div className="row">
          <span>Kolor</span>
          <div className="swatches">
            {COLORS.map((c) => (
              <button
                key={c}
                aria-label={c}
                className={`swatch ${config.color === c ? 'active' : ''}`}
                style={{ background: c }}
                onClick={() => set({ color: c })}
              />
            ))}
          </div>
        </div>

        <label className="row">
          <span>Metaliczność</span>
          <input
            type="range" min={0} max={1} step={0.05}
            value={config.metalness}
            onChange={(e) => set({ metalness: +e.target.value })}
          />
        </label>

        <label className="row">
          <span>Chropowatość</span>
          <input
            type="range" min={0} max={1} step={0.05}
            value={config.roughness}
            onChange={(e) => set({ roughness: +e.target.value })}
          />
        </label>

        <button className="toggle" onClick={() => set({ autoRotate: !config.autoRotate })}>
          Autoobrót: {config.autoRotate ? 'WŁ' : 'WYŁ'}
        </button>

        <label className="import-btn">
          📂 Importuj chmurę E57 (.e57)
          <input
            type="file"
            accept=".e57"
            style={{ display: 'none' }}
            onChange={(e) => {
              const f = e.target.files?.[0];
              if (f) importE57(f);
              e.target.value = '';
            }}
          />
        </label>
      </div>
    </div>
  );
}
