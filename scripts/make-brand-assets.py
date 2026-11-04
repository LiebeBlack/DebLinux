#!/usr/bin/env python3
"""Generate the MAXT_OS brand images.

Pure standard library (no Pillow): a tiny PNG encoder plus a few drawing
primitives, so the assets can be regenerated on any machine.

Outputs:
    config/includes.chroot/etc/calamares/branding/maxt/logo.png
    config/includes.chroot/etc/calamares/branding/maxt/productIcon.png
    config/includes.chroot/etc/calamares/branding/maxt/welcome.png
    config/includes.chroot/usr/share/backgrounds/maxt/wallpaper.png

Run from the repository root: python3 scripts/make-brand-assets.py
"""

import math
import struct
import zlib
from pathlib import Path

BG = (5, 5, 7)
BG_2 = (16, 11, 13)
RED = (255, 59, 59)
CRIMSON = (196, 18, 32)
EMBER = (255, 138, 92)
BLACK_1 = (10, 10, 13)
BLACK_2 = (30, 22, 25)
INK = (244, 245, 248)


def clamp(value, low=0.0, high=1.0):
    return low if value < low else high if value > high else value


class Canvas:
    def __init__(self, width, height, alpha=False):
        self.w = width
        self.h = height
        self.ch = 4 if alpha else 3
        self.buf = bytearray(width * height * self.ch)

    def blend(self, x, y, color, alpha=1.0):
        if alpha <= 0 or x < 0 or y < 0 or x >= self.w or y >= self.h:
            return
        i = (y * self.w + x) * self.ch
        if self.ch == 3:
            for k in range(3):
                self.buf[i + k] = int(self.buf[i + k] + (color[k] - self.buf[i + k]) * alpha)
            return
        dst_a = self.buf[i + 3] / 255.0
        out_a = alpha + dst_a * (1.0 - alpha)
        if out_a <= 0:
            return
        for k in range(3):
            self.buf[i + k] = int((color[k] * alpha + self.buf[i + k] * dst_a * (1.0 - alpha)) / out_a)
        self.buf[i + 3] = int(out_a * 255)

    def save(self, path):
        stride = self.w * self.ch
        raw = bytearray()
        for y in range(self.h):
            raw.append(0)
            raw += self.buf[y * stride:(y + 1) * stride]

        def chunk(kind, data):
            return (struct.pack('>I', len(data)) + kind + data
                    + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff))

        ihdr = struct.pack('>IIBBBBB', self.w, self.h, 8, 6 if self.ch == 4 else 2, 0, 0, 0)
        header = b'\x89PNG\r\n\x1a\n'
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(header + chunk(b'IHDR', ihdr)
                         + chunk(b'IDAT', zlib.compress(bytes(raw), 9))
                         + chunk(b'IEND', b''))
        print('%-58s %4dx%-4d %6.1f KiB' % (path, self.w, self.h, path.stat().st_size / 1024))


def gradient(canvas, top, bottom):
    for y in range(canvas.h):
        t = y / max(1, canvas.h - 1)
        color = bytes(int(top[k] + (bottom[k] - top[k]) * t) for k in range(3))
        start = y * canvas.w * 3
        canvas.buf[start:start + canvas.w * 3] = color * canvas.w


def glow(canvas, cx, cy, radius, color, strength):
    x0, x1 = max(0, int(cx - radius)), min(canvas.w, int(cx + radius) + 1)
    y0, y1 = max(0, int(cy - radius)), min(canvas.h, int(cy + radius) + 1)
    for y in range(y0, y1):
        dy = y + 0.5 - cy
        for x in range(x0, x1):
            dist = math.hypot(x + 0.5 - cx, dy)
            if dist < radius:
                t = 1.0 - dist / radius
                canvas.blend(x, y, color, strength * t * t)


def segment(canvas, x1, y1, x2, y2, width, color, alpha=1.0):
    half = width / 2.0
    pad = half + 1.5
    x0, x1b = max(0, int(min(x1, x2) - pad)), min(canvas.w, int(max(x1, x2) + pad) + 1)
    y0, y1b = max(0, int(min(y1, y2) - pad)), min(canvas.h, int(max(y1, y2) + pad) + 1)
    vx, vy = x2 - x1, y2 - y1
    length2 = vx * vx + vy * vy
    for y in range(y0, y1b):
        py = y + 0.5
        for x in range(x0, x1b):
            px = x + 0.5
            if length2 == 0:
                dist = math.hypot(px - x1, py - y1)
            else:
                t = clamp(((px - x1) * vx + (py - y1) * vy) / length2)
                dist = math.hypot(px - (x1 + t * vx), py - (y1 + t * vy))
            coverage = clamp(half + 0.5 - dist)
            if coverage > 0:
                canvas.blend(x, y, color, alpha * coverage)


def ring(canvas, cx, cy, radius, width, color, alpha):
    outer = radius + width / 2.0 + 1.0
    x0, x1 = max(0, int(cx - outer)), min(canvas.w, int(cx + outer) + 1)
    y0, y1 = max(0, int(cy - outer)), min(canvas.h, int(cy + outer) + 1)
    for y in range(y0, y1):
        for x in range(x0, x1):
            dist = abs(math.hypot(x + 0.5 - cx, y + 0.5 - cy) - radius)
            coverage = clamp(width / 2.0 + 0.5 - dist)
            if coverage > 0:
                canvas.blend(x, y, color, alpha * coverage)


def grid(canvas, step, color, alpha):
    for x in range(0, canvas.w, step):
        for y in range(canvas.h):
            canvas.blend(x, y, color, alpha)
    for y in range(0, canvas.h, step):
        for x in range(canvas.w):
            canvas.blend(x, y, color, alpha)


def vignette(canvas, strength):
    cx, cy = canvas.w / 2.0, canvas.h / 2.0
    max_dist = math.hypot(cx, cy)
    for y in range(canvas.h):
        dy = y + 0.5 - cy
        for x in range(canvas.w):
            t = math.hypot(x + 0.5 - cx, dy) / max_dist
            factor = 1.0 - strength * t * t
            i = (y * canvas.w + x) * 3
            for k in range(3):
                canvas.buf[i + k] = int(canvas.buf[i + k] * factor)


def rounded_square(canvas, x0, y0, size, radius, top, bottom, alpha=1.0):
    cx, cy = x0 + size / 2.0, y0 + size / 2.0
    half = size / 2.0
    x_start, x_end = max(0, int(x0) - 1), min(canvas.w, int(x0 + size) + 2)
    y_start, y_end = max(0, int(y0) - 1), min(canvas.h, int(y0 + size) + 2)
    for y in range(y_start, y_end):
        for x in range(x_start, x_end):
            qx = abs(x + 0.5 - cx) - (half - radius)
            qy = abs(y + 0.5 - cy) - (half - radius)
            dist = (math.hypot(max(qx, 0.0), max(qy, 0.0))
                    + min(max(qx, qy), 0.0) - radius)
            coverage = clamp(0.5 - dist)
            if coverage <= 0:
                continue
            t = clamp(((x + 0.5 - x0) + (y + 0.5 - y0)) / (2.0 * size))
            color = tuple(int(top[k] + (bottom[k] - top[k]) * t) for k in range(3))
            canvas.blend(x, y, color, alpha * coverage)


def draw_m(canvas, x0, y0, size, thickness, color, alpha=1.0):
    left = x0 + size * 0.12
    right = x0 + size * 0.88
    top = y0 + size * 0.12
    bottom = y0 + size * 0.88
    midx = x0 + size * 0.50
    # Vertex sits on the baseline so the mark reads as an M, not a V with tails.
    midy = y0 + size * 0.87
    segment(canvas, left, bottom, left, top, thickness, color, alpha)
    segment(canvas, left, top, midx, midy, thickness, color, alpha)
    segment(canvas, midx, midy, right, top, thickness, color, alpha)
    segment(canvas, right, top, right, bottom, thickness, color, alpha)


def make_logo(size, path):
    canvas = Canvas(size, size, alpha=True)
    pad = size * 0.055
    # Red rim drawn as a real outline, then a near-black tile on top.
    rounded_square(canvas, pad, pad, size - 2 * pad, size * 0.205, RED, RED)
    rounded_square(canvas, pad + 2.5, pad + 2.5, size - 2 * pad - 5, size * 0.20,
                   BLACK_1, BLACK_2)
    draw_m(canvas, pad, pad, size - 2 * pad, size * 0.088, RED)
    canvas.save(path)


def make_welcome(path, width=840, height=420):
    canvas = Canvas(width, height)
    gradient(canvas, BG, BG_2)
    glow(canvas, width * 0.18, height * 0.12, height * 0.95, CRIMSON, 0.60)
    glow(canvas, width * 0.92, height * 0.85, height * 0.8, RED, 0.30)
    grid(canvas, 60, INK, 0.018)
    for radius in (150, 220, 290, 360):
        ring(canvas, width * 0.90, height * 0.30, radius, 1.2, RED, 0.10)
    make_logo_tile(canvas, width * 0.09, height * 0.235, height * 0.53)
    # Accent underline that hints at the wordmark.
    segment(canvas, width * 0.44, height * 0.68, width * 0.79, height * 0.68, 3, RED, 0.9)
    segment(canvas, width * 0.44, height * 0.72, width * 0.66, height * 0.72, 3, EMBER, 0.55)
    vignette(canvas, 0.35)
    canvas.save(path)


def make_logo_tile(canvas, x, y, size):
    rounded_square(canvas, x, y, size, size * 0.22, RED, RED)
    rounded_square(canvas, x + size * 0.012, y + size * 0.012,
                   size * 0.976, size * 0.212, BLACK_1, BLACK_2)
    draw_m(canvas, x, y, size, size * 0.088, RED)


def make_wallpaper(path, width=1920, height=1080):
    canvas = Canvas(width, height)
    gradient(canvas, BG, BG_2)
    glow(canvas, width * 0.20, height * 0.10, height * 1.05, CRIMSON, 0.55)
    glow(canvas, width * 0.88, height * 0.78, height * 0.95, RED, 0.30)
    glow(canvas, width * 0.55, height * 1.05, height * 0.7, EMBER, 0.12)
    grid(canvas, 80, INK, 0.030)
    for radius in (240, 360, 480, 600, 720):
        ring(canvas, width * 0.78, height * 0.46, radius, 1.4, RED, 0.085)
    draw_m(canvas, width * 0.55, height * 0.35, height * 0.72, height * 0.055, RED, 0.075)
    vignette(canvas, 0.55)
    canvas.save(path)


def main():
    root = Path(__file__).resolve().parent.parent
    branding = root / 'config/includes.chroot/etc/calamares/branding/maxt'
    backgrounds = root / 'config/includes.chroot/usr/share/backgrounds/maxt'

    print('Generating MAXT_OS brand assets')
    make_logo(512, branding / 'logo.png')
    make_logo(128, branding / 'productIcon.png')
    make_welcome(branding / 'welcome.png')
    make_wallpaper(backgrounds / 'wallpaper.png')


if __name__ == '__main__':
    main()
