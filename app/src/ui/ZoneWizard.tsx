import type { Cabinet } from '../design/types';
import type { Room } from '../design/room';
import { activeQuestions, zoneSpec, type ZoneAnswers, type ZoneQuestion } from '../design/zonePlan';
import { planForZone, wallLabel, zoneSummary, type Zone } from '../design/zones';

interface Props {
  zone: Zone;
  room: Room;
  cabinets: Cabinet[];
  step: number;
  onStep: (n: number) => void;
  onAnswer: (patch: ZoneAnswers) => void;
  onFrame: (feature?: string) => void;
  onClose: () => void;
  onDelete: () => void;
  onReset: () => void;
  onPlacement: (on: boolean) => void;
  placement: boolean;
}

/** Kreator strefy: pytanie po pytaniu, natychmiastowa przebudowa i zbliżenie 3D. */
export default function ZoneWizard({
  zone, room, cabinets, step, onStep, onAnswer, onFrame, onClose, onDelete, onReset,
  onPlacement, placement,
}: Props) {
  const spec = zoneSpec(zone.kind);
  const qs = activeQuestions(zone.kind, zone.answers);
  const plan = planForZone(zone, room);
  const sum = zoneSummary(cabinets, zone);
  const q: ZoneQuestion | undefined = qs[Math.min(step, qs.length - 1)];
  const value = q ? zone.answers[q.id] : undefined;

  const isPos = q?.type === 'position';
  const posVal = typeof value === 'number' ? value : 50;

  const next = () => {
    if (step < qs.length - 1) onStep(step + 1);
    else onClose();
  };
  const prev = () => onStep(Math.max(0, step - 1));

  return (
    <div className="zw">
      <div className="zw-head">
        <div>
          <div className="zw-kicker">
            {spec.icon} {wallLabel(zone.side)} ściana · {Math.round(plan.start)}–{Math.round(plan.start + plan.width)} mm
          </div>
          <div className="zw-title">{zone.name}</div>
        </div>
        <button className="zw-x" onClick={onClose} title="Zamknij kreator (strefa zostaje)">✕</button>
      </div>

      <div className="zw-progress">
        <span>Pytanie {Math.min(step + 1, qs.length)} / {qs.length}</span>
        <div className="zw-bar"><i style={{ width: `${((step + 1) / qs.length) * 100}%` }} /></div>
      </div>

      {q && (
        <div className="zw-q">
          <div className="zw-q-label">{q.label}</div>
          {q.help && <div className="zw-help">{q.help}</div>}

          {q.type === 'choice' && (
            <div className="zw-choices">
              {(q.choices ?? []).map((ch) => (
                <button
                  key={String(ch.value)}
                  className={`zw-choice ${value === ch.value ? 'on' : ''}`}
                  onClick={() => onAnswer({ [q.id]: ch.value })}
                  title={ch.hint}
                >
                  <b>{ch.label}</b>
                  {ch.hint && <small>{ch.hint}</small>}
                </button>
              ))}
            </div>
          )}

          {isPos && (
            <>
              <div className="zw-slider">
                <input
                  type="range"
                  min={q.min ?? 0}
                  max={q.max ?? 100}
                  step={q.step ?? 5}
                  value={posVal}
                  onChange={(e) => onAnswer({ [q.id]: Number(e.target.value) })}
                />
                <span className="zw-val">{Math.round(posVal)}{q.unit ?? ''}</span>
              </div>
              <div className="zw-place">
                <button
                  className={placement ? 'on' : ''}
                  onClick={() => onPlacement(!placement)}
                >
                  {placement ? '● Przesuwanie w 3D — kliknij blat' : '✥ Przesuń w 3D (klik / przeciągnij)'}
                </button>
                <span className="zw-place-hint">albo suwakiem powyżej</span>
              </div>
            </>
          )}

          {!isPos && q.feature && (
            <button className="zw-frame" onClick={() => onFrame(q.feature)}>
              ⤢ Zbliż na {q.feature === 'zone' ? 'całą strefę' : q.feature === 'sink' ? 'zlew' : q.feature === 'hob' ? 'płytę' : q.feature === 'oven' ? 'piekarnik' : q.feature === 'fridge' ? 'lodówkę' : q.feature === 'wardrobe' ? 'szafę' : q.feature === 'tv' ? 'TV' : q.feature === 'vitrine' ? 'witryny' : q.feature === 'pantry' ? 'spiżarnię' : q.feature === 'dishwasher' ? 'zmywarkę' : 'element'}
            </button>
          )}
        </div>
      )}

      <div className="zw-nav">
        <button className="ghost" onClick={prev} disabled={step === 0}>← Wstecz</button>
        <button className="primary" onClick={next}>
          {step < qs.length - 1 ? 'Dalej →' : 'Gotowe ✓'}
        </button>
      </div>

      <div className="zw-sum">
        <b>Propozycja na żywo</b>
        <span>
          {sum.base} dolnych · {sum.wall} górnych · {sum.tall} wysokich · {sum.fronts} frontów ·{' '}
          {sum.appliances} urządzeń · {sum.length} mm
        </span>
      </div>

      {plan.warnings.length > 0 && (
        <div className="zw-warn">
          {plan.warnings.map((w, i) => <div key={i}>⚠ {w}</div>)}
        </div>
      )}

      {plan.notes.length > 0 && (
        <div className="zw-notes">
          {plan.notes.map((n, i) => <div key={i}>· {n}</div>)}
        </div>
      )}

      <details className="zw-rel">
        <summary>Zależności tej strefy</summary>
        <ul>{spec.relations.map((r, i) => <li key={i}>{r}</li>)}</ul>
      </details>

      <div className="zw-actions">
        <button onClick={onReset} title="Przywróć propozycję domyślną">↺ Propozycja</button>
        <button className="danger" onClick={onDelete}>Usuń strefę</button>
      </div>
    </div>
  );
}
