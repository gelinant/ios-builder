#!/usr/bin/env python3
"""Renders the iOS app icon (1024x1024 PNG, no alpha) from the Vela mark.

Same geometry as docs/logo.svg and the Android adaptive icon: a diagonal brand gradient
(#0D3D43 top left to #149387 bottom right) and a two-tone chevron drawn in a 512 space.
iOS masks the corners itself, so the gradient fills the whole square.
Standard library only. Usage: python3 scripts/ios/make-app-icon.py [out.png]
"""
import struct
import sys
import zlib

SIZE = 1024
SCALE = SIZE / 512
BG_START = (0x0D, 0x3D, 0x43)
BG_END = (0x14, 0x93, 0x87)
WHITE = (0xFF, 0xFF, 0xFF)
TEAL = (0x39, 0xE0, 0xC8)
LEFT = [(256, 100), (146, 376), (256, 318)]
RIGHT = [(256, 100), (366, 376), (256, 318)]
DEFAULT_OUT = "iosApp/Vela/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"


def edges(tri):
    """Edge lines (a, b, c) with a*x + b*y + c = signed distance, positive inside."""
    pts = [(x * SCALE, y * SCALE) for x, y in tri]
    area = (pts[1][0] - pts[0][0]) * (pts[2][1] - pts[0][1]) - (pts[2][0] - pts[0][0]) * (pts[1][1] - pts[0][1])
    sign = 1 if area > 0 else -1
    out = []
    for i in range(3):
        (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % 3]
        a, b = -(y1 - y0), x1 - x0
        norm = (a * a + b * b) ** 0.5
        a, b = sign * a / norm, sign * b / norm
        out.append((a, b, -(a * x0 + b * y0)))
    return out


def coverage(lines, x, y):
    d = min(a * x + b * y + c for a, b, c in lines)
    return max(0.0, min(1.0, d + 0.5))


def mix(c0, c1, t):
    return tuple(c0[i] + (c1[i] - c0[i]) * t for i in range(3))


def render():
    left, right = edges(LEFT), edges(RIGHT)
    rows = []
    for py in range(SIZE):
        row = bytearray([0])
        y = py + 0.5
        for px in range(SIZE):
            x = px + 0.5
            color = mix(BG_START, BG_END, (x + y) / (2 * SIZE))
            cl = coverage(left, x, y)
            if cl > 0:
                color = mix(color, WHITE, cl)
            cr = coverage(right, x, y)
            if cr > 0:
                color = mix(color, TEAL, cr)
            row += bytes(int(round(v)) for v in color)
        rows.append(bytes(row))
    return b"".join(rows)


def png(raw):
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_OUT
    with open(out, "wb") as f:
        f.write(png(render()))
