
import pye57, numpy as np, struct
f = pye57.E57("/Users/radoslawcaban/Downloads/1.e57")
d = f.read_scan(0, colors=True, ignore_missing_fields=True, intensity=False)
x = d["cartesianX"].astype(np.float32); y = d["cartesianY"].astype(np.float32); z = d["cartesianZ"].astype(np.float32)
r = d["colorRed"].astype(np.uint8); g = d["colorGreen"].astype(np.uint8); b = d["colorBlue"].astype(np.uint8)
n = len(x)
print(f"pkt {n:,}")

# decymacja do ~2 mln (krok 12) — do testu algorytmu w Swifcie
step = max(1, n // 2_000_000)
idx = np.arange(0, n, step)
print(f"krok {step} -> {len(idx):,} pkt")

hdr = f"""ply
format binary_little_endian 1.0
comment skan Trimble X9 (test)
element vertex {len(idx)}
property float x
property float y
property float z
property uchar red
property uchar green
property uchar blue
end_header
"""
dt = np.dtype([("x","<f4"),("y","<f4"),("z","<f4"),("r","u1"),("g","u1"),("b","u1")])
arr = np.empty(len(idx), dtype=dt)
arr["x"]=x[idx]; arr["y"]=y[idx]; arr["z"]=z[idx]
arr["r"]=r[idx]; arr["g"]=g[idx]; arr["b"]=b[idx]
out = "/Users/radoslawcaban/github/aplikacja-sprzedazowa/app/tools/fixtures/x9-real.ply"
with open(out,"wb") as fh:
    fh.write(hdr.encode()); fh.write(arr.tobytes())
import os
print("zapisano", out, f"{os.path.getsize(out)/1e6:.1f} MB")
