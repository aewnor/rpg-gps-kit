"""Utilidades de dibujo pixel art sobre arrays RGBA (numpy) con paleta fija."""
import hashlib
import random

import numpy as np
from PIL import Image

# Paleta «Mediterrani d'estiu», calibrada con la ortofoto PNOA (tools/palette_check.py): el tono de cada
# material sale de la mediana real del satélite por clase de suelo (olivos y pinar oliva, tierra ocre
# apagada, mar azul petróleo, asfalto gris cálido claro, tejas descoloridas), con algo más de saturación
# y luz para que se lea a 1×. Tres o cuatro valores por material; luz desde arriba a la izquierda.
PALETTE = {
    'ink': '#1f1a24',       # contorno oscuro selectivo
    'white': '#f6f1e3', 'white2': '#dcd3bf', 'white3': '#b2a790',
    'ochre': '#e3b866', 'ochre2': '#bf8c4a', 'ochre3': '#8a5f34',
    'terra': '#cf6d4c', 'terra2': '#a34a39', 'terra3': '#6b302b',
    'pine': '#9ba45c', 'pine2': '#6d8045', 'pine3': '#4a5f38', 'pine4': '#2c3d2a',
    'dry': '#c9ad7f', 'dry2': '#a68b62', 'dry3': '#806a4a',
    'sand': '#f0e2c0', 'sand2': '#d8c69c',
    'sea': '#4aa3b0', 'sea2': '#2e7a92', 'sea3': '#215873', 'foam': '#ffffff',
    'stone': '#c9bba0', 'stone2': '#a6957a', 'stone3': '#786852',
    'asph': '#85827f', 'asph2': '#6c6a69', 'asph3': '#4a4749',
    'red': '#c9403a', 'blue': '#3d6fc4', 'skin': '#f1c3a1',
    # añadidos: sombra de piel y rubor (personajes), agua de piscina, hierba al sol y mar abierto
    'skin2': '#d39b7e', 'blush': '#eb9f8c', 'pool': '#7fd3d6', 'sun': '#c3c27a', 'deep': '#1b4863',
}
NAMES = list(PALETTE)
assert len(NAMES) == 37, len(NAMES)


def rgba(name, a=255):
    h = PALETTE[name].lstrip('#')
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def mix(c, d, k):
    """Mezcla dos colores (nombre de paleta o tupla RGBA) → tupla RGBA. k = 0 → c, k = 1 → d."""
    a = rgba(c) if isinstance(c, str) else c
    b = rgba(d) if isinstance(d, str) else d
    return tuple(int(round(a[i] * (1 - k) + b[i] * k)) for i in range(3)) + (255,)


def rng_for(*key):
    return random.Random(int(hashlib.md5(repr(key).encode()).hexdigest()[:8], 16))


class Sprite:
    def __init__(self, w, h, fill=None):
        self.w, self.h = w, h
        self.a = np.zeros((h, w, 4), np.uint8)
        if fill:
            self.a[:, :] = rgba(fill)

    def px(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.a[y, x] = rgba(c) if isinstance(c, str) else c

    def rect(self, x, y, w, h, c):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.px(xx, yy, c)

    def hline(self, x0, x1, y, c):
        for x in range(x0, x1 + 1):
            self.px(x, y, c)

    def vline(self, x, y0, y1, c):
        for y in range(y0, y1 + 1):
            self.px(x, y, c)

    def speckle(self, rng, colors, density, region=None):
        x0, y0, w, h = region or (0, 0, self.w, self.h)
        for yy in range(y0, y0 + h):
            for xx in range(x0, x0 + w):
                if rng.random() < density:
                    self.px(xx, yy, rng.choice(colors))

    def blit(self, other, x, y):
        for yy in range(other.h):
            for xx in range(other.w):
                if other.a[yy, xx, 3]:
                    self.px(x + xx, y + yy, tuple(other.a[yy, xx]))

    def pattern(self, x, y, rows, cmap):
        """rows: lista de strings; cada carácter se traduce con cmap (espacio/'.' = transparente)."""
        for j, row in enumerate(rows):
            for i, ch in enumerate(row):
                if ch in cmap:
                    self.px(x + i, y + j, cmap[ch])

    def flip_h(self):
        s = Sprite(self.w, self.h)
        s.a = self.a[:, ::-1].copy()
        return s

    def image(self):
        return Image.fromarray(self.a, 'RGBA')


def sheet(sprites, cols):
    """Monta sprites del mismo tamaño en una hoja."""
    w, h = sprites[0].w, sprites[0].h
    rows = (len(sprites) + cols - 1) // cols
    out = Sprite(w * cols, h * rows)
    for i, s in enumerate(sprites):
        out.a[(i // cols) * h:(i // cols) * h + h, (i % cols) * w:(i % cols) * w + w] = s.a
    return out
