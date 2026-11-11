"""Ustala, która oś chmury jest pionowa (podłoga/sufit dają ostre piki)."""
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
pts = np.stack([d["x"], d["y"], d["z"]], axis=1).astype(np.float64)

print("punktów:", len(pts))
for name, ax in zip("XYZ", range(3)):
    v = pts[:, ax]
    h, e = np.histogram(v, bins=200)
    peak = h.max() / max(1.0, h.mean())
    best = np.argsort(h)[-3:][::-1]
    print(f"{name}: zakres {v.min():.2f}..{v.max():.2f}  pik/średnia={peak:.1f}  "
          f"szczyty={[round(float((e[b]+e[b+1])/2),2) for b in best]}")

# PCA
c = pts - pts.mean(axis=0)
cov = np.cov(c.T)
w, v = np.linalg.eigh(cov)
order = np.argsort(w)[::-1]
print("\nPCA wariancje:", [f"{w[k]:.2f}" for k in order])
for k in order:
    print("  oś", np.round(v[:, k], 3), "var", round(float(w[k]), 2))
