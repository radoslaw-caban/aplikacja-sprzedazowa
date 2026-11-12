
import pye57, numpy as np
f = pye57.E57("/Users/radoslawcaban/Downloads/1.e57")
d = f.read_scan(0, colors=True, ignore_missing_fields=True, intensity=False)
x = d["cartesianX"].astype(np.float64); y = d["cartesianY"].astype(np.float64); z = d["cartesianZ"].astype(np.float64)

# po zamianie Y<->Z: pion = y
print("=== po zamianie: pion = y ===")
print(f"y: {y.min():.2f} … {y.max():.2f}")
hist, edges = np.histogram(y, bins=120)
top = np.argsort(hist)[-6:][::-1]
print("piki y (podloga/sufit):")
for i in top: print(f"  y {edges[i]:+.2f}…{edges[i+1]:+.2f}  {hist[i]:>10,}")

# ile punktow w pasmach 30 cm nad najnizszym poziomem
lo = y.min()
for band in [(0.0,0.35),(0.35,0.7),(1.0,1.4)]:
    m = (y >= lo+band[0]) & (y < lo+band[1])
    print(f"pasmo {band[0]:.2f}-{band[1]:.2f} nad min: {m.sum():,} pkt")
