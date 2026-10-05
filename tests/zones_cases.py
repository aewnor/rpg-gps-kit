"""Zonas poligonales y retoques del mapa (tools/zones.py), sobre un mapa sintético."""
import json
import os
import sys
import tempfile

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
import zones  # noqa: E402

fails = 0


def check(cond, msg):
    global fails
    print(('OK   ' if cond else 'FAIL ') + msg)
    fails += 0 if cond else 1


tiles = zones._tiles()
# máscara: triángulo
m = zones.poly_mask({'w': 8, 'h': 6, 'poly': [[0, 0], [8, 0], [0, 6]]})
check(m[0, 0] and not m[5, 7] and m.sum() == 24, f'máscara poligonal ({m.sum()} celdas)')
check(zones.poly_mask({'w': 3, 'h': 2}).all(), 'sin forma: todo el rectángulo')

# retoques: una casilla de agua, un muro y un borrado, conservando el bit de puente
W = H = 10
mm = {'scene': 'overworld', 'width': W, 'height': H, 'flips': {}, 'objects': [],
      'layers': {'ground': np.full((H, W), tiles['g_grass_0']['id'] + 1, np.int32),
                 'structures': np.zeros((H, W), np.int32)},
      'coll': np.zeros((H, W), np.uint8)}
mm['coll'][2, 2] = 4  # transitable a nivel 1 (puente)
mm['layers']['structures'][4, 4] = tiles['w_stone_0']['id'] + 1
mm['coll'][4, 4] = 1
edits = {'cells': {'1,1': {'ground': 'pool_0_0'}, '2,2': {'structures': 'w_stone_0'}, '4,4': {'structures': ''}}}
with tempfile.NamedTemporaryFile('w', suffix='.json', delete=False) as f:
    json.dump(edits, f)
zones.MAP_EDITS = f.name
n, errs = zones.apply_map_edits(mm, tiles)
check(n == 3 and not errs, f'3 retoques aplicados ({n}, {errs})')
check(mm['coll'][1, 1] == 2, 'agua pintada → colisión agua')
check(mm['coll'][2, 2] == 5, 'muro sobre puente → sólido a nivel 0 y conserva el bit del puente')
check(mm['coll'][4, 4] == 0 and mm['layers']['structures'][4, 4] == 0, 'muro borrado → transitable')
os.unlink(f.name)
print('TODAS LAS PRUEBAS DE ZONAS OK' if not fails else f'{fails} FALLOS')
sys.exit(1 if fails else 0)
