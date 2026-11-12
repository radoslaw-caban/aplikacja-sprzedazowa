
import pye57, numpy as np, sys
f = pye57.E57("/Users/radoslawcaban/Downloads/1.e57")
print("skany:", f.scan_count)
tot = 0
for i in range(f.scan_count):
    h = f.get_header(i)
    print(f"  skan {i}: {h.point_count:,} pkt, guid={h.guid[:8] if hasattr(h,'guid') else '?'}")
    tot += h.point_count
print("RAZEM:", f"{tot:,}")
# bounding box po przeczytaniu pierwszego skanu (probka)
d = f.read_scan(0, colors=True, ignore_missing_fields=True, intensity=False)
x,y,z = d["cartesianX"], d["cartesianY"], d["cartesianZ"]
print("skan0 pkt:", len(x))
print(f"X {x.min():.3f} … {x.max():.3f}  ({x.max()-x.min():.3f} m)")
print(f"Y {y.min():.3f} … {y.max():.3f}  ({y.max()-y.min():.3f} m)")
print(f"Z {z.min():.3f} … {z.max():.3f}  ({z.max()-z.min():.3f} m)")
print("pola:", list(d.keys())[:14])
