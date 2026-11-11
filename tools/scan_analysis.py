"""Analiza chmury punktów domu: obrys, ściany, wysokości.

Wynik: wypisuje wymiary i dominujące płaszczyzny ścian (X i Z), żeby
geometrię domu zbudować z DANYCH, a nie z wymyślonych liczb.
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
data = np.frombuffer(raw, dtype=rec, count=n, offset=i)
x, y, z = data["x"], data["y"], data["z"]

print(f"plik: {path}")
print(f"punktów: {len(x)}")
print(f"X: {x.min():.2f} .. {x.max():.2f}  rozpiętość {x.max()-x.min():.2f} m")
print(f"Y: {y.min():.2f} .. {y.max():.2f}  rozpiętość {y.max()-y.min():.2f} m")
print(f"Z: {z.min():.2f} .. {z.max():.2f}  rozpiętość {z.max()-z.min():.2f} m")

# poziomy: podłoga i sufit
hist, edges = np.histogram(y, bins=80)
top = np.argsort(hist)[-6:][::-1]
print("\nGĘSTE POZIOMY Y (podłoga/sufit):")
for t in top:
    print(f"  y={edges[t]:+.2f}  punktów={hist[t]}")

# ściany: histogram X i Z (tylko punkty w pasie wysokości 0.3-2.4 m)
mask = (y > y.min() + 0.3) & (y < y.min() + 2.4)
xs, zs = x[mask], z[mask]
print(f"\npunktów w pasie ścian: {mask.sum()}")

def peaks(values, label, bins=120):
    h, e = np.histogram(values, bins=bins)
    order = np.argsort(h)[-12:][::-1]
    picked = []
    for idx in order:
        c = (e[idx] + e[idx + 1]) / 2
        if all(abs(c - p) > 0.35 for p, _ in picked):
            picked.append((c, h[idx]))
        if len(picked) >= 6:
            break
    print(f"\nŚCIANY {label} (dominujące płaszczyzny):")
    for c, cnt in sorted(picked):
        print(f"  {label}={c:+.2f}  punktów={cnt}")
    return [p for p, _ in picked]

peaks(xs, "X")
peaks(zs, "Z")

# podłoga: mediana Y dolnych 5%
floor = np.percentile(y, 2)
ceiling = np.percentile(y, 98)
print(f"\npodłoga ~{floor:.2f} m, sufit ~{ceiling:.2f} m, wysokość {ceiling-floor:.2f} m")

# gęstość w siatce 0.5 m — obrys zabudowy
gx = np.floor((x - x.min()) / 0.5).astype(int)
gz = np.floor((z - z.min()) / 0.5).astype(int)
grid = np.zeros((gx.max() + 1, gz.max() + 1), dtype=int)
np.add.at(grid, (gx, gz), 1)
occupied = grid > 25
print(f"komórki 0.5 m z zabudową: {occupied.sum()}")
print(f"prostokąt zabudowy: {x.min():.2f}..{x.max():.2f} × {z.min():.2f}..{z.max():.2f}")
