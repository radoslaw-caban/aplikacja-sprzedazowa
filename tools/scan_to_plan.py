"""Z chmury punktów robi plan domu (JSON): obrys, wysokość, ściany.

Ściany wykrywamy jako płaszczyzny prostopadłe do X lub Y (piki histogramu),
a potem dzielimy każdą linię na odcinki tam, gdzie faktycznie są punkty.
Przerwy > 0,8 m traktujemy jako otwory (drzwi/przejścia) i zapisujemy osobno.
"""
import json
import sys
import numpy as np

src = sys.argv[1] if len(sys.argv) > 1 else "app/public/dom-chmura.ply"
dst = sys.argv[2] if len(sys.argv) > 2 else "ios/Resources/Scans/dom-chmura-plan.json"

raw = open(src, "rb").read()
i = raw.find(b"end_header") + len(b"end_header")
while raw[i:i + 1] in (b"\n", b"\r"):
    i += 1
rec = np.dtype([("x", "<f4"), ("y", "<f4"), ("z", "<f4"),
                ("r", "u1"), ("g", "u1"), ("b", "u1")])
n = (len(raw) - i) // rec.itemsize
d = np.frombuffer(raw, dtype=rec, count=n, offset=i)
x, y, z = (d[k].astype(np.float64) for k in ("x", "y", "z"))

h, e = np.histogram(z, bins=200)
order = np.argsort(h)[-2:]
floor_z, ceil_z = sorted(float((e[k] + e[k + 1]) / 2) for k in order)
height = ceil_z - floor_z

band = (z > floor_z + 0.25) & (z < floor_z + 2.3)
xs, ys = x[band], y[band]

# OBRYS Z RZECZYWISTEJ PODŁOGI, nie z bounding boxa całego pasa ścian.
# Skan obejmuje też przestrzeń obok pomieszczenia (X w chmurze ma 14 m,
# a pomieszczenie ~10 m), więc bbox zaniósłby nas w miejsca bez podłogi.
band_floor = (z > floor_z - 0.15) & (z < floor_z + 0.35)
fx, fy = x[band_floor] - (xs.min() + xs.max()) / 2, y[band_floor] - (ys.min() + ys.max()) / 2

CELL = 0.25
gx = np.floor(fx / CELL).astype(int)
gy = np.floor(fy / CELL).astype(int)
gx -= gx.min()
gy -= gy.min()
W, H = gx.max() + 1, gy.max() + 1
grid = np.zeros((H, W), dtype=np.int32)
np.add.at(grid, (gy, gx), 1)
occupied = grid >= 4

# największa spójna wyspa (BFS) — pomieszczenie, nie przypadkowe punkty
from collections import deque
seen = np.zeros_like(occupied)
best = []
for sy in range(H):
    for sx in range(W):
        if not occupied[sy, sx] or seen[sy, sx]:
            continue
        queue = deque([(sy, sx)])
        seen[sy, sx] = True
        cells = []
        while queue:
            cy_, cx_ = queue.popleft()
            cells.append((cy_, cx_))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = cy_ + dy, cx_ + dx
                if 0 <= ny < H and 0 <= nx < W and occupied[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    queue.append((ny, nx))
        if len(cells) > len(best):
            best = cells

if best:
    # Obrys z PERCENTYLI punktów podłogi (1–99%), nie z bboxa: pojedyncze
    # punkty odstające (i sąsiednie pomieszczenia) rozciągały bryłę na 14 m.
    px0, px1 = np.percentile(fx, [1, 99])
    py0, py1 = np.percentile(fy, [1, 99])
    xs_cells = np.array([c[1] for c in best])
    ys_cells = np.array([c[0] for c in best])
    base_x = float((xs.min() + xs.max()) / 2)
    base_y = float((ys.min() + ys.max()) / 2)
    x0, x1 = float(px0) + base_x, float(px1) + base_x
    y0, y1 = float(py0) + base_y, float(py1) + base_y
    cx = (x0 + x1) / 2
    cy = (y0 + y1) / 2
    width = x1 - x0
    depth = y1 - y0
    print(f"pomieszczenie z podłogi: {width:.2f} x {depth:.2f} m "
          f"(komórek {len(best)}, bbox całego pasa {xs.max()-xs.min():.2f} x {ys.max()-ys.min():.2f})")
else:
    cx = (xs.min() + xs.max()) / 2
    cy = (ys.min() + ys.max()) / 2
    width = float(xs.max() - xs.min())
    depth = float(ys.max() - ys.min())

xs = xs - cx
ys = ys - cy

TOL = 0.07          # połowa grubości wykrywanej płaszczyzny
MIN_RUN = 0.5       # krótszy odcinek to szum
MIN_GAP = 0.8       # przerwa większa niż to = otwór
BIN = 0.05          # rozdzielczość wzdłuż ściany


def line_positions(values, bins=140, min_points=600, gap=0.35, take=10):
    hh, ee = np.histogram(values, bins=bins)
    out = []
    for idx in np.argsort(hh)[::-1]:
        if hh[idx] < min_points:
            break
        c = float((ee[idx] + ee[idx + 1]) / 2)
        if all(abs(c - p) > gap for p in out):
            out.append(c)
        if len(out) >= take:
            break
    return sorted(out)


def segments(axis, pos):
    """Odcinki wzdłuż ściany o zadanej pozycji prostopadłej."""
    perp, along = (xs, ys) if axis == "x" else (ys, xs)
    m = np.abs(perp - pos) < TOL
    if m.sum() < 80:
        return []
    vals = along[m]
    lo, hi = float(vals.min()), float(vals.max())
    if hi - lo < MIN_RUN:
        return []
    nb = max(1, int((hi - lo) / BIN))
    hist, edges = np.histogram(vals, bins=nb, range=(lo, hi))
    filled = hist > 0
    out = []
    start = None
    for k, f in enumerate(filled):
        if f and start is None:
            start = k
        elif not f and start is not None:
            out.append((float(edges[start]), float(edges[k])))
            start = None
    if start is not None:
        out.append((float(edges[start]), float(edges[-1])))
    # scal drobne przerwy i odrzuć krótkie odcinki
    merged = []
    for a, b in out:
        if merged and a - merged[-1][1] < MIN_GAP / 2:
            merged[-1] = (merged[-1][0], b)
        else:
            merged.append((a, b))
    return [(round(a, 3), round(b, 3)) for a, b in merged if b - a >= MIN_RUN]


# OBRYS: krawędzie zajętych komórek, których sąsiad jest pusty.
# Bbox dawał prostokąt obejmujący puste pole obok pokoju — dlatego chmura
# „nie dochodziła" do dwóch ścian.
outline_edges = []      # (axis, pos, from, to)
if best:
    mask = np.zeros((H, W), dtype=bool)
    for (ry, rx) in best:
        mask[ry, rx] = True
    ox, oy = float(xs.min()), float(ys.min())
    for ry in range(H):
        for rx in range(W):
            if not mask[ry, rx]:
                continue
            x0c = ox + rx * CELL - cx
            x1c = x0c + CELL
            y0c = oy + ry * CELL - cy
            y1c = y0c + CELL
            if ry == 0 or not mask[ry - 1, rx]:
                outline_edges.append(("x", round(y0c, 3), round(x0c, 3), round(x1c, 3)))
            if ry == H - 1 or not mask[ry + 1, rx]:
                outline_edges.append(("x", round(y1c, 3), round(x0c, 3), round(x1c, 3)))
            if rx == 0 or not mask[ry, rx - 1]:
                outline_edges.append(("y", round(x0c, 3), round(y0c, 3), round(y1c, 3)))
            if rx == W - 1 or not mask[ry, rx + 1]:
                outline_edges.append(("y", round(x1c, 3), round(y0c, 3), round(y1c, 3)))

def merge_edges(edges, tol=0.03):
    """Scala współliniowe krawędzie w dłuższe odcinki."""
    groups = {}
    for axis, pos, a, b in edges:
        key = (axis, round(pos, 2))
        groups.setdefault(key, []).append((a, b))
    out = []
    for (axis, pos), spans in groups.items():
        spans.sort()
        cur_a, cur_b = spans[0]
        for a, b in spans[1:]:
            if a - cur_b <= tol:
                cur_b = max(cur_b, b)
            else:
                out.append({"axis": axis, "pos": pos, "from": round(cur_a, 3), "to": round(cur_b, 3),
                            "length": round(cur_b - cur_a, 3)})
                cur_a, cur_b = a, b
        out.append({"axis": axis, "pos": pos, "from": round(cur_a, 3), "to": round(cur_b, 3),
                    "length": round(cur_b - cur_a, 3)})
    return [e for e in out if e["length"] >= 0.4]

# PODŁOGA: poziome przebiegi zajętych komórek, scalone w wiersze.
# Dzięki temu strop i posadzka są dokładnie tam, gdzie skan ma podłogę —
# без prostokąta obejmującego puste pole obok pomieszczenia.
floor_runs = []
if best:
    mask = np.zeros((H, W), dtype=bool)
    for (ry, rx) in best:
        mask[ry, rx] = True
    ox, oy = float(xs.min()), float(ys.min())
    for ry in range(H):
        row = mask[ry]
        if not row.any():
            continue
        start_x = None
        for rx in range(W + 1):
            filled = rx < W and row[rx]
            if filled and start_x is None:
                start_x = rx
            elif not filled and start_x is not None:
                x0 = ox + start_x * CELL - cx
                x1 = ox + rx * CELL - cx
                z0 = oy + ry * CELL - cy
                floor_runs.append({"x0": round(x0, 3), "x1": round(x1, 3),
                                   "z0": round(z0, 3), "z1": round(z0 + CELL, 3)})
                start_x = None

print(f"podłoga: {len(floor_runs)} przebiegów (wierszy)")

# WYGŁADZENIE maski: domknięcie morfologiczne (dylatacja + erozja), żeby
# obrys nie był postrzępiony od szumu pojedynczych komórek.
def dilate(m):
    out = m.copy()
    out[1:, :] |= m[:-1, :]
    out[:-1, :] |= m[1:, :]
    out[:, 1:] |= m[:, :-1]
    out[:, :-1] |= m[:, 1:]
    return out

def erode(m):
    out = m.copy()
    out[1:, :] &= m[:-1, :]
    out[:-1, :] &= m[1:, :]
    out[:, 1:] &= m[:, :-1]
    out[:, :-1] &= m[:, 1:]
    out[0, :] = out[1, :] = out[:, 0] = out[:, -1] = False
    out[0, :] |= m[0, :]
    out[-1, :] |= m[-1, :]
    out[:, 0] |= m[:, 0]
    out[:, -1] |= m[:, -1]
    return out

if best:
    closed = erode(erode(dilate(dilate(mask))))
    # jeśli domknięcie zjadło pokój, wracamy do maski surowej
    if closed.sum() > mask.sum() * 0.5:
        mask = closed

    # OBRYS z krawędzi maski; scalanie po pozycji z tolerancją 5 cm
    raw_edges = []
    for ry in range(H):
        for rx in range(W):
            if not mask[ry, rx]:
                continue
            x0w = ox + rx * CELL - cx
            x1w = x0w + CELL
            z0w = oy + ry * CELL - cy
            z1w = z0w + CELL
            if ry == 0 or not mask[ry - 1, rx]:
                raw_edges.append(("x", z0w, x0w, x1w))
            if ry == H - 1 or not mask[ry + 1, rx]:
                raw_edges.append(("x", z1w, x0w, x1w))
            if rx == 0 or not mask[ry, rx - 1]:
                raw_edges.append(("y", x0w, z0w, z1w))
            if rx == W - 1 or not mask[ry, rx + 1]:
                raw_edges.append(("y", x1w, z0w, z1w))

    groups = {}
    for axis, pos, a, b in raw_edges:
        key = (axis, round(pos / 0.05) * 0.05)
        groups.setdefault(key, []).append((a, b))
    outline = []
    for (axis, pos), spans in groups.items():
        spans.sort()
        cur_a, cur_b = spans[0]
        for a, b in spans[1:]:
            if a - cur_b <= CELL * 1.6:
                cur_b = max(cur_b, b)
            else:
                if cur_b - cur_a >= CELL * 1.5:
                    outline.append({"axis": axis, "pos": round(pos, 3),
                                    "from": round(cur_a, 3), "to": round(cur_b, 3),
                                    "length": round(cur_b - cur_a, 3)})
                cur_a, cur_b = a, b
        if cur_b - cur_a >= CELL * 1.5:
            outline.append({"axis": axis, "pos": round(pos, 3),
                            "from": round(cur_a, 3), "to": round(cur_b, 3),
                            "length": round(cur_b - cur_a, 3)})
else:
    outline = []

print(f"obrys: {len(outline)} odcinków, podłoga: {len(floor_runs)} przebiegów")


walls = []
MIN_WALL = 1.9      # krótsze odcinki to meble i sprzęt, nie ściany

for pos in line_positions(xs):
    for a, b in segments("x", pos):
        if b - a >= MIN_WALL:
            walls.append({"axis": "x", "pos": round(pos, 3), "from": a, "to": b,
                          "length": round(b - a, 3)})
for pos in line_positions(ys):
    for a, b in segments("y", pos):
        if b - a >= MIN_WALL:
            walls.append({"axis": "y", "pos": round(pos, 3), "from": a, "to": b,
                          "length": round(b - a, 3)})

# deduplikacja: równoległe linie bliżej niż 0,5 m to ta sama ściana
# (grubość wykrywania + tynk); zostawiamy tę z dłuższym odcinkiem
walls.sort(key=lambda w: -w["length"])
kept = []
for w in walls:
    twin = next((k for k in kept
                 if k["axis"] == w["axis"] and abs(k["pos"] - w["pos"]) < 0.5
                 and min(k["to"], w["to"]) - max(k["from"], w["from"]) > 0), None)
    if twin is None:
        kept.append(w)
walls = sorted(kept, key=lambda w: (w["axis"], w["pos"]))

plan = {
    "source": "dom-chmura.ply",
    # transformacja chmury do sceny: pion to Z chmury, a plan jest
    # wyśrodkowany na (cx, cy) i oparty na podłodze floor_z
    "up": "z",
    "center": {"x": round(cx, 4), "y": round(cy, 4)},
    "floor": round(floor_z, 4),
    "points": int(len(x)),
    "height": round(height, 3),
    "width": round(width, 3),
    "depth": round(depth, 3),
    "floorRuns": floor_runs,
    "outline": outline,
    # WYKRYTE ODCINKI TO ZABUDOWA KUCHENNA, nie ściany: chmura jest gęsta
    # właśnie w pasie szafek (setki punktów na metr), a nie na obwodzie pokoju.
    # Dlatego idą do sceny jako szafki (0,6 m głębokości, 0,9 m wysokości),
    # a obwód pokoju bierzemy z percentyli chmury.
    "cabinets": walls,
    "walls": [],
}
import os
os.makedirs(os.path.dirname(dst), exist_ok=True)
json.dump(plan, open(dst, "w"), indent=1)

print(f"wysokość {height:.2f} m, obrys {width:.2f} × {depth:.2f} m")
print(f"ścian wewnętrznych (odcinków po filtracji): {len(walls)}")
for w in walls:
    print(f"  {w['axis']}={w['pos']:+.2f}  od {w['from']:+.2f} do {w['to']:+.2f}  "
          f"({w['to']-w['from']:.2f} m)")
print("zapisane:", dst)
