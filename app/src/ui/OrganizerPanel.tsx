import { useMemo, useState } from 'react';
import {
  MODULE_SIZES,
  ORGANIZER_KINDS,
  isFree,
  makeLayout,
  place,
  removeItem,
  usage,
  type OrganizerKind,
  type OrganizerLayout,
} from '../design/organizer';

interface Props {
  innerW: number;
  innerD: number;
  layout?: OrganizerLayout;
  onChange: (l: OrganizerLayout) => void;
  onClose: () => void;
}

/**
 * Rzut z góry szuflady: siatka modułów, klik w komórkę = wstawienie
 * wybranego modułu (kwadrat/prostokąt). Klik w istniejący pojemnik = usuń.
 */
export default function OrganizerPanel({ innerW, innerD, layout, onChange, onClose }: Props) {
  const base = useMemo(() => layout ?? makeLayout(innerW, innerD, 50), [layout, innerW, innerD]);
  const [kind, setKind] = useState<OrganizerKind>('cubby');
  const [size, setSize] = useState({ w: 1, h: 1 });
  const [hover, setHover] = useState<{ col: number; row: number } | null>(null);

  const u = usage(base);
  const cw = 100 / base.cols;
  const ch = 100 / base.rows;

  const cellAt = (e: React.MouseEvent<HTMLDivElement>) => {
    const r = e.currentTarget.getBoundingClientRect();
    const col = Math.floor(((e.clientX - r.left) / r.width) * base.cols);
    const row = Math.floor(((e.clientY - r.top) / r.height) * base.rows);
    return { col: Math.max(0, Math.min(base.cols - 1, col)), row: Math.max(0, Math.min(base.rows - 1, row)) };
  };

  return (
    <div className="org-overlay" onClick={onClose}>
      <div className="org-panel" onClick={(e) => e.stopPropagation()}>
        <div className="org-head">
          <div>
            <strong>Pojemniki w szufladzie</strong>
            <div className="org-sub">
              Światło: {innerW} × {innerD} mm · moduł {base.cell} mm · zajęte {u.used}/{u.total}
            </div>
          </div>
          <button className="org-close" onClick={onClose}>✕</button>
        </div>

        <div className="org-body">
          {/* paleta modułów */}
          <div className="org-palette">
            <div className="org-label">Rozmiar modułu</div>
            <div className="org-sizes">
              {MODULE_SIZES.map((m) => (
                <button
                  key={m.label}
                  className={`org-chip ${size.w === m.w && size.h === m.h ? 'on' : ''}`}
                  onClick={() => setSize({ w: m.w, h: m.h })}
                >
                  {m.label}
                </button>
              ))}
            </div>

            <div className="org-label" style={{ marginTop: 10 }}>Typ</div>
            <div className="org-kinds">
              {(Object.keys(ORGANIZER_KINDS) as OrganizerKind[]).map((k) => (
                <button
                  key={k}
                  className={`org-chip ${kind === k ? 'on' : ''}`}
                  onClick={() => setKind(k)}
                >
                  <span className="org-swatch" style={{ background: ORGANIZER_KINDS[k].color }} />
                  {ORGANIZER_KINDS[k].label}
                </button>
              ))}
            </div>

            <button className="org-clear" onClick={() => onChange({ ...base, items: [] })}>
              Wyczyść
            </button>
          </div>

          {/* rzut z góry */}
          <div className="org-topview">
            <div
              className="org-grid"
              onMouseMove={(e) => setHover(cellAt(e))}
              onMouseLeave={() => setHover(null)}
              onClick={(e) => {
                const { col, row } = cellAt(e);
                const hit = base.items.find(
                  (it) => col >= it.col && col < it.col + it.w && row >= it.row && row < it.row + it.h,
                );
                if (hit) {
                  onChange(removeItem(base, hit.id));
                  return;
                }
                onChange(place(base, col, row, size.w, size.h, kind));
              }}
              style={{
                backgroundSize: `${cw}% ${ch}%`,
                aspectRatio: `${base.cols} / ${base.rows}`,
              }}
            >
              {/* podgląd wstawianego modułu */}
              {hover && isFree(base, hover.col, hover.row, size.w, size.h) && (
                <div
                  className="org-ghost"
                  style={{
                    left: `${hover.col * cw}%`,
                    top: `${hover.row * ch}%`,
                    width: `${size.w * cw}%`,
                    height: `${size.h * ch}%`,
                  }}
                />
              )}
              {/* istniejące pojemniki */}
              {base.items.map((it) => (
                <div
                  key={it.id}
                  className="org-item"
                  title={`${ORGANIZER_KINDS[it.kind].label} ${it.w}×${it.h} — kliknij, aby usunąć`}
                  style={{
                    left: `${it.col * cw}%`,
                    top: `${it.row * ch}%`,
                    width: `${it.w * cw}%`,
                    height: `${it.h * ch}%`,
                    background: ORGANIZER_KINDS[it.kind].color + 'cc',
                  }}
                >
                  {it.w}×{it.h}
                </div>
              ))}
            </div>
            <div className="org-legend">
              <span>↑ tył szuflady</span>
              <span>{base.cols} × {base.rows} modułów</span>
              <span>↓ front</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
