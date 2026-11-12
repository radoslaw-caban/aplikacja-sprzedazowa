import pye57, numpy as np
from collections import deque
f = pye57.E57("/Users/radoslawcaban/Downloads/1.e57")
d = f.read_scan(0, colors=True, ignore_missing_fields=True, intensity=False)
x = d["cartesianX"].astype(np.float64); y = d["cartesianY"].astype(np.float64); z = d["cartesianZ"].astype(np.float64)

cell = 0.04
def test_band(z0, z1, label):
    m = (z >= z0) & (z <= z1)
    if m.sum() < 1000:
        print(f"{label}: {m.sum()} pkt — za malo"); return None
    bx, by = x[m], y[m]
    ix = np.floor(bx/cell).astype(np.int64); iy = np.floor(by/cell).astype(np.int64)
    ix -= ix.min(); iy -= iy.min()
    W, H = int(ix.max())+1, int(iy.max())+1
    g = np.zeros((W,H), dtype=bool); g[ix,iy]=True
    s = g.copy()
    for dx in (-1,0,1):
        for dy in (-1,0,1):
            s |= np.roll(np.roll(g,dx,0),dy,1)
    seen = np.zeros_like(s); q = deque()
    for i in range(W):
        for j in (0,H-1):
            if not s[i,j]: seen[i,j]=True; q.append((i,j))
    for j in range(H):
        for i in (0,W-1):
            if not s[i,j]: seen[i,j]=True; q.append((i,j))
    while q:
        i,j = q.popleft()
        for di,dj in ((1,0),(-1,0),(0,1),(0,-1)):
            a,b = i+di,j+dj
            if 0<=a<W and 0<=b<H and not s[a,b] and not seen[a,b]:
                seen[a,b]=True; q.append((a,b))
    interior = (~s)&(~seen)
    frac = interior.sum()/interior.size*100
    print(f"{label}: {m.sum():>9,} pkt  sciany {s.sum():>6,}  WNETRZE {frac:.1f}%")
    return interior, s, W, H

floor, ceil = -0.775, 1.766
for (a,b,lab) in [(1.3,1.75,"1.30-1.75 (pod sufitem)"), (0.9,1.3,"0.90-1.30"),
                  (0.4,0.9,"0.40-0.90"), (0.0,0.4,"0.00-0.40"), (-0.7,-0.1,"-0.70--0.10"),
                  (0.2,1.7,"0.20-1.70 (calosc)")]:
    test_band(a,b,lab)
