import { useState } from 'react';

export type RoomPurpose =
  | 'kuchnia'
  | 'salon'
  | 'łazienka'
  | 'sypialnia'
  | 'wiatrołap'
  | 'korytarz'
  | 'garaż'
  | 'spiżarka'
  | 'biuro'
  | 'inne';

export const PURPOSES: { id: RoomPurpose; label: string; hint: string }[] = [
  { id: 'kuchnia', label: 'Kuchnia', hint: 'Blat 900, okap, ciąg roboczy zlew→zmywarka→płyta' },
  { id: 'salon', label: 'Salon', hint: 'Strefa wypoczynku, TV, przejścia min. 900' },
  { id: 'łazienka', label: 'Łazienka', hint: 'Strefy mokre, wentylacja, umywalka 800' },
  { id: 'sypialnia', label: 'Sypialnia', hint: 'Szafa 600 głęb., obejście łóżka 700' },
  { id: 'wiatrołap', label: 'Wiatrołap', hint: 'Szafa na kurtki 350–600, miejsce na buty' },
  { id: 'korytarz', label: 'Korytarz', hint: 'Zabudowa wąska 350, przejście 900' },
  { id: 'garaż', label: 'Garaż', hint: 'Regały, warsztat, dojście techniczne' },
  { id: 'spiżarka', label: 'Spiżarka', hint: 'Półki 300–400, głębokość 600' },
  { id: 'biuro', label: 'Biuro', hint: 'Biurko 600 głęb., gniazda, regały' },
  { id: 'inne', label: 'Inne', hint: 'Brak podpowiedzi' },
];

export interface RoomDraft {
  width: number;
  depth: number;
  height: number;
  purpose: RoomPurpose;
  name: string;
}

interface Props {
  initial?: Partial<RoomDraft>;
  onCancel: () => void;
  onConfirm: (d: RoomDraft) => void;
}

/** Okno rysowania pomieszczenia: prostokąt + wymiary + przeznaczenie. */
export default function RoomDialog({ initial, onCancel, onConfirm }: Props) {
  const [width, setWidth] = useState(initial?.width ?? 4000);
  const [depth, setDepth] = useState(initial?.depth ?? 3500);
  const [height, setHeight] = useState(initial?.height ?? 2600);
  const [purpose, setPurpose] = useState<RoomPurpose>(initial?.purpose ?? 'kuchnia');
  const [name, setName] = useState(initial?.name ?? 'Pomieszczenie 1');

  const hint = PURPOSES.find((p) => p.id === purpose)?.hint ?? '';
  const area = (width * depth) / 1e6;

  return (
    <div className="modal-backdrop" onClick={onCancel}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h2>Rysuj pomieszczenie</h2>
        <p className="modal-sub">Rysujesz prostokąt — podaj wymiary i przeznaczenie.</p>

        <div className="modal-grid">
          <label>
            <span>Szerokość [mm]</span>
            <input type="number" step={10} value={width} onChange={(e) => setWidth(+e.target.value)} />
          </label>
          <label>
            <span>Głębokość [mm]</span>
            <input type="number" step={10} value={depth} onChange={(e) => setDepth(+e.target.value)} />
          </label>
          <label>
            <span>Wysokość [mm]</span>
            <input type="number" step={10} value={height} onChange={(e) => setHeight(+e.target.value)} />
          </label>
          <label>
            <span>Nazwa</span>
            <input value={name} onChange={(e) => setName(e.target.value)} />
          </label>
        </div>

        <div className="modal-section">Przeznaczenie</div>
        <div className="purpose-grid">
          {PURPOSES.map((p) => (
            <button
              key={p.id}
              className={`purpose ${purpose === p.id ? 'on' : ''}`}
              onClick={() => setPurpose(p.id)}
            >
              {p.label}
            </button>
          ))}
        </div>

        <p className="modal-hint">
          <b>{area.toFixed(2)} m²</b> — {hint}
        </p>

        <div className="modal-actions">
          <button className="ghost" onClick={onCancel}>Anuluj</button>
          <button className="primary" onClick={() => onConfirm({ width, depth, height, purpose, name })}>
            Utwórz pomieszczenie
          </button>
        </div>
      </div>
    </div>
  );
}
