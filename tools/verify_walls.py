"""Kontrola dopasowania: ile punktów chmury leży na każdej wykrytej ścianie.

Dla każdego odcinka ściany z planu liczymy punkty chmury w pasie ±4 cm od
płaszczyzny i w obrębie odcinka. Wysoka pokrytość = ściana naprawdę istnieje
w skanie (a nie jest wymyślona przez generator).
"""
import json
import sys
import numpy as np

ply = sys.argv[1] if len(sys.argv) > 1 else "app/public/dom-chmura.ply"
plan_path = sys.argv[2] if len(sys.argv) > 2 else "ios/Resources/Scans/dom-chmura-plan.json"
plan = json.load(open(plan_path))

raw = open(ply, "rb").read()
i = raw.find(b"end_header") + len(b"end_header")
while raw[i:i + 1] in (b"\n", b"\r"):
    i += 1
rec = np.dtype([("x", "<f4"), ("y", "<f4"), ("z", "<f4"),
                ("r", "u1"), ("g", "u1"), ("b", "u1")])
n = (len(raw) - i) // rec.itemsize
d = np.frombuffer(raw, dtype=rec, count=n, offset=i)
X, Y, Z = (d[k].astype(np.float64) for k in ("x", "y", "z"))

sx = X - plan["center"]["x"]
sy = Z - plan["floor"]
sz = Y - plan["center"]["y"]

TOL = 0.04
print(f"plan: {plan['width']:.2f} x {plan['depth']:.2f} x {plan['height']:.2f} m")
print(f"ścian do sprawdzenia: {len(plan['walls'])}\n")
covered = 0
for w in plan["walls"]:
    if w["axis"] == "x":
        perp, along = sx, sz
    else:
        perp, along = sz, sx
    mask = (np.abs(perp - w["pos"]) < TOL) & (along >= w["from"]) & (along <= w["to"]) \
           & (sy > -0.1) & (sy < plan["height"] + 0.1)
    count = int(mask.sum())
    per_m = count / max(0.01, w["length"])
    ok = per_m > 40
    covered += 1 if ok else 0
    print(f"  {w['axis']}={w['pos']:+.2f} {w['from']:+.2f}..{w['to']:+.2f} "
          f"({w['length']:.2f} m): {count:6d} pkt, {per_m:6.0f} pkt/m "
          f"{'OK' if ok else 'słabo'}")

print(f"\nścian potwierdzonych w chmurze: {covered}/{len(plan['walls'])}")
