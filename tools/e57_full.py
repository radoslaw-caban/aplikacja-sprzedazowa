import pye57, numpy as np
f = pye57.E57("/Users/radoslawcaban/Downloads/1.e57")
d = f.read_scan(0, colors=True, ignore_missing_fields=True, intensity=False)
x = d["cartesianX"].astype(np.float64); y = d["cartesianY"].astype(np.float64); z = d["cartesianZ"].astype(np.float64)
print(f"PELNY obrys: x {x.min():.2f}…{x.max():.2f}  y {y.min():.2f}…{y.max():.2f}  z {z.min():.2f}…{z.max():.2f}")

# gdzie jest wiekszosc punktow? srodek ciezkosci i mediana
print(f"mediana x {np.median(x):.2f}  y {np.median(y):.2f}  z {np.median(z):.2f}")

# mapa CALEGO skanu w rzucie (wszystkie wysokosci)
cell=0.08
ix=np.floor(x/cell).astype(np.int64); iy=np.floor(y/cell).astype(np.int64)
ix-=ix.min(); iy-=iy.min()
W,H=int(ix.max())+1,int(iy.max())+1
g=np.zeros((W,H),bool); g[ix,iy]=True
print(f"\nRZUT CALEGO SKANU ({W}x{H} komorek {cell} m):")
for j in range(H-1,-1,-1):
    print("  "+"".join("#" if g[i,j] else "." for i in range(0,W,2)))
