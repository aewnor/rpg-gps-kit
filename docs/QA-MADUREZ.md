# Madurez — 2026-10-04

Contratos: los perfiles corruptos ocupan su ranura y ofrecen error; el guardado
conserva backup validado y bloquea salir/cambiar dueño ante fallo. Las partidas
anteriores siguen bajo «Partides locals»; cada dueño del hub tiene su directorio.
El formulario HTML usa sesiones de edición y conserva la rejilla alternativa.

El editor requiere una sesión adulta de 15 minutos validada por el hub. Las
escrituras requieren `X-Roda-Request: 1` e `If-Match` de la lectura; 409 conserva
el borrador. No sustituir una revisión antigua automáticamente para reintentar.
NPCs usan únicamente contexto público persistido, con límites y fallback local.

`make unit` verifica almacenamiento, namespaces, cancelación, editor y releases.
`python3 tests/http_cases.py` verifica HTTP real en loopback con datos temporales.
`make validate` requiere el artefacto geográfico cartography/derived/terrain.npz.
`love . --test=tests/profile_flow.lua --mute` comprueba el flujo nativo.

`sh tools/build_web.sh` crea candidato completo sin activar. `--activate` activa
tras validarlo. La publicación desde el editor copia y compila fuentes en staging;
un fallo no modifica los mapas activos. Editor y mapas compilados viajan con la
release. El servidor necesita reiniciarse cuando cambia su código Python.

Rollback web: usar `activate_release(root, release_anterior)` de
tools/web_release.py. Al revertir esta actualización también deben restaurarse
servidor y fuentes desde su backup y reiniciarse solo roda-rpg-web.service.
Nunca eliminar partidas ni mapas para hacer rollback.

Evidencias de ejecución: salida/roda-rpg-maduro-20261003 en el workspace de Astra.
Chromium comprueba Unicode, borradores, cambio de dueño, recarga, rejilla,
320/390/768/1365 px y horizontal, controles >=44 px, teclado, texto 200 % y
reduced-motion. Todas las APIs domésticas del navegador usan fixtures.
Pendientes de prueba manual: Android/iOS físicos (IME y teclado virtual), mando,
lector de pantalla y rendimiento p95 en dispositivo final. Emulación no sustituye
esas comprobaciones. El runtime existente permanece fijado a love.js 11.4.1.
