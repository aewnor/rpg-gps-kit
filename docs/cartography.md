# Cartografía y rejilla

## Fuentes
`cartography/municipio.osm.gz` (extracto OSM), `cartography/limite.osm.gz` (relación 345490),
`cartography/world-plan.json` y `cartography/puntos-interes.csv` (anclas del plan). Fecha: 2026-10-02.

## Proyección
Local equirectangular esférica (`tools/osmlib.py`): R = 6 371 000 m,
`tile_x = floor((lon − 1.425) · k_lon / 4)`, `tile_y = floor((41.215 − lat) · k_lat / 4)`,
`k_lat = πR/180`, `k_lon = k_lat · cos(41.1875°)`. **4 m por tile** (`M_PER_TILE`), atlas
1600 × 1600 tiles, chunks 32 × 32, origen noroeste. Fuera del rectángulo descargado el terreno
está bloqueado.

Cambio respecto al plan (2026-10-02, a petición de el pare): a 10 m/tile, con calles ensanchadas a
2–4 tiles, el trazado no se reconocía. Ahora cada vía usa su anchura real aproximada en metros
(`HIGHWAY` en `semantic.py`) y cada vía férrea OSM es **una** vía de 1 tile (antes se dibujaban
dos carriles dobles por vía). Las anclas del plan (a 10 m/tile) se recalculan desde lon/lat.

## Proceso (`make maps`)
1. `semantic.py`: rasteriza OSM con supermuestreo ×4 en clases de suelo y de detalle **por nivel**
   (−1 túnel, 0, +1 puente) a partir de `bridge`, `tunnel`, `layer`, `covered`. Anchuras reales en metros
   (mínimo 1 tile). Las conexiones solo diagonales se cierran (4-conectividad).
2. `import_osm.py`: edificios (mínimo tejado + fachada), casas generadas en manzanas residenciales
   sin huella OSM (marcadas `generated`), hitos, muros, árboles, autotiles, colisión, rampas,
   objetos y rutas. Escribe `maps/source/overworld.tmj` (Tiled, JSON sin comprimir).
3. `make_caves.py`: escena ficticia `cova_pedrera.tmj`.
4. `compile_maps.py`: TMJ → chunks Lua en `maps/runtime/<escena>/`.
5. `validate_content.py`: rutas peatonales, cruces a distinto nivel, costa, ferrocarril, textos.

## Colisión (capa `collision`, tileset `collision.tsj`)
| bits | significado |
|---|---|
| 0–1 | nivel 0: 0 transitable, 1 sólido, 2 agua, 3 peligro (autopista) |
| 4 | transitable a nivel 1 (tablero de puente) |
| 8 | transitable a nivel −1 (paso inferior) |
| 16 | rampa: cambio de nivel |
| 32 | geometría pendiente de revisión (bloqueada) |

Regla de movimiento (`src/world/collision.lua` = `tools/walkgraph.py`): se conserva el nivel salvo
en rampas; al salir de una rampa se prefiere el nivel del puente/túnel. Las rampas se colocan en
los extremos de cada puente/túnel transitable, **nunca** sobre la huella (dilatada) de lo que
cruza sin compartir nodo. Si un extremo cae dentro de la vía ensanchada, el paso se prolonga en
su dirección hasta salir (lo registra `import-report.json`).

## Simplificaciones registradas
- Escala de 10 m/tile: posiciones relativas fieles; edificios y personas simbólicos.
- Casco antiguo (radio 22 tiles alrededor de Sant Bartomeu): calles residenciales como pavimento.
- Hitos colocados en el hueco libre más cercano a su ancla (desplazamiento en `import-report.json`);
  su acceso peatonal artístico se dibuja si falta (aviso en el informe).
- `map-overrides.json`: conexiones, desplazamientos de hitos y rampas manuales (vacío por ahora:
  ninguna ruta del recorrido lo ha necesitado).
- Ortofoto ICGC no utilizada todavía: pendiente para revisar vegetación y accesos.
