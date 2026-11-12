import pye57, numpy as np
f = pye57.E57("/Users/radoslawcaban/Downloads/1.e57")
d = f.read_scan(0, colors=True, ignore_missing_fields=True, intensity=False)
x = d["cartesianX"].astype(np.float64); y = d["cartesianY"].astype(np.float64); z = d["cartesianZ"].astype(np.float64)

band = (z >= 1.766-0.42) & (z <= 1.766-0.02)
bx, by = x[band], y[band]
print(f"pasmo: {band.sum():,} pkt")
print(f"x {bx.min():.2f}…{bx.max():.2f}  y {by.min():.2f}…{by.max():.2f}")

# gestosc: ile komorek 3 cm zajetych
for cell in (0.03, 0.05, 0.10):
    ix = np.floor(bx/cell).astype(np.int64); iy = np.floor(by/cell).astype(np.int64)
    keys = ix.astype(np.int64)*100000 + iy
    u = len(np.unique(keys))
    span_x = (bx.max()-bx.min())/cell; span_y = (by.max()-by.min())/cell
    print(f"  cell {cell:.2f} m: {u:,} zajetych z {int(span_x*span_y):,} ({100*u/(span_x*span_y):.1f}%)")

# rozklad: czy sa dziury w pasmie
H, xe, ye = np.histogram2d(bx, by, bins=(60,60))
occ = (H>0)
print(f"\ngestosc 60x60: {occ.sum()}/{occ.size} = {100*occ.mean():.1f}% zajetych")
# jak wyglada mapa zajetosci
for j in range(59,-1,-1):
    print("  " + "".join("#" if H[i,j]>0 else "." for i in range(60)))
