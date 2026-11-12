/**
 * Działka i pole robocze edytora otoczenia.
 *
 * Wszystko w MILIMETRACH, jak reszta projektu. Działka jest rysowana na
 * planie: obrys + dojazd. Siatka ma zmienną gęstość — od 1 mm do 1 m —
 * i ta gęstość jest jednocześnie:
 *   - krokiem przyciągania kursora (precyzja wstawiania),
 *   - ziarnem dokładności pomiarów,
 *   - ziarnem zapisu współrzędnych.
 *
 * Świadoma decyzja: NIE zaokrąglamy geometrii do siatki przy renderze,
 * tylko przy zapisie i przy wstawianiu. Inaczej zmiana gęstości niszczyłaby
 * już postawione elementy.
 */

export type PlotPoint = { x: number; z: number };

/** Gęstości siatki — dokładnie te, które widać w panelu precyzji. */
export const GRID_STEPS = [
  1, 2, 5, 10, 20, 50, 100, 200, 500, 1000,
] as const;

export type GridStep = (typeof GRID_STEPS)[number];

export interface PlotDraft {
  /** obrys działki (wielokąt, mm) */
  outline: PlotPoint[];
  /** dojazd: odcinek od krawędzi drogi do granicy działki */
  driveway: { from: PlotPoint; to: PlotPoint; width: number } | null;
  /** północ geograficzna w stopniach (0 = północ na -Z) */
  northDeg: number;
}

export interface Plot {
  id: string;
  /** nazwa szablonu: "działka" + nazwisko klienta */
  name: string;
  client: string;
  outline: PlotPoint[];
  driveway: { from: PlotPoint; to: PlotPoint; width: number } | null;
  northDeg: number;
  /** gęstość siatki / precyzja projektu (mm) */
  gridStep: number;
  createdAt: number;
  updatedAt: number;
}

export function emptyPlot(client = ''): Plot {
  return {
    id: `plot-${Date.now().toString(36)}`,
    name: 'działka',
    client,
    outline: [],
    driveway: null,
    northDeg: 0,
    gridStep: 100,
    createdAt: Date.now(),
    updatedAt: Date.now(),
  };
}

/** Nazwa wyświetlana: „działka Kowalski". */
export function plotLabel(p: Plot): string {
  return p.client ? `${p.name} ${p.client}` : p.name;
}

// ---------- geometria ----------

export function polygonArea(pts: PlotPoint[]): number {
  if (pts.length < 3) return 0;
  let a = 0;
  for (let i = 0; i < pts.length; i++) {
    const j = (i + 1) % pts.length;
    a += pts[i].x * pts[j].z - pts[j].x * pts[i].z;
  }
  return Math.abs(a) / 2; // mm²
}

export function polygonPerimeter(pts: PlotPoint[]): number {
  if (pts.length < 2) return 0;
  let s = 0;
  for (let i = 0; i < pts.length; i++) {
    const j = (i + 1) % pts.length;
    s += Math.hypot(pts[j].x - pts[i].x, pts[j].z - pts[i].z);
  }
  return s;
}

export function pointInPolygon(p: PlotPoint, poly: PlotPoint[]): boolean {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const xi = poly[i].x;
    const zi = poly[i].z;
    const xj = poly[j].x;
    const zj = poly[j].z;
    const hit = zi > p.z !== zj > p.z && p.x < ((xj - xi) * (p.z - zi)) / (zj - zi) + xi;
    if (hit) inside = !inside;
  }
  return inside;
}

export function boundsOf(pts: PlotPoint[]): { minX: number; maxX: number; minZ: number; maxZ: number } {
  if (!pts.length) return { minX: 0, maxX: 0, minZ: 0, maxZ: 0 };
  let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
  for (const p of pts) {
    if (p.x < minX) minX = p.x;
    if (p.x > maxX) maxX = p.x;
    if (p.z < minZ) minZ = p.z;
    if (p.z > maxZ) maxZ = p.z;
  }
  return { minX, maxX, minZ, maxZ };
}

/** Prostokąt działki — domyślny start (30 × 50 m). */
export function rectPlot(widthMm = 30000, depthMm = 50000): PlotPoint[] {
  const w = widthMm / 2;
  const d = depthMm / 2;
  return [
    { x: -w, z: -d },
    { x: w, z: -d },
    { x: w, z: d },
    { x: -w, z: d },
  ];
}

// ---------- precyzja ----------

export function snap(value: number, step: number): number {
  if (step <= 0) return value;
  return Math.round(value / step) * step;
}

export function snapPoint(p: PlotPoint, step: number): PlotPoint {
  return { x: snap(p.x, step), z: snap(p.z, step) };
}

/** Etykieta precyzji do panelu: „1 mm", „10 cm", „1 m". */
export function precisionLabel(step: number): string {
  if (step < 10) return `${step} mm`;
  if (step < 1000) return `${step / 10} cm`;
  return `${step / 1000} m`;
}

/** Krok siatki w mm → odległość między liniami w mm (ta sama wartość). */
export function gridSpacing(step: number): number {
  return step;
}

/**
 * Poziom szczegółowości siatki do rysowania: przy 1 mm nie da się narysować
 * linii co milimetr na 50 m, więc rysujemy linie główne (co 10× i co 100×)
 * i zagęszczamy dopiero przy zbliżeniu kamery.
 */
export function gridLevels(step: number): { minor: number; major: number; micro: number } {
  return { micro: step, minor: step * 10, major: step * 100 };
}
