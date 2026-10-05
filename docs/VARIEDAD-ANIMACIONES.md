# Variedad y animaciones

Ampliación aditiva; IDs y guardados anteriores se conservan.

- 24 objetos: 8 armas (daga, sabre, llança, martell, destral, gladi, bastó y fulla),
  6 piezas de equipo, 5 alimentos y 5 coleccionables. Alcance, tiempos, energía y
  nivel mantienen compromisos entre armas. Todos salen en botín o tiendas.
- 8 diseños de NPC; 6 personajes nuevos con diálogo local y colocación validada.
  Nuevos aspectos también disponibles en el editor, peatones y servicios.
- 4 familias de cofres (mar, bosque, romana y cristal) además de las 4 existentes.
  Selección determinista por ID, sin volver a abrir cofres guardados. Cofres de
  misión conservan su objeto garantizado. Todas las familias aparecen en mapas.
- 6 elementos de ambientación: barril, caja, flores, ánfora, farol y setas.
  Se colocan junto a servicios solo en suelo transitable; no añaden obstáculos.

Movimiento revisado: pasos según distancia real (jugador, NPC, acompañantes y
peatones), reposo con pies apoyados, armas y escudos equipados visibles, anticipación,
golpe, estela y recuperación; respuesta al daño, vuelo del dragón, respiración de
animales, vehículos, proyectiles, antorchas, indicadores, partículas, textos y
transiciones entre escenas. Cofres: 5 fotogramas y aparición breve de la recompensa.
También se suavizan la entrada y los resultados de los seis minijuegos; la ruleta
reduce el giro decorativo con movimiento reducido, conservando su resultado.
Los tiempos físicos de combate y colisiones no cambian para armas existentes.

El movimiento reducido del navegador llega al canvas. También hay opción nativa
persistente en Opcions. Ambas se combinan; reduce sacudidas, respiración, saltos,
estelas y cantidad de partículas sin ocultar información necesaria para jugar.
No se cambian las reglas ni los tiempos jugables de los minijuegos.

Assets originales reproducibles: `python3 tools/make_variety.py`, ejecutado también
por `make package`. No requiere red, APIs de generación ni nuevas dependencias.
Pruebas: `make unit`, `python3 tools/validate_content.py`,
`love . --test=tests/variety_flow.lua --mute` y `tests/npc_placement.lua`.
Prueba de render con capturas separadas por arma y fases de cofre; la emulación no
sustituye la comprobación física del teclado móvil.
