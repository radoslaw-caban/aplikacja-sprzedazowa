import type { CabinetTemplate } from '../design/library';

/**
 * Miniatura szafki jako SVG — rzut z przodu, proporcje z realnych wymiarów.
 * Rysuje korpus, fronty (z podziałem), blat i cokół. Bez zależności od silnika 3D.
 */
export default function CabinetThumb({ t, size = 54 }: { t: CabinetTemplate; size?: number }) {
  const c = t.make();
  const W = c.width;
  const H = c.height + (c.worktop && c.type !== 'wall' ? 38 : 0);
  const pad = 3;
  const scale = (size - pad * 2) / Math.max(W, H * 0.75);
  const w = W * scale;
  const h = H * scale;
  const x0 = (size - w) / 2;
  const y0 = size - pad - h;

  const plinth = c.type === 'base' ? c.plinth : 0;
  const bodyY = y0 + h - (H - plinth) * scale;
  const bodyH = (H - plinth) * scale;
  const worktopH = c.worktop && c.type !== 'wall' ? 38 * scale : 0;

  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className="thumb">
      {/* cień */}
      <rect x={x0 + 1} y={y0 + 1} width={w} height={h} rx={1} fill="#000" opacity={0.35} />
      {/* blat */}
      {worktopH > 0 && (
        <rect x={x0 - 1} y={bodyY - worktopH} width={w + 2} height={worktopH} fill="#6b6257" />
      )}
      {/* korpus */}
      <rect x={x0} y={bodyY} width={w} height={bodyH} fill="#2a3038" stroke="#4a5563" strokeWidth={0.8} />
      {/* cokół */}
      {plinth > 0 && (
        <rect
          x={x0 + 1.5}
          y={bodyY + bodyH}
          width={w - 3}
          height={plinth * scale}
          fill="#1c2128"
        />
      )}
      {/* fronty */}
      {c.fronts.map((f) => {
        const fx = x0 + (f.x0 / W) * w;
        const fw = ((f.x1 - f.x0) / W) * w;
        const top = bodyY + bodyH - ((f.y1 - plinth) / (H - plinth)) * bodyH;
        const fh2 = ((f.y1 - f.y0) / (H - plinth)) * bodyH;
        return (
          <rect
            key={f.id}
            x={fx + 0.6}
            y={top + 0.6}
            width={Math.max(fw - 1.2, 1)}
            height={Math.max(fh2 - 1.2, 1)}
            fill="#c9a06a"
            stroke="#8a6b45"
            strokeWidth={0.5}
            rx={0.6}
          />
        );
      })}
      {/* liczba frontów gdy brak */}
      {c.fronts.length === 0 && (
        <rect x={x0 + 2} y={bodyY + 2} width={w - 4} height={bodyH - 4} fill="none" stroke="#55606d"
          strokeDasharray="2 2" strokeWidth={0.7} />
      )}
      {/* znacznik szuflad */}
      {c.elements.some((e) => e.kind.startsWith('drawer')) && (
        <line x1={x0 + w * 0.15} y1={y0 + h * 0.5} x2={x0 + w * 0.85} y2={y0 + h * 0.5}
          stroke="#8a6b45" strokeWidth={0.6} opacity={0.6} />
      )}
    </svg>
  );
}
