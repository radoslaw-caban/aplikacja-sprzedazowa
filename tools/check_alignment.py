"""Sprawdza, czy chmura po transformacji planu mieści się w bryle domu.

Liczby muszą się zgadzać z tym, co robi aplikacja:
  p_scene = (x - center.x, z - floor, y - center.y)
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
x, y, z = (d[k].astype(np.float64) for k in ("x", "y", "z"))

cx, cy = plan["center"]["x"], plan["center"]["y"]
floor = plan["floor"]
W, D, H = plan["width"], plan["depth"], plan["height"]

sx = x - cx
sy = z - floor
sz = y - cy
print(f"plan: {W:.2f} x {D:.2f} x {H:.2f} m, center=({cx:.3f},{cy:.3f}), floor={floor:.3f}")
print(f"po transformacji: X {sx.min():+.2f}..{sx.max():+.2f}  "
      f"Y {sy.min():+.2f}..{sy.max():+.2f}  Z {sz.min():+.2f}..{sz.max():+.2f}")

inside = ((np.abs(sx) <= W / 2 + 0.35) & (np.abs(sz) <= D / 2 + 0.35)
          & (sy >= -0.35) & (sy <= H + 0.35))
print(f"punktów w bryle: {inside.sum()} z {len(x)}")
if inside.sum():
    print(f"  bbox w bryle: X {sx[inside].min():+.2f}..{sx[inside].max():+.2f} "
          f"Z {sz[inside].min():+.2f}..{sz[inside].max():+.2f} "
          f"Y {sy[inside].min():+.2f}..{sy[inside].max():+.2f}")
