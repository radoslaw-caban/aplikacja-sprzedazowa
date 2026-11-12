import { useMemo, useState, type CSSProperties } from 'react';
import CabinetThumb from './CabinetThumb';
import type { CabinetTemplate } from '../design/library';
import { GROUP_LABELS } from '../design/library';
import type { LightTemplate } from '../design/lighting';
import {
  APPLIANCE_ITEMS,
  LIBRARY_CATEGORIES,
  categoryById,
  type LibraryCategoryId,
} from '../design/libraryCategories';

/** Jedna pozycja listy — niezależnie od tego, czy to szafka, oprawa czy AGD. */
interface Item {
  key: string;
  label: string;
  note?: string;
  /** do miniaturki szafki */
  template?: CabinetTemplate;
  /** kolor kropki (np. temperatura światła) */
  swatch?: string;
  tag?: string;
  onPick: () => void;
}

interface Props {
  /** szablony szafek pogrupowane po roli korpusu */
  templatesByGroup: (group: string) => CabinetTemplate[];
  cabinetGroups: readonly string[];
  onPickCabinet: (t: CabinetTemplate) => void;

  lights: LightTemplate[];
  onPickLight: (t: LightTemplate) => void;

  onPickAppliance: (kind: string) => void;

  /** otwiera kreator stref */
  onStartZone: () => void;
  zonesCount: number;

  /** liczba elementów — do licznika w nagłówku kategorii */
  decorCount: number;
  onAddDecor: (key: string) => void;
  decorTemplates: { key: string; label: string }[];
}

/**
 * Biblioteka projektu: kategorie od góry, każda w swoim kolorze.
 *
 * Zasada wizualna: wybrana kategoria to JEDNA wspólna karta z obwódką w jej
 * kolorze; pozostałe są „cofnięte" — bez obwódki, przygaszone, mniejsze.
 * Dzięki temu wiadomo, gdzie się jest, bez czytania nagłówków.
 */
export default function LibraryPanel(props: Props) {
  const [active, setActive] = useState<LibraryCategoryId>('cabinets');
  const cat = categoryById(active);

  const items: Item[] = useMemo(() => {
    if (active === 'cabinets') {
      return props.cabinetGroups.flatMap((g) =>
        props.templatesByGroup(g).map((t) => ({
          key: t.key,
          label: t.label,
          note: GROUP_LABELS[g] ?? g,
          template: t,
          onPick: () => props.onPickCabinet(t),
        })),
      );
    }
    if (active === 'lights') {
      return props.lights.map((t) => ({
        key: t.key,
        label: t.label,
        note: t.hint,
        swatch: t.color,
        tag: t.temp,
        onPick: () => props.onPickLight(t),
      }));
    }
    if (active === 'appliances') {
      return APPLIANCE_ITEMS.map((a) => ({
        key: a.kind,
        label: a.label,
        note: a.note,
        tag: `${a.w}×${a.h}`,
        onPick: () => props.onPickAppliance(a.kind),
      }));
    }
    if (active === 'decor') {
      return props.decorTemplates.map((d) => ({
        key: d.key,
        label: d.label,
        onPick: () => props.onAddDecor(d.key),
      }));
    }
    return [];
  }, [active, props]);

  return (
    <div className="libpanel">
      <div className="libpanel-cats">
        {LIBRARY_CATEGORIES.map((c) => {
          const on = c.id === active;
          return (
            <button
              key={c.id}
              className={`libcat ${on ? 'on' : ''}`}
              style={
                on
                  ? { borderColor: c.tint, background: c.soft, color: '#fff' }
                  : { borderColor: 'transparent' }
              }
              onClick={() => setActive(c.id)}
              title={c.hint}
            >
              <span className="libcat-glyph" style={{ color: on ? c.tint : '#6b7280' }}>
                {c.glyph}
              </span>
              <span className="libcat-label">{c.label}</span>
              {c.id === 'zones' && props.zonesCount > 0 && (
                <span className="libcat-count" style={{ color: c.tint }}>
                  {props.zonesCount}
                </span>
              )}
              {c.id === 'decor' && props.decorCount > 0 && (
                <span className="libcat-count" style={{ color: c.tint }}>
                  {props.decorCount}
                </span>
              )}
            </button>
          );
        })}
      </div>

      {/* wspólna karta wybranej kategorii — jedna obwódka na wszystkie pozycje */}
      <div
        className="libcard"
        style={
          {
            borderColor: cat.tint,
            background: cat.soft,
            '--cat-tint': cat.tint,
          } as CSSProperties
        }
      >
        <div className="libcard-head" style={{ borderColor: cat.tint }}>
          <span style={{ color: cat.tint }}>{cat.glyph}</span>
          <strong>{cat.label}</strong>
        </div>

        {active === 'zones' && (
          <div className="libcard-empty">
            <p>{cat.hint}</p>
            <button
              className="libcard-cta"
              style={{ borderColor: cat.tint, color: cat.tint }}
              onClick={props.onStartZone}
            >
              + Nowa strefa
            </button>
          </div>
        )}

        {active !== 'zones' && (
          <div className="libcard-list">
            {items.map((it) => (
              <button key={it.key} className="libitem" onClick={it.onPick} title={it.note}>
                {it.template ? (
                  <CabinetThumb t={it.template} size={38} />
                ) : it.swatch ? (
                  <span className="libitem-swatch" style={{ background: it.swatch }} />
                ) : (
                  <span className="libitem-glyph" style={{ color: cat.tint }}>
                    •
                  </span>
                )}
                <span className="libitem-body">
                  <span className="libitem-label">{it.label}</span>
                  {it.note && <span className="libitem-note">{it.note}</span>}
                </span>
                {it.tag && <span className="libitem-tag">{it.tag}</span>}
              </button>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
