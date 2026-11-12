import pye57, numpy as np
f = pye57.E57("/Users/radoslawcaban/Downloads/1.e57")
d = f.read_scan(0, colors=True, ignore_missing_fields=True, intensity=False)
x = d["cartesianX"].astype(np.float64); y = d["cartesianY"].astype(np.float64); z = d["cartesianZ"].astype(np.float64)
band = (z >= 1.766-0.42) & (z <= 1.766-0.02)
bx, by = x[band], y[band]

cell = 0.03
ix = np.floor(bx/cell).astype(np.int64); iy = np.floor(by/cell).astype(np.int64)
ix -= ix.min(); iy -= iy.min()
W, H = int(ix.max())+1, int(iy.max())+1
g = np.zeros((W,H), dtype=bool); g[ix,iy]=True

def dilate(a, r):
    out = a.copy()
    for dx in range(-r,r+1):
        for dy in range(-r,r+1):
            out |= np.roll(np.roll(a,dx,0),dy,1)
    return out

from collections import deque
def flood(solid):
    # zalewanie od brzegu po komorkach NIE-sciana
    W2,H2 = solid.shape
    seen = np.zeros_like(solid)
    q = deque()
    for i in range(W2):
        for j in (0,H2-1):
            if not solid[i,j] and not seen[i,j]: seen[i,j]=True; q.append((i,j))
    for j in range(H2):
        for i in (0,W2-1):
            if not solid[i,j] and not seen[i,j]: seen[i,j]=True; q.append((i,j))
    while q:
        i,j = q.popleft()
        for di,dj in ((1,0),(-1,0),(0,1),(0,-1)):
            a,b = i+di, j+dj
            if 0<=a<W2 and 0<=b<H2 and not solid[a,b] and not seen[a,b]:
                seen[a,b]=True; q.append((a,b))
    return seen

for r in (1,2,3,4):
    s = dilate(g,r)
    out = flood(s)
    interior = (~s) & (~out)
    print(f"r={r}: sciany {100*s.mean():.1f}%  zewnetrze {100*out.mean():.1f}%  WNETRZE {100*interior.mean():.2f}%")
    if r==1:
        print("   mapa wnetrza (W=wewnatrz, #=sciana, .=zewnatrz):")
        for j in range(H-1,-1,-1):
            row = ""
            for i in range(0,W,2):
                row += "W" if interior[i,j] else ("#" if s[i,j] else ".")
            print("   " + row)
