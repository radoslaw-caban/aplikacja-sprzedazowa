#!/usr/bin/env python3
"""
Pakuje model glTF (pliki .gltf + .bin + tekstury) w jeden plik GLB.

Po co: Poly Haven (CC0) publikuje modele jako glTF z osobnymi plikami,
a nasz GLBLoader czyta pojedynczy plik GLB.

Użycie:
    python3 tools/gltf_to_glb.py model.gltf wyjscie.glb
"""

import base64
import json
import mimetypes
import os
import struct
import sys


def read_uri(base_dir: str, uri: str) -> bytes:
    if uri.startswith("data:"):
        _, payload = uri.split(",", 1)
        return base64.b64decode(payload)
    with open(os.path.join(base_dir, uri), "rb") as handle:
        return handle.read()


def pack(gltf_path: str, out_path: str) -> None:
    base_dir = os.path.dirname(os.path.abspath(gltf_path))
    with open(gltf_path, "r", encoding="utf-8") as handle:
        gltf = json.load(handle)

    blob = bytearray()
    views = gltf.setdefault("bufferViews", [])

    def align() -> None:
        while len(blob) % 4:
            blob.append(0)

    # 1) dane geometrii: sklej wszystkie bufory w jeden i przesuń bufferViews
    for buffer_index, buffer in enumerate(gltf.get("buffers", [])):
        uri = buffer.get("uri")
        if not uri:
            continue
        align()
        offset = len(blob)
        blob.extend(read_uri(base_dir, uri))
        for view in views:
            if view.get("buffer") == buffer_index:
                view["byteOffset"] = view.get("byteOffset", 0) + offset

    # 2) obrazy: dopisz do tego samego bufora i zrób z nich bufferViews
    for image in gltf.get("images", []):
        uri = image.get("uri")
        if not uri:
            continue
        data = read_uri(base_dir, uri)
        align()
        offset = len(blob)
        blob.extend(data)
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(data)})
        image.pop("uri", None)
        image["bufferView"] = len(views) - 1
        if "mimeType" not in image:
            mime, _ = mimetypes.guess_type(uri)
            image["mimeType"] = mime or "image/png"

    align()
    gltf["buffers"] = [{"byteLength": len(blob)}]
    for view in views:
        view["buffer"] = 0

    json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    while len(json_bytes) % 4:
        json_bytes += b" "

    total = 12 + 8 + len(json_bytes) + 8 + len(blob)
    with open(out_path, "wb") as out:
        out.write(b"glTF")
        out.write(struct.pack("<II", 2, total))
        out.write(struct.pack("<I", len(json_bytes)))
        out.write(b"JSON")
        out.write(json_bytes)
        out.write(struct.pack("<I", len(blob)))
        out.write(b"BIN\x00")
        out.write(bytes(blob))

    print(f"{out_path}: {total / 1e6:.2f} MB, obrazów: {len(gltf.get('images', []))}, siatek: {len(gltf.get('meshes', []))}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    pack(sys.argv[1], sys.argv[2])
