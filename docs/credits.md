# Créditos

## Cartografía
- Datos geográficos © [OpenStreetMap](https://www.openstreetmap.org/copyright) y sus colaboradores,
  bajo licencia ODbL 1.0. Extracto del rectángulo 1.425–1.500 E / 41.160–41.215 N y
  [relación 345490](https://www.openstreetmap.org/relation/345490) (límite municipal), descargados el
  2 de octubre de 2026. El mapa del juego es una obra derivada simplificada (4 m por tile).
- Ortofoto PNOA y Modelo Digital del Terreno MDT05: © Instituto Geográfico Nacional (scne.es),
  CC BY 4.0. Usados para clasificar suelo, árboles y color de tejados, y para los niveles de terreno.
- Ortofoto PNOA de máxima resolución (placas solares, `tools/solar_detect.py`): PNOA cedido por © Instituto
  Geográfico Nacional (CC BY 4.0), WMS `https://www.ign.es/wms-inspire/pnoa-ma`.
- Edificios y piscinas: © Dirección General del Catastro (servicio INSPIRE de edificios), municipios
  de Roda de Berà, Creixell, Bonastre, El Vendrell y La Pobla de Montornès; descargados el 2 de
  octubre de 2026.
- Plano turístico municipal de Roda de Berà: solo contraste visual (no se ha copiado contenido).

## Arte, música y texto
- Tiles, sprites, hitos, vehículos y minimapa: originales, generados por `tools/make_tiles.py`,
  `tools/make_sprites.py` y `tools/make_minimap.py` (paleta de 32 colores en `tools/pixel.py`).
- Música y efectos: originales, sintetizados en `src/audio.lua` al arrancar.
- Personajes, diálogos y misiones: ficticios. La Cova de la Pedrera es inventada.
- Lugares reales: Sant Bartomeu, Arc de Berà, Roc de Sant Gaietà, Ermita de la Mare de Déu de Berà,
  Pedrera de l'Elies, Torre del Cucurull, Mirador del Pujol de la Morella, Roda de Mar.

## Tipografía
- [GNU Unifont](https://unifoundry.com/unifont/) (8 × 16), SIL Open Font License 1.1 / GPLv2+ con
  excepción de fuentes; convertida a fuente bitmap por `tools/make_sprites.py`.

## Motor
- [LÖVE 11.5](https://love2d.org/) (zlib/libpng).
