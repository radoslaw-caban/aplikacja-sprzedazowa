import { useEffect, useState } from 'react';
import {
  ACTIONS,
  defaultSettings,
  type ClientData,
  type Settings,
} from '../design/settings';
import { ENGINE_OPTIONS } from '../design/units';

interface Props {
  settings: Settings;
  onChange: (s: Settings) => void;
  onClose: () => void;
  onSaveProject: () => void;
  onLoadProject: (file: File) => void;
}

type Section = 'program' | 'camera' | 'keys' | 'client';

/** Ustawienia programu — pełne okno z blurem tła. */
export default function SettingsPanel({ settings, onChange, onClose, onSaveProject, onLoadProject }: Props) {
  const [section, setSection] = useState<Section>('program');
  const [capture, setCapture] = useState<string | null>(null);

  // przechwytywanie nowego skrótu
  useEffect(() => {
    if (!capture) return;
    const onKey = (e: KeyboardEvent) => {
      e.preventDefault();
      e.stopPropagation();
      if (e.key === 'Escape') {
        setCapture(null);
        return;
      }
      if (e.key.length === 1 || e.key === ' ') {
        onChange({ ...settings, shortcuts: { ...settings.shortcuts, [capture]: e.key.toLowerCase() } });
        setCapture(null);
      }
    };
    window.addEventListener('keydown', onKey, true);
    return () => window.removeEventListener('keydown', onKey, true);
  }, [capture, settings, onChange]);

  const setCam = (patch: Partial<Settings['camera']>) =>
    onChange({ ...settings, camera: { ...settings.camera, ...patch } });
  const setClient = (patch: Partial<ClientData>) =>
    onChange({ ...settings, client: { ...settings.client, ...patch } });

  return (
    <div className="settings-overlay" onClick={onClose}>
      <div className="settings-panel" onClick={(e) => e.stopPropagation()}>
        <div className="set-head">
          <strong>Ustawienia</strong>
          <button className="set-close" onClick={onClose}>✕</button>
        </div>

        <div className="set-body">
          <nav className="set-nav">
            {(
              [
                ['program', 'Program'],
                ['camera', 'Kamera i widoki'],
                ['keys', 'Skróty klawiszowe'],
                ['client', 'Dane klienta'],
              ] as [Section, string][]
            ).map(([id, label]) => (
              <button
                key={id}
                className={section === id ? 'on' : ''}
                onClick={() => setSection(id)}
              >
                {label}
              </button>
            ))}
          </nav>

          <div className="set-content">
            {section === 'program' && (
              <>
                <h3>Widok</h3>
                <label className="set-row">
                  <span>Oddalenie kamery</span>
                  <input
                    type="range" min={0.4} max={3} step={0.05}
                    value={settings.camera.distance}
                    onChange={(e) => setCam({ distance: +e.target.value })}
                  />
                  <b>{settings.camera.distance.toFixed(2)}×</b>
                </label>
                <label className="set-row">
                  <span>Pokaż fronty</span>
                  <button
                    className={`set-toggle ${settings.showFronts ? 'on' : ''}`}
                    onClick={() => onChange({ ...settings, showFronts: !settings.showFronts })}
                  >
                    {settings.showFronts ? 'WŁ' : 'WYŁ'}
                  </button>
                </label>
                <label className="set-row">
                  <span>Obrót projektu w tle</span>
                  <button
                    className={`set-toggle ${settings.autoRotate ? 'on' : ''}`}
                    onClick={() => onChange({ ...settings, autoRotate: !settings.autoRotate })}
                  >
                    {settings.autoRotate ? 'WŁ' : 'WYŁ'}
                  </button>
                </label>

                <h3>Projekt</h3>
                <label className="set-row">
                  <span>Jednostka wymiarów</span>
                  <div className="modes">
                    {(['mm', 'cm', 'm'] as const).map((u) => (
                      <button
                        key={u}
                        className={settings.units === u ? 'on' : ''}
                        onClick={() => onChange({ ...settings, units: u })}
                      >
                        {u}
                      </button>
                    ))}
                  </div>
                </label>
                <label className="set-row">
                  <span>Dokładność edycji</span>
                  <input
                    type="range" min={0} max={4} step={1}
                    value={settings.precision}
                    onChange={(e) => onChange({ ...settings, precision: +e.target.value })}
                  />
                  <b>{settings.precision} miejsc</b>
                </label>
                <p className="set-hint">
                  Krok edycji: {settings.precision === 4 ? '0,0001' : settings.precision === 3 ? '0,001' : settings.precision === 2 ? '0,01' : settings.precision === 1 ? '0,1' : '1'} {settings.units}
                </p>

                <h3>Blat (osobny obiekt)</h3>
                <label className="set-row">
                  <span>Widoczny</span>
                  <button
                    className={settings.worktop.enabled ? 'set-toggle on' : 'set-toggle'}
                    onClick={() => onChange({ ...settings, worktop: { ...settings.worktop, enabled: !settings.worktop.enabled } })}
                  >
                    {settings.worktop.enabled ? 'WŁ' : 'WYŁ'}
                  </button>
                </label>
                <label className="set-row">
                  <span>Grubość</span>
                  <input type="range" min={12} max={60} step={1} value={settings.worktop.thickness}
                    onChange={(e) => onChange({ ...settings, worktop: { ...settings.worktop, thickness: +e.target.value } })} />
                  <b>{settings.worktop.thickness} mm</b>
                </label>
                <label className="set-row">
                  <span>Nawis</span>
                  <input type="range" min={0} max={80} step={1} value={settings.worktop.overhang}
                    onChange={(e) => onChange({ ...settings, worktop: { ...settings.worktop, overhang: +e.target.value } })} />
                  <b>{settings.worktop.overhang} mm</b>
                </label>
                <p className="set-hint">Blaty sąsiadujących szafek łączą się automatycznie w jeden odcinek na bieg.</p>

                <h3>Cokół (osobny obiekt)</h3>
                <label className="set-row">
                  <span>Widoczny</span>
                  <button
                    className={settings.plinth.enabled ? 'set-toggle on' : 'set-toggle'}
                    onClick={() => onChange({ ...settings, plinth: { ...settings.plinth, enabled: !settings.plinth.enabled } })}
                  >
                    {settings.plinth.enabled ? 'WŁ' : 'WYŁ'}
                  </button>
                </label>
                <label className="set-row">
                  <span>Wysokość</span>
                  <input type="range" min={60} max={200} step={5} value={settings.plinth.height}
                    onChange={(e) => onChange({ ...settings, plinth: { ...settings.plinth, height: +e.target.value } })} />
                  <b>{settings.plinth.height} mm</b>
                </label>
                <label className="set-row">
                  <span>Położenie</span>
                  <div className="modes">
                    <button className={settings.plinth.mode === 'flush' ? 'on' : ''}
                      onClick={() => onChange({ ...settings, plinth: { ...settings.plinth, mode: 'flush' } })}>
                      Licowany
                    </button>
                    <button className={settings.plinth.mode === 'recessed' ? 'on' : ''}
                      onClick={() => onChange({ ...settings, plinth: { ...settings.plinth, mode: 'recessed' } })}>
                      Cofnięty
                    </button>
                  </div>
                </label>
                <label className="set-row">
                  <span>Cofnięcie</span>
                  <input type="range" min={0} max={120} step={5} value={settings.plinth.setback}
                    disabled={settings.plinth.mode !== 'recessed'}
                    onChange={(e) => onChange({ ...settings, plinth: { ...settings.plinth, setback: +e.target.value } })} />
                  <b>{settings.plinth.setback} mm</b>
                </label>
                <p className="set-hint">Domyślnie cofnięty 40 mm. Cokoły łączą się automatycznie na całym biegu.</p>

                <h3>Okucia</h3>
                <label className="set-row">
                  <span>Poziom detalu</span>
                  <div className="modes">
                    <button className={settings.hardwareDetail !== 'full' ? 'on' : ''}
                      onClick={() => onChange({ ...settings, hardwareDetail: 'basic' })}>
                      Podstawowy
                    </button>
                    <button className={settings.hardwareDetail === 'full' ? 'on' : ''}
                      onClick={() => onChange({ ...settings, hardwareDetail: 'full' })}>
                      Pełny
                    </button>
                  </div>
                </label>
                <p className="set-hint">
                  Podstawowy: uchwyty + prowadnice. Pełny: dodatkowo zawiasy Blum CLIP top,
                  nóżki regulowane, wieszaki ścienne i wsporniki półek (więcej brył = wolniejszy render).
                </p>

                <h3>Silnik graficzny</h3>
                <div className="set-actions">
                  {ENGINE_OPTIONS.map((e) => (
                    <button
                      key={e.id}
                      className={settings.engine === e.id ? 'set-toggle on' : 'set-toggle'}
                      title={e.description}
                      onClick={() => onChange({ ...settings, engine: e.id })}
                    >
                      {e.label}
                    </button>
                  ))}
                </div>
                <p className="set-hint">Przełączanie skrótem: {settings.shortcuts['engine.cycle']?.toUpperCase()}</p>

                <h3>Zapis projektu</h3>
                <div className="set-actions">
                  <button onClick={onSaveProject}>💾 Zapisz projekt</button>
                  <label className="set-file">
                    📂 Wczytaj projekt
                    <input
                      type="file"
                      accept=".json"
                      style={{ display: 'none' }}
                      onChange={(e) => {
                        const f = e.target.files?.[0];
                        if (f) onLoadProject(f);
                        e.target.value = '';
                      }}
                    />
                  </label>
                </div>

                <h3>Reset</h3>
                <button className="set-danger" onClick={() => onChange(defaultSettings())}>
                  Przywróć ustawienia domyślne
                </button>
              </>
            )}

            {section === 'camera' && (
              <>
                <h3>Kamera</h3>
                <label className="set-row">
                  <span>Oddalenie (wszystkie widoki)</span>
                  <input
                    type="range" min={0.4} max={3} step={0.05}
                    value={settings.camera.distance}
                    onChange={(e) => setCam({ distance: +e.target.value })}
                  />
                  <b>{settings.camera.distance.toFixed(2)}×</b>
                </label>
                <label className="set-row">
                  <span>Kąt widzenia (FOV)</span>
                  <input
                    type="range" min={25} max={75} step={1}
                    value={settings.camera.fov}
                    onChange={(e) => setCam({ fov: +e.target.value })}
                  />
                  <b>{settings.camera.fov}°</b>
                </label>
                <label className="set-row">
                  <span>Wysokość patrzenia we wnętrzu</span>
                  <input
                    type="range" min={0.2} max={0.8} step={0.05}
                    value={settings.camera.interiorHeight}
                    onChange={(e) => setCam({ interiorHeight: +e.target.value })}
                  />
                  <b>{Math.round(settings.camera.interiorHeight * 100)}%</b>
                </label>
                <p className="set-hint">
                  Oddalenie działa we wszystkich widokach: układ, wnętrze, przed szafką i do szuflady.
                </p>
              </>
            )}

            {section === 'keys' && (
              <>
                <h3>Skróty klawiszowe</h3>
                <p className="set-hint">Kliknij skrót i naciśnij nowy klawisz. Esc anuluje.</p>
                <div className="keys-list">
                  {ACTIONS.map((a) => (
                    <div className="keys-row" key={a.id}>
                      <span className="keys-label">
                        {a.label}
                        <i className={`keys-mod ${a.module}`}>{a.module}</i>
                      </span>
                      <button
                        className={`keys-key ${capture === a.id ? 'capture' : ''}`}
                        onClick={() => setCapture(a.id)}
                      >
                        {capture === a.id ? '…' : settings.shortcuts[a.id]?.toUpperCase() ?? '—'}
                      </button>
                    </div>
                  ))}
                </div>
              </>
            )}

            {section === 'client' && (
              <>
                <h3>Dane klienta</h3>
                <label className="set-field">
                  <span>Imię i nazwisko / firma</span>
                  <input value={settings.client.name} onChange={(e) => setClient({ name: e.target.value })} />
                </label>
                <label className="set-field">
                  <span>Telefon</span>
                  <input value={settings.client.phone} onChange={(e) => setClient({ phone: e.target.value })} />
                </label>
                <label className="set-field">
                  <span>E-mail</span>
                  <input value={settings.client.email} onChange={(e) => setClient({ email: e.target.value })} />
                </label>
                <label className="set-field">
                  <span>Adres montażu</span>
                  <input value={settings.client.address} onChange={(e) => setClient({ address: e.target.value })} />
                </label>
                <label className="set-field">
                  <span>Notatki</span>
                  <textarea
                    rows={3}
                    value={settings.client.notes}
                    onChange={(e) => setClient({ notes: e.target.value })}
                  />
                </label>
                <p className="set-hint">Dane klienta zapisują się razem z projektem.</p>
              </>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
