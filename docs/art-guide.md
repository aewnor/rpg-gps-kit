# Guía de arte

- Tiles 16 × 16, personajes 16 × 24 (6 columnas: 4 pasos + reposo + parpadeo; filas abajo/arriba/izq/der).
- Resolución lógica 320 × 240, escala entera, filtro `nearest`. Sin antialiasing ni rotaciones
  arbitrarias: vehículos con variantes horizontal, vertical y dos diagonales.
- **Paleta «Mediterrani d'estiu»** (37 colores, `tools/pixel.py`), calibrada con la ortofoto PNOA: el tono de
  cada material sale de la mediana real del satélite por clase de suelo (pinar y olivos oliva, tierra ocre
  apagada, parcelas urbanas de grava beige, mar azul petróleo, asfalto gris cálido, tejas descoloridas), con
  algo más de saturación y luz para leerse a 1×. `make validate` ejecuta `tools/palette_check.py`, que
  compara tono y orden de luminosidad de cada clase con el satélite. `make_tiles.py` escribe la paleta en
  `data/palette.json`, que usan el dibujo vectorial de calles (`src/world/vectors.lua`) y el editor.
- Cada terreno tiene 3 variantes de luz (oscura, media, clara): el importador elige la variante según la
  luminosidad de la ortofoto en esa casilla, así las manchas del mapa siguen las del satélite.
- Luz desde arriba a la izquierda: aleros claros arriba, sombra abajo a la derecha. Contorno `ink`
  automático en las siluetas de personajes y criaturas (`tools/chars.py`), zócalos y objetos que deben leerse.
- Autotiles por máscara de 4 vecinos (N=1, E=2, S=4, O=8): mar con espuma (4 frames a 4 FPS) y mar abierto
  más profundo (`seadeep_*`), piscinas, calles con acera, pavimento, caminos, rieras, tejados, muros.

## Edificios (`tools/buildings.py`)
- **Enderezados**: las huellas del Catastro/OSM se giran al ángulo que mejor encaja en la rejilla y, si son
  casi rectangulares, se sustituyen por un rectángulo de la misma área y centro. Una sola fachada continua.
- Tejados de pendiente (`terra`, `brown`, `slate`, `stone`) con vertiente norte al sol (`r_<t>_n_*`),
  cumbrera en la fila central (`r_<t>_k_*`) y vertiente sur en sombra (`r_<t>_s_*`). Azoteas (`flat`) con
  pretil y, en el interior, depósito, aire acondicionado, placas solares o claraboya (`r_flat_x1..4`).
  Cubierta metálica (`metal`) para naves e invernadero de vidrio (`glass`).
- Fachadas `f_<pared>_<l|m|r|s>_<tipo>`: paredes blanca, ocre, piedra, arena, salmón, azul cielo, ladrillo,
  chapa y vidrio; tipos `win` (persianas), `bal` (balconera), `door`, `shop`/`shop2`/`shop3` (toldos
  rojo, azul y verde), `garage`, `roll` (persiana de nave), `arch` (arco) y `up` (planta alta con balcón).
- Clases por uso del Catastro: casa, bloque de pisos (2–3 filas de fachada, bajos con tiendas), comercio,
  nave industrial, equipamiento público, masía e invernadero.
- Hitos con sprite propio: Sant Bartomeu, Arc de Berà (se pasa por debajo), Roc de Sant Gaietà,
  Ermita, Pedrera (boca de cueva ficticia), Torre del Cucurull, Mirador, Roda de Mar y, nuevos,
  **Ajuntament**, **Biblioteca Municipal** y **Castell de Creixell** (con cartel; no entran en el quadern).
- Elementos nuevos del paisaje: **barraques de pedra seca** (2 × 2, en los 33 nodos OSM del término) y las
  paradas del **Mercat Setmanal** (`o_stall_*`). Árboles: pino piñonero (2), palmera, olivo y **ciprés**.

## Personajes (`tools/chars.py`)
- Se dibujan por partes (cabeza, pelo, ropa, brazos, piernas, complementos) con contorno automático.
  Ciclo de caminar de 4 pasos con el cuerpo bajando 1 px en el apoyo y los brazos al revés que las piernas;
  reposo con parpadeo. Ojos con brillo, rubor y boca; sombra de piel y de pelo a la derecha.
- Estilos: pelo `short`, `bob`, `long`, `pigtails`, `bun`, `bald`, `spiky`; ropa `shorts`, `pants`, `dress`,
  `sweater`, `uniform`; sombreros `cap`, `ranger`, `beanie`, `chef`, `witch`, `pirate`, `santa`, `pumpkin`;
  complementos `apron`, `bag`, `cane`, `beard`, `glasses`, `scarf`, `belt`, `ribs`.
- Los aspectos del jugador (`data/skins.json`) y los NPC (`NPCS` en `tools/make_sprites.py`) son solo
  colores y estilo. NPC del juego: la Carme (forner), en Pere (pescador), l'avi Josep, la Laia, l'Anna
  (agent forestal), la Marta (carter) y, para el editor, turista, nen i veïna.
- En el juego: sombra bajo los pies, polvo al pisar (más en bici), estela de la espada, chispas al golpear,
  nube al vencer a un enemigo, sacudida de cámara al recibir daño, NPC que miran al jugador cuando se acerca
  y cámara que se adelanta hacia donde se camina.

- Todo el arte se genera por código y es reproducible: cambiar el dibujo = editar el generador y
  `make art maps`. Los PNG de `assets/runtime/` no se editan a mano.
- Inventario: autor y licencia en `docs/credits.md` (todo original salvo la fuente Unifont, OFL).
