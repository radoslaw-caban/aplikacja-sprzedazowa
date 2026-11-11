import type { Room, WallSide } from '../design/room';
import { ZONE_GROUPS, ZONE_SPECS, type ZoneKind } from '../design/zonePlan';
import { wallLabel, wallLength, wallObstacles, type Zone } from '../design/zones';

interface Props {
  room: Room;
  wall: WallSide | null;
  zones: Zone[];
  activeZoneId?: string | null;
  onPick: (kind: ZoneKind) => void;
  onSelect: (id: string) => void;
  onDelete: (id: string) => void;
}

/** Biblioteka stref — widoczna w trybie Strefy, po wybraniu ściany w 3D. */
export default function ZoneLibrary({ room, wall, zones, activeZoneId, onPick, onSelect, onDelete }: Props) {
  const len = wall ? wallLength(room, wall) : 0;
  const obs = wall ? wallObstacles(room, wall) : [];

  return (
    <div className="zl">
      <div className="zl-wall">
        {wall ? (
          <>
            <div className="zl-wall-title">Ściana {wallLabel(wall)}</div>
            <div className="zl-wall-meta">
              {Math.round(len)} mm · wys. {Math.round(room.wallHeight)} mm
              {obs.length > 0 && ` · ${obs.map((o) => (o.kind === 'window' ? 'okno' : 'drzwi')).join(', ')}`}
            </div>
          </>
        ) : (
          <>
            <div className="zl-wall-title">Kliknij ścianę w 3D</div>
            <div className="zl-wall-meta">
              Płaszczyzna ściany staje się ścianą projektową — tu wstawisz strefy mebli.
            </div>
          </>
        )}
      </div>

      {zones.length > 0 && (
        <div className="zl-zones">
          <div className="zl-sec">Strefy w projekcie</div>
          {zones.map((z) => (
            <div key={z.id} className={`zl-zone ${activeZoneId === z.id ? 'on' : ''}`}>
              <button className="zl-zone-main" onClick={() => onSelect(z.id)}>
                <b>{z.name}</b>
                <small>{wallLabel(z.side)} ściana</small>
              </button>
              <button className="zl-zone-del" onClick={() => onDelete(z.id)} title="Usuń strefę i jej szafki">✕</button>
            </div>
          ))}
        </div>
      )}

      {wall && (
        <>
          <div className="zl-sec">Wybierz rodzaj zabudowy</div>
          {ZONE_GROUPS.map((g) => {
            const items = ZONE_SPECS.filter((s) => s.group === g.id);
            if (!items.length) return null;
            return (
              <div key={g.id} className="zl-group">
                <div className="zl-group-title">{g.label}</div>
                {items.map((s) => (
                  <div key={s.kind} className="zl-item">
                    <button className="zl-item-head" onClick={() => onPick(s.kind)}>
                      <span className="zl-icon">{s.icon}</span>
                      <span className="zl-item-label">
                        <b>{s.short}</b>
                        <small>{s.description}</small>
                      </span>
                    </button>
                    <details className="zl-rel">
                      <summary>Zależności</summary>
                      <ul>{s.relations.map((r, i) => <li key={i}>{r}</li>)}</ul>
                    </details>
                  </div>
                ))}
              </div>
            );
          })}
        </>
      )}

      <div className="zl-hint">
        Strefa wstawia gotową propozycję od razu. Kolejne pytania doprecyzowują wymiary,
        urządzenia i pozycje — scena przebudowuje się na bieżąco.
      </div>
    </div>
  );
}
