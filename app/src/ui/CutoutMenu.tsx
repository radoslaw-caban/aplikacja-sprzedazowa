import { useState } from 'react';
import type { ReactElement } from 'react';
import type { Cutout, CutoutShape } from '../design/types';

interface Props {
  onAdd: (c: Omit<Cutout, 'id'>) => void;
  onClose: () => void;
  selected?: Cutout;
  onUpdate?: (patch: Partial<Cutout>) => void;
  onDelete?: () => void;
}

/** Piktogramy kształtów wycięć. */
const SHAPES: { id: CutoutShape; label: string; svg: ReactElement }[] = [
  {
    id: 'circle',
    label: 'Koło',
    svg: (
      <svg width="40" height="40" viewBox="0 0 40 40">
        <circle cx="20" cy="20" r="12" fill="#1a1d22" stroke="#c9a227" strokeWidth="1.6" />
      </svg>
    ),
  },
  {
    id: 'rect',
    label: 'Prostokąt',
    svg: (
      <svg width="40" height="40" viewBox="0 0 40 40">
        <rect x="8" y="13" width="24" height="14" rx="2" fill="#1a1d22" stroke="#c9a227" strokeWidth="1.6" />
      </svg>
    ),
  },
  {
    id: 'socket1',
    label: 'Gniazdo 1×',
    svg: (
      <svg width="40" height="40" viewBox="0 0 40 40">
        <circle cx="20" cy="20" r="11" fill="#1a1d22" stroke="#c9a227" strokeWidth="1.6" />
        <circle cx="20" cy="20" r="3" fill="#c9a227" />
      </svg>
    ),
  },
  {
    id: 'socket2',
    label: 'Gniazdo 2×',
    svg: (
      <svg width="40" height="40" viewBox="0 0 40 40">
        <rect x="6" y="14" width="28" height="12" rx="6" fill="#1a1d22" stroke="#c9a227" strokeWidth="1.6" />
        <circle cx="15" cy="20" r="2.6" fill="#c9a227" />
        <circle cx="25" cy="20" r="2.6" fill="#c9a227" />
      </svg>
    ),
  },
];

/** Menu dodawania/edycji wycięcia. */
export default function CutoutMenu({ onAdd, onClose, selected, onUpdate, onDelete }: Props) {
  const [shape, setShape] = useState<CutoutShape>(selected?.shape ?? 'circle');
  const isCircle = shape === 'circle' || shape === 'socket1' || shape === 'socket2';

  if (selected && onUpdate) {
    return (
      <div className="cut-menu">
        <div className="cut-title">Wycięcie</div>
        <div className="cut-row">
          <label>X</label>
          <input type="number" value={selected.x} onChange={(e) => onUpdate({ x: +e.target.value })} />
        </div>
        <div className="cut-row">
          <label>Y</label>
          <input type="number" value={selected.y} onChange={(e) => onUpdate({ y: +e.target.value })} />
        </div>
        <div className="cut-row">
          <label>{isCircle ? 'Ø' : 'Szer.'}</label>
          <input type="number" value={selected.w} onChange={(e) => onUpdate({ w: +e.target.value })} />
        </div>
        <div className="cut-row">
          <label>Wys.</label>
          <input type="number" value={selected.h} onChange={(e) => onUpdate({ h: +e.target.value })} />
        </div>
        <div className="cut-row">
          <label>Głęb.</label>
          <input
            type="number" min={0} value={selected.depth}
            onChange={(e) => onUpdate({ depth: +e.target.value, pocket: +e.target.value > 0 })}
          />
        </div>
        <div className="cut-hint">
          {selected.depth > 0 ? `Kieszeń ${selected.depth} mm (np. frez pod LED)` : 'Na wylot'}
        </div>
        <button className="danger" onClick={onDelete}>Usuń wycięcie</button>
        <button onClick={onClose}>Gotowe</button>
      </div>
    );
  }

  return (
    <div className="cut-menu">
      <div className="cut-title">Dodaj wycięcie</div>
      <div className="cut-shapes">
        {SHAPES.map((s) => (
          <button
            key={s.id}
            className={`cut-shape ${shape === s.id ? 'on' : ''}`}
            onClick={() => setShape(s.id)}
            title={s.label}
          >
            {s.svg}
            <span>{s.label}</span>
          </button>
        ))}
      </div>

      <div className="cut-row">
        <label>{isCircle ? 'Ø' : 'Szer.'}</label>
        <input type="number" id="cut-w" defaultValue={isCircle ? 35 : 120} />
      </div>
      {!isCircle && (
        <div className="cut-row">
          <label>Wys.</label>
          <input type="number" id="cut-h" defaultValue={60} />
        </div>
      )}
      <div className="cut-row">
        <label>Głęb.</label>
        <input type="number" id="cut-d" defaultValue={0} min={0} />
      </div>
      <div className="cut-hint">0 = na wylot · &gt;0 = kieszeń</div>

      <button
        className="cut-add"
        onClick={() => {
          const w = Number((document.getElementById('cut-w') as HTMLInputElement)?.value) || 35;
          const h = Number((document.getElementById('cut-h') as HTMLInputElement)?.value) || w;
          const d = Number((document.getElementById('cut-d') as HTMLInputElement)?.value) || 0;
          onAdd({
            shape,
            target: 'front',
            x: 100,
            y: 100,
            z: 0,
            w,
            h: isCircle ? w : h,
            depth: d,
            pocket: d > 0,
          });
          onClose();
        }}
      >
        Wstaw na front
      </button>
      <button onClick={onClose}>Anuluj</button>
    </div>
  );
}
