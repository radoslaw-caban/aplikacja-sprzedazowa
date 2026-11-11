#!/usr/bin/env python3
"""
Decimacja GLB metodą klasteryzacji wierzchołków — do LOD.

Dlaczego: model drzewa z Poly Haven ma 1,07 mln trójkątów. W oddali taki
detal jest niewidoczny, a kosztuje tyle samo. Klasteryzacja (grupowanie
wierzchołków w komórki siatki) daje mniejszą siatkę zachowującą sylwetkę.

Użycie:
    python3 tools/decimate_glb.py IslandTree.glb IslandTree_LOD1.glb 0.010
    python3 tools/decimate_glb.py IslandTree.glb IslandTree_LOD2.glb 0.030

Ostatni argument: rozmiar komórki jako ułamek przekątnej bryły.
"""

import json
import struct
import sys

COMPONENT = {5121: ("B", 1), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
TYPE_COUNT = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def load_glb(path):
    data = open(path, "rb").read()
    _, _, _ = struct.unpack_from("<III", data, 0)
    offset = 12
    chunks = {}
    while offset + 8 <= len(data):
        length, kind = struct.unpack_from("<II", data, offset)
        chunks[kind] = data[offset + 8: offset + 8 + length]
        offset += 8 + length
    gltf = json.loads(chunks[0x4E4F534A])
    return gltf, chunks[0x004E4942]


def read_accessor(gltf, binary, index):
    acc = gltf["accessors"][index]
    view = gltf["bufferViews"][acc["bufferView"]]
    fmt, size = COMPONENT[acc["componentType"]]
    comps = TYPE_COUNT[acc["type"]]
    base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = view.get("byteStride") or size * comps
    out = []
    for i in range(acc["count"]):
        values = struct.unpack_from("<" + fmt * comps, binary, base + i * stride)
        out.append(values if comps > 1 else values[0])
    return out


def decimate(positions, normals, uvs, indices, cell):
    lo = [min(p[i] for p in positions) for i in range(3)]
    buckets = {}
    remap = [0] * len(positions)

    for i, p in enumerate(positions):
        key = (
            int((p[0] - lo[0]) / cell),
            int((p[1] - lo[1]) / cell),
            int((p[2] - lo[2]) / cell),
        )
        bucket = buckets.get(key)
        if bucket is None:
            buckets[key] = {"i": len(buckets), "n": 0, "p": [0.0, 0.0, 0.0], "nr": [0.0, 0.0, 0.0], "uv": [0.0, 0.0]}
            bucket = buckets[key]
        remap[i] = bucket["i"]
        bucket["n"] += 1
        for k in range(3):
            bucket["p"][k] += p[k]
            bucket["nr"][k] += normals[i][k] if normals else 0.0
        if uvs:
            bucket["uv"][0] += uvs[i][0]
            bucket["uv"][1] += uvs[i][1]

    count = len(buckets)
    new_pos = [None] * count
    new_nor = [None] * count
    new_uv = [None] * count
    for bucket in buckets.values():
        n = bucket["n"]
        new_pos[bucket["i"]] = [c / n for c in bucket["p"]]
        nr = [c / n for c in bucket["nr"]]
        length = sum(c * c for c in nr) ** 0.5 or 1.0
        new_nor[bucket["i"]] = [c / length for c in nr]
        new_uv[bucket["i"]] = [c / n for c in bucket["uv"]]

    new_indices = []
    seen = set()
    for t in range(0, len(indices), 3):
        a, b, c = remap[indices[t]], remap[indices[t + 1]], remap[indices[t + 2]]
        if a == b or b == c or a == c:
            continue                       # zdegenerowany po klasteryzacji
        key = tuple(sorted((a, b, c)))
        if key in seen:
            continue
        seen.add(key)
        new_indices += [a, b, c]

    return new_pos, new_nor, new_uv, new_indices


def build(gltf, binary, out_path, fraction):
    positions_all = []
    for mesh in gltf["meshes"]:
        for prim in mesh["primitives"]:
            positions_all += read_accessor(gltf, binary, prim["attributes"]["POSITION"])
    lo = [min(p[i] for p in positions_all) for i in range(3)]
    hi = [max(p[i] for p in positions_all) for i in range(3)]
    diagonal = sum((hi[i] - lo[i]) ** 2 for i in range(3)) ** 0.5
    cell = diagonal * fraction
    print(f"przekątna {diagonal:.3f} m, komórka {cell * 1000:.1f} mm")

    blob = bytearray()
    views = []
    accessors = []

    def push(data, alignment=4):
        while len(blob) % alignment:
            blob.append(0)
        offset = len(blob)
        blob.extend(data)
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(data)})
        return len(views) - 1

    # obrazy: kopiujemy bez zmian
    for image in gltf.get("images", []):
        view = gltf["bufferViews"][image["bufferView"]]
        start = view.get("byteOffset", 0)
        data = binary[start:start + view["byteLength"]]
        image["bufferView"] = push(bytes(data))

    primitives = []
    total_tris = 0
    for mesh in gltf["meshes"]:
        for prim in mesh["primitives"]:
            attrs = prim["attributes"]
            positions = read_accessor(gltf, binary, attrs["POSITION"])
            normals = read_accessor(gltf, binary, attrs["NORMAL"]) if "NORMAL" in attrs else None
            uvs = read_accessor(gltf, binary, attrs["TEXCOORD_0"]) if "TEXCOORD_0" in attrs else None
            indices = read_accessor(gltf, binary, prim["indices"]) if "indices" in prim else list(range(len(positions)))

            new_pos, new_nor, new_uv, new_idx = decimate(positions, normals, uvs, indices, cell)
            if not new_idx:
                continue
            total_tris += len(new_idx) // 3

            pos_view = push(struct.pack("<" + "f" * (len(new_pos) * 3), *[c for p in new_pos for c in p]))
            accessors.append({"bufferView": pos_view, "componentType": 5126, "count": len(new_pos), "type": "VEC3",
                              "min": [min(p[i] for p in new_pos) for i in range(3)],
                              "max": [max(p[i] for p in new_pos) for i in range(3)]})
            pos_accessor = len(accessors) - 1

            nor_accessor = None
            if new_nor:
                nor_view = push(struct.pack("<" + "f" * (len(new_nor) * 3), *[c for n in new_nor for c in n]))
                accessors.append({"bufferView": nor_view, "componentType": 5126, "count": len(new_nor), "type": "VEC3"})
                nor_accessor = len(accessors) - 1

            uv_accessor = None
            if new_uv:
                uv_view = push(struct.pack("<" + "f" * (len(new_uv) * 2), *[c for uv in new_uv for c in uv]))
                accessors.append({"bufferView": uv_view, "componentType": 5126, "count": len(new_uv), "type": "VEC2"})
                uv_accessor = len(accessors) - 1

            idx_view = push(struct.pack("<" + "I" * len(new_idx), *new_idx))
            accessors.append({"bufferView": idx_view, "componentType": 5125, "count": len(new_idx), "type": "SCALAR"})
            idx_accessor = len(accessors) - 1

            new_attrs = {"POSITION": pos_accessor}
            if nor_accessor is not None:
                new_attrs["NORMAL"] = nor_accessor
            if uv_accessor is not None:
                new_attrs["TEXCOORD_0"] = uv_accessor

            primitives.append({"attributes": new_attrs, "indices": idx_accessor, "material": prim.get("material", 0)})

    out = {
        "asset": {"version": "2.0", "generator": "decimate_glb.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0}],
        "meshes": [{"primitives": primitives}],
        "materials": gltf.get("materials", []),
        "textures": gltf.get("textures", []),
        "images": gltf.get("images", []),
        "samplers": gltf.get("samplers", []),
        "bufferViews": views,
        "accessors": accessors,
        "buffers": [{"byteLength": len(blob)}],
    }

    json_bytes = json.dumps(out, separators=(",", ":")).encode("utf-8")
    while len(json_bytes) % 4:
        json_bytes += b" "
    while len(blob) % 4:
        blob.append(0)
    total = 12 + 8 + len(json_bytes) + 8 + len(blob)
    with open(out_path, "wb") as handle:
        handle.write(b"glTF")
        handle.write(struct.pack("<II", 2, total))
        handle.write(struct.pack("<I", len(json_bytes)))
        handle.write(b"JSON")
        handle.write(json_bytes)
        handle.write(struct.pack("<I", len(blob)))
        handle.write(b"BIN\x00")
        handle.write(bytes(blob))
    print(f"{out_path}: {total / 1e6:.2f} MB, {total_tris} trójkątów")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        print(__doc__)
        sys.exit(1)
    gltf_data, bin_data = load_glb(sys.argv[1])
    build(gltf_data, bin_data, sys.argv[2], float(sys.argv[3]))
