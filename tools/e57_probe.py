
import pye57, numpy as np
f = pye57.E57("/Users/radoslawcaban/Downloads/1.e57")
d = f.read_scan(0, colors=True, ignore_missing_fields=True, intensity=False)
x = d["cartesianX"].astype(np.float64); y = d["cartesianY"].astype(np.float64); z = d["cartesianZ"].astype(np.float64)
n = len(x); print(f"pkt {n:,}")

# --- histogram Z: podloga i sufit ---
hist, edges = np.histogram(z, bins=200)
top = np.argsort(hist)[-8:][::-1]
print("\nNAJGLESTSZE POZIOMY Z (piki):")
for i in top[:8]:
    print(f"  z = {edges[i]:+.3f} … {edges[i+1]:+.3f}   {hist[i]:>10,} pkt")

# --- plan: gestosc 2D ---
H, xe, ye = np.histogram2d(x, y, bins=400)
print(f"\nplan: {xe[0]:.2f}…{xe[-1]:.2f} x {ye[0]:.2f}…{ye[-1]:.2f}")
print(f"komorek z punktami: {(H>0).sum()} / {H.size}")
