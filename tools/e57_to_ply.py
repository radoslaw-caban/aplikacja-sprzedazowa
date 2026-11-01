#!/usr/bin/env python3
"""Konwersja E57 -> binarny PLY (xyz+rgb) dla aplikacji sprzedażowej.

Użycie:  python3 tools/e57_to_ply.py skan.e57 skan.ply
Wymaga:  pip3 install pye57 numpy

Dlaczego: E57 (CompressedVector) to skomplikowany format; przeglądarka
wczytuje PLY natywnie i błyskawicznie. Konwersja trwa kilka sekund.
"""
import sys
import numpy as np

def convert(src: str, dst: str) -> None:
    import pye57
    f = pye57.E57(src)
    print(f"Skanów: {f.scan_count}")
    clouds = []
    colors = []
    for i in range(f.scan_count):
        d = f.read_scan(i, colors=True, ignore_missing_fields=True)
        pts = np.stack([d['cartesianX'], d['cartesianY'], d['cartesianZ']], axis=1).astype(np.float32)
        clouds.append(pts)
        if 'colorRed' in d:
            colors.append(np.stack([d['colorRed'], d['colorGreen'], d['colorBlue']], axis=1).astype(np.uint8))
        else:
            colors.append(np.full((len(pts), 3), 160, dtype=np.uint8))
    pts = np.concatenate(clouds)
    cols = np.concatenate(colors)
    n = len(pts)
    dt = np.dtype([('x', '<f4'), ('y', '<f4'), ('z', '<f4'), ('r', 'u1'), ('g', 'u1'), ('b', 'u1')])
    body = np.empty(n, dtype=dt)
    body['x'], body['y'], body['z'] = pts[:, 0], pts[:, 1], pts[:, 2]
    body['r'], body['g'], body['b'] = cols[:, 0], cols[:, 1], cols[:, 2]
    hdr = (
        "ply\nformat binary_little_endian 1.0\n"
        f"comment z {src}\nelement vertex {n}\n"
        "property float x\nproperty float y\nproperty float z\n"
        "property uchar red\nproperty uchar green\nproperty uchar blue\nend_header\n"
    ).encode()
    with open(dst, 'wb') as fh:
        fh.write(hdr)
        fh.write(body.tobytes())
    print(f"OK: {n:,} pkt -> {dst} ({(len(hdr)+n*dt.itemsize)/1e6:.1f} MB)")

if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit("użycie: e57_to_ply.py <wejście.e57> <wyjście.ply>")
    convert(sys.argv[1], sys.argv[2])
