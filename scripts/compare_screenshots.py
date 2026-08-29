#!/usr/bin/env python3
"""Stdlib-only PNG comparison: decode RGBA/RGB PNGs, pixel diff, write diff PNG."""
import struct
import zlib
from pathlib import Path
import sys

_PNG_SIG = b"\x89PNG\r\n\x1a\n"


def _read_chunks(data: bytes):
    if not data.startswith(_PNG_SIG):
        raise ValueError("not a PNG")
    offset = len(_PNG_SIG)
    chunks = []
    while offset < len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        ctype = data[offset + 4:offset + 8].decode("ascii", "replace")
        cdata = data[offset + 8:offset + 8 + length]
        chunks.append((ctype, cdata))
        offset += 8 + length + 4
    return chunks


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def decode_png(path: str):
    """Return (width, height, rgba_bytes) for an 8-bit RGB/RGBA PNG."""
    data = Path(path).read_bytes()
    chunks = _read_chunks(data)
    width = height = bit_depth = color_type = 0
    idat = bytearray()
    for ctype, cdata in chunks:
        if ctype == "IHDR":
            width, height, bit_depth, color_type = struct.unpack(">IIBB", cdata[:10])
        elif ctype == "IDAT":
            idat += cdata
    if bit_depth != 8:
        raise ValueError("only 8-bit PNG supported")
    channels = {2: 3, 6: 4}.get(color_type)
    if channels is None:
        raise ValueError("only color type 2 (RGB) or 6 (RGBA) supported")
    raw = zlib.decompress(bytes(idat))
    stride = width * channels
    out = bytearray(width * height * 4)
    prev_row = bytearray(stride)
    pos = 0
    for y in range(height):
        ftype = raw[pos]; pos += 1
        row = bytearray(raw[pos:pos + stride]); pos += stride
        for x in range(stride):
            a = row[x - channels] if x >= channels else 0
            b = prev_row[x]
            c = prev_row[x - channels] if x >= channels else 0
            if ftype == 1:
                row[x] = (row[x] + a) & 0xFF
            elif ftype == 2:
                row[x] = (row[x] + b) & 0xFF
            elif ftype == 3:
                row[x] = (row[x] + ((a + b) >> 1)) & 0xFF
            elif ftype == 4:
                row[x] = (row[x] + _paeth(a, b, c)) & 0xFF
        for x in range(width):
            r = row[x * channels]
            g = row[x * channels + 1]
            bl = row[x * channels + 2]
            al = row[x * channels + 3] if channels == 4 else 255
            o = (y * width + x) * 4
            out[o] = r; out[o + 1] = g; out[o + 2] = bl; out[o + 3] = al
        prev_row = row
    return width, height, bytes(out)


def encode_png(width: int, height: int, rgba: bytes) -> bytes:
    """Encode an RGBA byte buffer as a filter-type-0 PNG (for self-test + diff)."""
    def chunk(ctype: bytes, body: bytes) -> bytes:
        return (struct.pack(">I", len(body)) + ctype + body
                + struct.pack(">I", zlib.crc32(ctype + body) & 0xFFFFFFFF))
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        raw += rgba[y * stride:(y + 1) * stride]
    idat = zlib.compress(bytes(raw), 9)
    return _PNG_SIG + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")


def compare(baseline: str, current: str, threshold: float = 0.02) -> dict:
    w1, h1, a = decode_png(baseline)
    w2, h2, b = decode_png(current)
    if (w1, h1) != (w2, h2):
        return {"changed_pixel_ratio": 1.0, "max_delta": 255,
                "diff_image_path": None, "regression": True,
                "message": "size mismatch %dx%d vs %dx%d" % (w1, h1, w2, h2)}
    total = w1 * h1
    changed = 0
    max_delta = 0
    diff = bytearray(total * 4)
    for i in range(total):
        o = i * 4
        d = max(abs(a[o] - b[o]), abs(a[o + 1] - b[o + 1]), abs(a[o + 2] - b[o + 2]))
        if d > max_delta:
            max_delta = d
        if d > 0:
            changed += 1
            diff[o] = 255; diff[o + 1] = 0; diff[o + 2] = 0; diff[o + 3] = 255
        else:
            diff[o] = 255; diff[o + 1] = 255; diff[o + 2] = 255; diff[o + 3] = 255
    ratio = changed / total if total else 0.0
    diff_path = None
    if changed > 0:
        diff_path = str(Path(current).with_suffix(".diff.png"))
        Path(diff_path).write_bytes(encode_png(w1, h1, bytes(diff)))
    return {"changed_pixel_ratio": ratio, "max_delta": max_delta,
            "diff_image_path": diff_path, "regression": ratio > threshold}


def _self_test() -> int:
    tmp = Path("test-output/_compare_selftest")
    tmp.mkdir(parents=True, exist_ok=True)
    red = bytes([255, 0, 0, 255] * 8)
    green_one = bytearray(red)
    green_one[4:8] = bytes([0, 255, 0, 255])
    a = tmp / "a.png"; b = tmp / "b.png"
    a.write_bytes(encode_png(4, 2, red))
    b.write_bytes(encode_png(4, 2, bytes(green_one)))
    r1 = compare(str(a), str(a), 0.0)
    r2 = compare(str(a), str(b), 0.0)
    ok = True
    if r1["changed_pixel_ratio"] != 0.0 or r1["regression"]:
        print("FAIL: identical images should be 0% diff"); ok = False
    if r2["changed_pixel_ratio"] <= 0.0 or not r2["regression"]:
        print("FAIL: modified image should be non-zero diff and a regression"); ok = False
    if r2["diff_image_path"] is None or not Path(r2["diff_image_path"]).exists():
        print("FAIL: diff image not written"); ok = False
    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(_self_test())
    print("usage: compare_screenshots.py --self-test  (import compare() for library use)")
    sys.exit(0)
