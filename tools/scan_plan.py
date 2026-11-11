"""Rzut chmury na płaszczyznę poziomą: ściany, otwory, obrys.

Chmura z Trimble X9 jest w układzie, w którym pionem jest Z (najostrzejsze
piki histogramu: podłoga i sufit). Ten skrypt liczy:
  - wysokość pomieszczenia,
  - dominujące linie ścian w X i Y,
  - mapę zajętości ASCII (do oceny układu),
  - prostokąt obrytu.
"""
import sys
import numpy as np

path = sys.argv[1] if len(sys.argv) > 1 else "app/public/dom-chmura.ply"
raw = open(path, "rb").read()
i = raw.find(b"end_header") + len(b"end_header")
while raw[i:i + 1] in (b"\n", b"\r"):
    i += 1
rec = np.dtype([("x", "<f4"), ("y", "<f4"), ("z", "<f4"),
                ("r", "u1"), ("g", "u1"), ("b", "u1")])
n = (len(raw) - i) // rec.itemsize
d = np.frombuffer(raw, dtype=rec, count=n, offset=i)
x, y, z = d["x"].astype(np.float64), d["y"].astype(np.float64), d["z"].astype(np.float64)

# piki pionu = podłoga i sufit
h, e = np.histogram(z, bins=200)
order = np.argsort(h)[-2:]
floor_z, ceil_z = sorted(float((e[k] + e[k + 1]) / 2) for k in order)
print(f"podłoga Z={floor_z:.2f}  sufit Z={ceil_z:.2f}  wysokość={ceil_z-floor_z:.2f} m")

band = (z > floor_z + 0.25) & (z < floor_z + 2.3)
xs, ys = x[band], y[band]
print(f"punktów w pasie ścian: {band.sum()}")

def wall_lines(values, label, bins=160, take=8, min_gap=0.30):
    hh, ee = np.histogram(values, bins=bins)
    picked = []
    for idx in np.argsort(hh)[::-1]:
        c = float((ee[idx] + ee[idx + 1]) / 2)
        if hh[idx] < 200:
            break
        if all(abs(c - p) > min_gap for p, _ in picked):
            picked.append((c, int(hh[idx])))
        if len(picked) >= take:
            break
    print(f"\nŚCIANY {label}:")
    for c, cnt in sorted(picked):
        print(f"  {label}={c:+.2f}  punktów={cnt}")
    return sorted(p for p, _ in picked)

wall_x = wall_lines(xs, "X")
wall_y = wall_lines(ys, "Y")

print(f"\nobrys X: {xs.min():.2f}..{xs.max():.2f} ({xs.max()-xs.min():.2f} m)")
print(f"obrys Y: {ys.min():.2f}..{ys.max():.2f} ({ys.max()-ys.min():.2f} m)")

# mapa zajętości 0.4 m
cell = 0.4
gx = ((xs - xs.min()) / cell).astype(int)
gy = ((ys - ys.min()) / cell).astype(int)
W, H = gx.max() + 1, gy.max() + 1
grid = np.zeros((H, W), dtype=int)
np.add.at(grid, (gy, gx), 1)
thr = max(3, int(np.percentile(grid[grid > 0], 60)))
print(f"\nmapa zajętości (0.4 m, próg {thr} pkt):")
for row in range(H - 1, -1, -1):
    print("".join("#" if grid[row, col] >= thr else ("." if grid[row, col] else " ")
                  for col in range(W)))
