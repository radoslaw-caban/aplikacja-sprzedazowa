import pye57, numpy as np
f = pye57.E57("/Users/radoslawcaban/Downloads/1.e57")
d = f.read_scan(0, colors=True, ignore_missing_fields=True, intensity=False)
x = d["cartesianX"].astype(np.float64); y = d["cartesianY"].astype(np.float64); z = d["cartesianZ"].astype(np.float64)
print(f"pkt {len(x):,}")
print(f"PION (z): {z.min():.3f} … {z.max():.3f}   ({z.max()-z.min():.3f} m)")
hist, edges = np.histogram(z, bins=100)
for i in np.argsort(hist)[-4:][::-1]:
    print(f"  z {edges[i]:+.2f}…{edges[i+1]:+.2f}  {hist[i]:>10,}")

floor, ceil = -0.775, 1.766
chars = " .:-=+*#%@"
def amap(mask, label, n=46):
    if mask.sum() == 0:
        print(f"\n{label}: PUSTO"); return
    H, xe, ye = np.histogram2d(x[mask], y[mask], bins=n)
    print(f"\n{label}: {mask.sum():,} pkt   x {xe[0]:.1f}…{xe[-1]:.1f}   y {ye[0]:.1f}…{ye[-1]:.1f}")
    mx = H.max() or 1
    for j in range(n-1, -1, -1):
        print("  " + "".join(chars[min(9, int(H[i,j]/mx*10))] for i in range(n)))

amap((z > ceil-0.45) & (z < ceil-0.03), "PASMO POD SUFITEM (zrodlo konturu)")
amap((z > floor-0.03) & (z < floor+0.35), "PASMO PRZY PODLODZE")
