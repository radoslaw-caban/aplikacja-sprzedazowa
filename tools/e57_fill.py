import pye57, numpy as np
f = pye57.E57("/Users/radoslawcaban/Downloads/1.e57")
d = f.read_scan(0, colors=True, ignore_missing_fields=True, intensity=False)
x = d["cartesianX"].astype(np.float64); y = d["cartesianY"].astype(np.float64); z = d["cartesianZ"].astype(np.float64)
band = (z >= 1.766-0.42) & (z <= 1.766-0.02)
bx, by = x[band], y[band]

# ile punktow przypada na 1 m sciany? policz dlugosc linii w mapie zajetosci
for cell in (0.02, 0.03, 0.05):
    ix = np.floor(bx/cell).astype(np.int64); iy = np.floor(by/cell).astype(np.int64)
    keys = np.unique(ix.astype(np.int64)*1000000 + iy)
    print(f"cell {cell}: {len(keys):,} zajetych; ~{len(bx)/max(1,len(keys)):.1f} pkt/komorka")

# A) zageszczenie: dolina -> klucz komorki 3 cm, potem zlicz
cell = 0.03
ix = np.floor(bx/cell).astype(np.int64); iy = np.floor(by/cell).astype(np.int64)
# przesun do nieujemnych
ix -= ix.min(); iy -= iy.min()
W, Hh = ix.max()+1, iy.max()+1
grid = np.zeros((int(W), int(Hh)), dtype=bool)
grid[ix, iy] = True
print(f"\nsiatka {int(W)}x{int(Hh)}  zajetych {grid.sum():,} ({100*grid.mean():.1f}%)")

def dilate(g, r=1):
    out = g.copy()
    for dx in range(-r, r+1):
        for dy in range(-r, r+1):
            out |= np.roll(np.roll(g, dx, axis=0), dy, axis=1)
    return out

for r in (1,2,3,5):
    dg = dilate(grid, r)
    print(f"  po dylatacji r={r}: {100*dg.mean():.1f}% zajetych")
