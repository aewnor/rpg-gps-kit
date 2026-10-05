# Prueba de rendimiento (T11/T18)

**Fecha:** 2026-10-02 · **Commit:** el de este documento · **Orden:** `make bench`
(`SDL_VIDEODRIVER=offscreen love . --bench=600 --mute`).

| | |
|---|---|
| Máquina | Raspberry Pi 5 Model B Rev 1.1, Debian 13 (trixie) 64 bits |
| Motor | LÖVE 11.5 |
| Render | OpenGL 3.1 Mesa 26.2.2 — Broadcom V3D 7.1.10.2 (GPU real; sin monitor, salida offscreen) |
| Recorrido | 10 min automáticos: centro → Arc → Ermita → Roc → Sant Bartomeu → Pedrera → Cucurull → Mirador (en bucle), con coches, trenes y combate activos |

| métrica | resultado | presupuesto |
|---|---|---|
| tiempo actualización+render P95 | **1,81 ms** | ≤ 16,7 ms |
| P99 / máximo | 3,14 ms / 16,7 ms | — |
| frames > 33 ms | **0** (racha máxima 0) | sin tirones prolongados |
| memoria residente | **120 MiB** (Lua 13,6 MiB, texturas 1,8 MiB) | < 200 MiB |
| temperatura | 60–68 °C | — |
| throttling (`vcgencmd get_throttled`) | **0x0** | sin throttling |
| pasos descartados por retraso | 0 | — |

Notas honestas:
- Sin monitor conectado: no se mide el coste de presentar en pantalla ni el vsync real. Hay que
  repetir `make bench` con HDMI (sin `SDL_VIDEODRIVER`) cuando haya pantalla.
- Los frames en que la herramienta de benchmark calcula su ruta (BFS) se excluyen (10 frames); en
  una ejecución anterior sin excluirlos llegaban a 0,9 s. El juego no hace búsquedas de rutas.
- Datos completos: `docs/bench-2026-10-02.json`.
