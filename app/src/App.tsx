import { useEffect, useRef, useState } from 'react';
import { createEngine } from './engine';
import type { ProductConfig } from './engine/RenderEngine';
import './App.css';

// Model demo (publiczny, darmowy glTF) — docelowo własne modele w assets/models/
const MODEL_URL =
  'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/master/2.0/Duck/glTF-Binary/Duck.glTF';

const COLORS = ['#c9a227', '#b0bec5', '#8d6e63', '#e53935', '#1e88e5', '#43a047'];

export default function App() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const engineRef = useRef<ReturnType<typeof createEngine> | null>(null);
  const [ready, setReady] = useState(false);
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
    })().catch(console.error);
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

  return (
    <div className="app">
      <header>
        <h1>Konfigurator 3D — demo</h1>
        <span className={`badge ${ready ? 'ok' : ''}`}>{ready ? 'silnik: three.js' : 'ładowanie…'}</span>
      </header>

      <div className="stage">
        <canvas ref={canvasRef} />
        {!ready && <div className="loader">Ładowanie modelu…</div>}
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
      </div>
    </div>
  );
}
