"""Nivells de les vies OSM (python3 tests/levels_cases.py): pas inferior curt, túnel i trinxera llarga."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
import semantic as S

CASES = [
    ({'layer': '-1'}, 7, -1, 'un pas inferior curt (layer=-1) va per sota'),
    ({'layer': '-1'}, 76, 0, 'una trinxera llarga sense tunnel (TV-2041) es queda a nivell del terra'),
    ({'layer': '-1', 'tunnel': 'yes'}, 200, -1, 'un túnel marcat és túnel encara que sigui llarg'),
    ({'layer': '-1', 'covered': 'yes'}, 90, -1, 'una via coberta va per sota'),
    ({'bridge': 'yes'}, 3, 1, 'un pont va per sobre'),
    ({'layer': '1'}, 50, 1, 'layer positiu va per sobre'),
    ({}, 10, 0, 'sense etiquetes, a terra'),
]
for tags, length, want, msg in CASES:
    got = S.way_level(tags, None, length)
    assert got == want, f'{msg}: {got} != {want}'
    print('OK  ', msg)
print('TOTES LES PROVES DE NIVELLS OK')
