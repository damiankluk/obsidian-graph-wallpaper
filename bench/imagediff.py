"""Small dependency-free PNG reader and RGB image comparator for fixtures."""

from __future__ import annotations

import pathlib
import struct
import zlib

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def read_png(path: pathlib.Path) -> dict:
    data = pathlib.Path(path).read_bytes()
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError("not a PNG file")
    offset = len(PNG_SIGNATURE)
    width = height = color_type = bit_depth = interlace = None
    compressed = bytearray()
    while offset < len(data):
        if offset + 12 > len(data):
            raise ValueError("truncated PNG chunk")
        length = struct.unpack_from(">I", data, offset)[0]
        kind = data[offset + 4:offset + 8]
        start, end = offset + 8, offset + 8 + length
        if end + 4 > len(data):
            raise ValueError("truncated PNG chunk data")
        payload = data[start:end]
        expected_crc = struct.unpack_from(">I", data, end)[0]
        if zlib.crc32(kind + payload) & 0xFFFFFFFF != expected_crc:
            raise ValueError("PNG chunk checksum mismatch")
        if kind == b"IHDR":
            width, height, bit_depth, color_type, compression, filtering, interlace = struct.unpack(">IIBBBBB", payload)
            if compression != 0 or filtering != 0:
                raise ValueError("unsupported PNG compression or filter method")
        elif kind == b"IDAT":
            compressed.extend(payload)
        elif kind == b"IEND":
            break
        offset = end + 4
    if not width or not height or bit_depth != 8 or color_type != 6 or interlace != 0:
        raise ValueError("only non-interlaced 8-bit RGBA PNGs are supported")
    raw = zlib.decompress(compressed)
    stride, bpp = width * 4, 4
    if len(raw) != height * (stride + 1):
        raise ValueError("PNG pixel data has an unexpected size")
    pixels = bytearray(height * stride)
    source = 0
    for y in range(height):
        filter_type = raw[source]
        source += 1
        row_start = y * stride
        for x in range(stride):
            value = raw[source + x]
            left = pixels[row_start + x - bpp] if x >= bpp else 0
            above = pixels[row_start - stride + x] if y else 0
            upper_left = pixels[row_start - stride + x - bpp] if y and x >= bpp else 0
            if filter_type == 1:
                value += left
            elif filter_type == 2:
                value += above
            elif filter_type == 3:
                value += (left + above) // 2
            elif filter_type == 4:
                p = left + above - upper_left
                pa, pb, pc = abs(p - left), abs(p - above), abs(p - upper_left)
                predictor = left if pa <= pb and pa <= pc else (above if pb <= pc else upper_left)
                value += predictor
            elif filter_type != 0:
                raise ValueError(f"unsupported PNG row filter {filter_type}")
            pixels[row_start + x] = value & 0xFF
        source += stride
    return {"width": width, "height": height, "pixels": pixels}


def compare(a: dict, b: dict, threshold: int = 0) -> dict:
    if (a["width"], a["height"]) != (b["width"], b["height"]):
        raise ValueError("image dimensions differ")
    width, height = a["width"], a["height"]
    pa, pb = a["pixels"], b["pixels"]
    total = width * height
    sum_abs = max_abs = different = 0
    for i in range(0, len(pa), 4):
        pixel_diff = 0
        for channel in range(3):
            difference = abs(pa[i + channel] - pb[i + channel])
            sum_abs += difference
            max_abs = max(max_abs, difference)
            pixel_diff = max(pixel_diff, difference)
        if pixel_diff > threshold:
            different += 1
    return {"mean_abs": sum_abs / (total * 3), "max_abs": max_abs,
            "differing_fraction": different / total}
