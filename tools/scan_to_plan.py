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

# środek obrytu → współrzędne lokalne (dom w środku sceny)
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
    "points": int(len(x)),
    "height": round(height, 3),
    "width": round(width, 3),
    "depth": round(depth, 3),
    "walls": walls,
}
import os
os.makedirs(os.path.dirname(dst), exist_ok=True)
json.dump(plan, open(dst, "w"), indent=1)

print(f"wysokość {height:.2f} m, obrys {width:.2f} × {depth:.2f} m")
print(f"ścian (odcinków po filtracji): {len(walls)}")
for w in walls:
    print(f"  {w['axis']}={w['pos']:+.2f}  od {w['from']:+.2f} do {w['to']:+.2f}  "
          f"({w['to']-w['from']:.2f} m)")
print("zapisane:", dst)
