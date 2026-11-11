/**
 * Testy reguł stref zabudowy (czysty planner) — Node 22+ (type stripping).
 * Sprawdzają wymiary, kolejność i zależności, nie wygląd sceny.
 */
import { planZone, zoneDefaults, activeQuestions, ZONE_SPECS, type ZoneContext } from '../src/design/zonePlan.ts';

declare const process: { exit(code: number): never };

let fails = 0;
const check = (name: string, cond: boolean, extra = '') => {
  console.log(`${cond ? 'OK  ' : 'FAIL'} ${name}${extra ? ' — ' + extra : ''}`);
  if (!cond) fails++;
};

const ctx = (over: Partial<ZoneContext> = {}): ZoneContext => {
  const wallLength = over.wallLength ?? 5000;
  const usableFrom = over.usableFrom ?? 0;
  return {
    wallLength,
    usableFrom,
    usableLength: over.usableLength ?? wallLength - usableFrom,
    wallHeight: 2600,
    roomDepth: 4000,
    roomWidth: 5000,
    obstacles: [],
    worktopThickness: 38,
    ...over,
  };
};

const rows = (parts: { type: string; at: number; width: number }[], type: string) =>
  parts.filter((p) => p.type === type).sort((a, b) => a.at - b.at);

/** Ciągłość rzędu: brak dziur i nakładek. */
const contiguous = (parts: { at: number; width: number }[]) => {
  for (let i = 1; i < parts.length; i++) {
    const prev = parts[i - 1];
    if (Math.abs(parts[i].at - (prev.at + prev.width)) > 0.6) return false;
  }
  return true;
};

// ---------------------------------------------------------------------------
// 1. Wszystkie strefy: dodatnie wymiary, brak nakładek w rzędzie
// ---------------------------------------------------------------------------
for (const spec of ZONE_SPECS) {
  const plan = planZone(spec.kind, zoneDefaults(spec.kind), ctx());
  check(`${spec.kind}: plan niepusty`, plan.parts.length > 0, `${plan.parts.length} części`);
  check(
    `${spec.kind}: dodatnie szerokości`,
    plan.parts.every((p) => p.width > 100 && p.height > 100 && p.depth > 100),
  );
  const base = rows(plan.parts, 'base');
  check(`${spec.kind}: ciąg dolny bez dziur`, contiguous(base), `${base.length} modułów`);
  check(
    `${spec.kind}: części w granicach strefy`,
    plan.parts.every((p) => p.at >= -0.5 && p.at + p.width <= plan.width + 0.5),
  );
}

// ---------------------------------------------------------------------------
// 2. Gotowanie: cokół z wysokości blatu, płyta, piekarnik, lodówka, okap
// ---------------------------------------------------------------------------
{
  const a = { ...zoneDefaults('kitchen-cook'), worktopHeight: 900 };
  const plan = planZone('kitchen-cook', a, ctx());
  const hob = plan.parts.find((p) => p.role === 'hob');
  check('gotowanie: szafka pod płytą 600', !!hob && hob.width === 600);
  check('gotowanie: cokół 900 − 38 − 720 = 142', hob?.plinth === 142, String(hob?.plinth));
  const oven = plan.parts.find((p) => p.role === 'oven');
  check('gotowanie: słupek piekarnika 600', oven?.width === 600 && oven.type === 'tall');
  check('gotowanie: piekarnik + mikrofala', !!oven && oven.appliances.includes('oven') && oven.appliances.includes('microwave'));
  const fridge = plan.parts.find((p) => p.role === 'fridge');
  check('gotowanie: lodówka do zabudowy 600', fridge?.width === 600);
  const vitrines = plan.parts.filter((p) => p.role.startsWith('witryna'));
  check('gotowanie: witryny na obu końcach', vitrines.length === 2);
  const wall = plan.parts.filter((p) => p.type === 'wall');
  check('gotowanie: szafki górne 1500 mm (blat 900 + 600)', wall.length > 0 && wall.every((w) => w.mountHeight === 1500));
  check('gotowanie: okap na szafce płyty', !!hob && hob.appliances.includes('hood'));
  check('gotowanie: zmywarka 600', plan.parts.some((p) => p.role === 'dishwasher' && p.width === 600));

  // szersza płyta
  const wide = planZone('kitchen-cook', { ...a, hob: 'induction-800' }, ctx());
  check('gotowanie: indukcja 800', wide.parts.find((p) => p.role === 'hob')?.width === 800);

  // przesunięcie płyty w lewo
  const left = planZone('kitchen-cook', { ...a, hobPos: 10 }, ctx());
  const l1 = left.parts.find((p) => p.role === 'hob')!;
  const r1 = plan.parts.find((p) => p.role === 'hob')!;
  check('gotowanie: przesuwanie płyty zmienia strefę pracy', l1.at < r1.at, `${l1.at} < ${r1.at}`);
}

// ---------------------------------------------------------------------------
// 3. Czystość: zlew, zmywarka obok, kosz, okno usuwa szafkę górną
// ---------------------------------------------------------------------------
{
  const a = zoneDefaults('kitchen-clean');
  const plan = planZone('kitchen-clean', a, ctx());
  const sink = plan.parts.find((p) => p.role === 'sink');
  check('czystość: zlew 1,5-komorowy 800', sink?.width === 800);
  check('czystość: kosz pod zlewem', !!sink && sink.appliances.includes('bin'));
  const dw = plan.parts.find((p) => p.role === 'dishwasher');
  check('czystość: zmywarka 600', dw?.width === 600);
  check('czystość: zmywarka przy zlewie', !!dw && !!sink && Math.abs(dw.at - (sink.at + sink.width)) < 1);

  const moved = planZone('kitchen-clean', { ...a, sinkPos: 90 }, ctx());
  const sink0 = plan.parts.find((p) => p.role === 'sink')!;
  const sink1 = moved.parts.find((p) => p.role === 'sink')!;
  check('czystość: przesuwanie zlewu po blacie', sink1.at > sink0.at, `${sink0.at} → ${sink1.at}`);

  // okno nad całym ciągiem → brak szafek górnych, ale ciąg dolny zostaje
  const windowCtx = ctx({ obstacles: [{ kind: 'window', from: 0, to: 5000, y0: 900, y1: 2300 }] });
  const blocked = planZone('kitchen-clean', a, windowCtx);
  check('czystość: okno usuwa szafki górne', blocked.parts.every((p) => p.type !== 'wall'));
  check('czystość: okno nie usuwa dołu', blocked.parts.some((p) => p.type === 'base'));
}

// ---------------------------------------------------------------------------
// 4. Wysoka zabudowa: wysokość do sufitu i zestaw słupków
// ---------------------------------------------------------------------------
{
  const plan = planZone('kitchen-tall', zoneDefaults('kitchen-tall'), ctx());
  check('wysoka: lodówka + piekarnik + spiżarnia', plan.parts.length === 3);
  check('wysoka: wysokość do sufitu 2560', plan.parts.every((p) => p.height === 2560), String(plan.parts[0]?.height));
  const low = planZone('kitchen-tall', { ...zoneDefaults('kitchen-tall'), toCeiling: false }, ctx());
  check('wysoka: korpus 2216', low.parts.every((p) => p.height === 2216));
}

// ---------------------------------------------------------------------------
// 5. Wyspa: blat z nawisem, brak szafek górnych
// ---------------------------------------------------------------------------
{
  const plan = planZone('kitchen-island', zoneDefaults('kitchen-island'), ctx());
  check('wyspa: brak szafek górnych', plan.parts.every((p) => p.type === 'base'));
  check('wyspa: blat 860 (korpus 560 + nawis 300)', plan.parts.every((p) => p.worktopDepth === 860));
  check('wyspa: płyta na środku', plan.parts.some((p) => p.appliances.includes('hob')));
  check('wyspa: okap sufitowy', plan.parts.some((p) => p.appliances.includes('hood')));
  const noSeat = planZone('kitchen-island', { ...zoneDefaults('kitchen-island'), seating: false }, ctx());
  check('wyspa: bez nawisu blat 680', noSeat.parts.every((p) => p.worktopDepth === 680));
}

// ---------------------------------------------------------------------------
// 6. Szafy: głębokości i panele
// ---------------------------------------------------------------------------
{
  const h = planZone('wardrobe-hinged', zoneDefaults('wardrobe-hinged'), ctx());
  check('szafa otwierana: głębokość 600', h.parts.every((p) => p.depth === 600));
  check('szafa otwierana: skrzydła', h.parts.every((p) => p.doors >= 1));
  const s = planZone('wardrobe-sliding', zoneDefaults('wardrobe-sliding'), ctx());
  check('szafa przesuwna: głębokość 650', s.parts.every((p) => p.depth === 650));
  check('szafa przesuwna: 2 panele', s.parts[0]?.slidingPanels === 2);
  const s3 = planZone('wardrobe-sliding', { ...zoneDefaults('wardrobe-sliding'), panels: 3 }, ctx());
  check('szafa przesuwna: 3 panele', s3.parts[0]?.slidingPanels === 3);
}

// ---------------------------------------------------------------------------
// 7. RTV i łazienka
// ---------------------------------------------------------------------------
{
  const tv = planZone('living-tv', zoneDefaults('living-tv'), ctx());
  check('RTV: szafka wisząca 250', tv.parts.filter((p) => p.type === 'base').every((p) => p.mountHeight === 250));
  check('RTV: TV w urządzeniach', tv.parts.some((p) => p.appliances.includes('tv')));
  const tvWall = tv.parts.find((p) => p.type === 'wall');
  check('RTV: nadbudowa nad telewizorem (≥1600)', !!tvWall && tvWall.mountHeight >= 1600, String(tvWall?.mountHeight));
  const bath = planZone('bathroom', zoneDefaults('bathroom'), ctx());
  check('łazienka: umywalka', bath.parts.some((p) => p.appliances.includes('basin')));
  check('łazienka: lustro', bath.parts.some((p) => p.appliances.includes('mirror')));
  check('łazienka: słupek 400', bath.parts.some((p) => p.role === 'bath-tall' && p.width === 400));
}

// ---------------------------------------------------------------------------
// 8. Ściana, drzwi, wąskie pomieszczenie
// ---------------------------------------------------------------------------
{
  const doorCtx = ctx({
    usableFrom: 1000,
    usableLength: 4000,
    obstacles: [{ kind: 'door', from: 0, to: 900, y0: 0, y1: 2100 }],
  });
  const plan = planZone('kitchen-clean', { ...zoneDefaults('kitchen-clean'), align: 'left' }, doorCtx);
  check('drzwi: zabudowa przesunięta za skrzydło', plan.start >= 1000, `start ${Math.round(plan.start)}`);

  const narrow = planZone('kitchen-cook', zoneDefaults('kitchen-cook'), ctx({ wallLength: 2400 }));
  check('wąska ściana: ostrzeżenie', narrow.warnings.length > 0);
  check('wąska ściana: bez witryn', narrow.parts.every((p) => !p.role.startsWith('witryna')));
}

// ---------------------------------------------------------------------------
// 9. Pytania zależne od odpowiedzi
// ---------------------------------------------------------------------------
{
  const cook = zoneDefaults('kitchen-cook');
  check('pytania: okap tylko przy płycie', activeQuestions('kitchen-cook', { ...cook, hob: 'none' }).every((q) => q.id !== 'hood'));
  const noOven = activeQuestions('kitchen-cook', { ...cook, oven: 'none' });
  check('pytania: mikrofala tylko przy słupku', noOven.every((q) => q.id !== 'microwave'));
  const clean = activeQuestions('kitchen-clean', { ...zoneDefaults('kitchen-clean'), sink: 'none' });
  check('pytania: pozycja zlewu tylko przy zlewie', clean.every((q) => q.id !== 'sinkPos'));
}

// ---------------------------------------------------------------------------
// 10. Każda strefa ma opisy zależności (wymóg „obszernie opisane")
// ---------------------------------------------------------------------------
for (const spec of ZONE_SPECS) {
  check(`${spec.kind}: opis zależności`, spec.relations.length >= 4 && spec.description.length > 40);
}

console.log(`\n${fails === 0 ? 'WSZYSTKIE TESTY OK' : `${fails} BŁĘDÓW`}`);
process.exit(fails ? 1 : 0);
