#!/usr/bin/env python3
"""Minimapa 320 × 320 (assets/runtime/minimap.png) y versión detallada para el zoom (minimap_hd.jpg).

Se compone con el color medio real de cada tile (tools/make_overview.py), así el minimapa tiene los
mismos colores que el mapa (y que la ortofoto en la que se calibró la paleta), y encima se trazan las
vías principales con trazo fino para orientarse: autopista, carreteras, calles, paseos y tren.
"""
import os

import numpy as np
from PIL import Image

import make_overview as ov

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
SIZE = 320
HD = 1600   # zoom: com a màxim 1 px per casella (textura <= 2048 per als mòbils)


def main():
    base = ov.render(1, min_classes=set())                     # 1 px por tile, sin vías
    small = base.resize((SIZE, SIZE), Image.BOX)
    lines = ov.render(1, min_classes={'MOTORWAY', 'ROAD_MAIN', 'ROAD', 'PEDESTRIAN', 'RAIL', 'RAIL_HS'},
                      scale_w=False)
    # las vías se reducen por mínimo de luminancia/color dominante: se dibujan aparte a escala final
    a = np.asarray(base, np.int16)
    b = np.asarray(lines, np.int16)
    diff = (np.abs(a - b).sum(-1) > 24)
    F = a.shape[0] // SIZE
    mask = diff.reshape(SIZE, F, SIZE, F).mean((1, 3)) > 0.18
    col = (b * diff[..., None]).reshape(SIZE, F, SIZE, F, 3).sum((1, 3)) / \
        np.maximum(1, diff.reshape(SIZE, F, SIZE, F).sum((1, 3)))[..., None]
    out = np.asarray(small, np.float32)
    out[mask] = col[mask]
    Image.fromarray(out.clip(0, 255).astype(np.uint8)).save(os.path.join(ROOT, 'assets/runtime/minimap.png'))
    print('minimap ok', out.shape)
    # versió detallada per al zoom del mapa M (1 px per casella, amb les vies): JPEG perquè pesi poc al web
    hd = lines.convert('RGB')
    if hd.width > HD:
        hd = hd.resize((HD, HD * hd.height // hd.width), Image.LANCZOS)
    path = os.path.join(ROOT, 'assets/runtime/minimap_hd.jpg')
    hd.save(path, quality=84, optimize=True)
    print('minimap_hd ok', hd.size, os.path.getsize(path) // 1024, 'KB')
    # zoom molt de prop (2026-10-05, «augmenta la resolució del mapa»): 2 px per casella en 2 × 2 trossos de com a
    # molt 1600 px (textures <= 2048 als mòbils); el joc carrega només els que es veuen
    hd2 = ov.render(2, min_classes={'MOTORWAY', 'ROAD_MAIN', 'ROAD', 'PEDESTRIAN', 'RAIL', 'RAIL_HS'}, scale_w=False).convert('RGB')
    hw, hh = hd2.width // 2, hd2.height // 2
    for r in range(2):
        for c in range(2):
            part = hd2.crop((c * hw, r * hh, (c + 1) * hw, (r + 1) * hh))
            if part.width > HD:
                part = part.resize((HD, HD * part.height // part.width), Image.LANCZOS)
            part.save(os.path.join(ROOT, f'assets/runtime/minimap_hd2_{r}_{c}.jpg'), quality=82, optimize=True)
    print('minimap_hd2 ok', hd2.size)


if __name__ == '__main__':
    main()
