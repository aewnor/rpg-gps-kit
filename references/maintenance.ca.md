# Manteniment de jocs RPG GPS

Llegeix només les seccions relacionades amb la feina. Les rutes són relatives al repositori del joc que s'està editant.

## Interiors, mobles i partides existents

- `src/world/procgen.lua` genera interiors i decoració; `src/world/procmap.lua` els converteix en mapa i assigna flags als cofres. Revisa les dues peces quan moguis mobles o afegeixis botí.
- Comprova spawn, sortida, portes entre plantes, NPC i punts d'interacció. Un cofre visible pot ser inaccessible si no hi ha cap posició legal des d'on mirar-lo. Valida amb la col·lisió i l'abast real del jugador; una aproximació per caselles pot marcar falsos errors a les cantonades.
- Conserva llavors, ordre de consum del generador aleatori, premis i flags dels cofres existents. Reordenar objectes pot canviar un flag numèric i tornar a donar un premi ja recollit. Fes servir identificadors estables per al contingut nou i conserva la compatibilitat del contingut antic.
- A Roda s'ha afegit `src/world/interior_access.lua`: comprova si existeix abans de reutilitzar-lo. `snapshot`/`replay` recol·loquen decoració de forma accessible sense regenerar el botí; `legacy_index` conserva flags antics. No assumeixis que el kit ja incorpora aquest mòdul.
- Si hi són, executa `tests/interior_access_cases.lua` i el flux `tests/interior_access_flow.lua`; prova també sortir, tornar a entrar i continuar una partida desada. Per validar generació procedural, cobreix tipus, llavors i plantes, no només un interior.

## Controls mòbils i màgia

- `web/index.html` transforma els botons tàctils en esdeveniments de teclat; `src/input.lua` els assigna a accions. Mantén coherents `data-key`, `data-code` i el mapa JavaScript `CODES` (`v`, `86`, `KeyV` per llançar màgia).
- `src/scenes/world_scene.lua:cast_spell` conserva l'aprenentatge de `magic_quest`, els requisits de nivell i el manà. `Magic.has_staff` admet el bastó equipat en qualsevol de les dues mans. Un botó que llança màgia no ha d'invocar el canvi d'arma `Rpg.swap`.
- A la versió de Roda revisada el 2026-10-08, el botó 🪄 substitueix el canvi d'arma tàctil. El kit pot conservar encara el botó R; verifica el fitxer abans de descriure'n el comportament.
- Diferencia zoom accidental del navegador i petició d'omplir la pantalla. `touch-action:none`, `overscroll-behavior:none` i els gestos de Safari afecten la interacció; no canvien la relació d'aspecte del joc. Limita els manejadors de gestos a joc/controls, sense interceptar formularis.
- Si canvies l'escala del dibuix, actualitza també la transformació de coordenades de `Game:pointer`. Estirar només el CSS pot desalinear els tocs.
- Comprova vertical i horitzontal amb `hasTouch`/`isMobile`, pulsació i alliberament de tecles, controls simultanis i formulari de nom. Reduir una finestra d'escriptori no activa necessàriament `(pointer: coarse)`. Identifica l'emulació com a tal: no prova Safari en un dispositiu físic.

## Resolució i rendiment

- En els derivats que tinguin `src/render_resolution.lua`, les coordenades lògiques i la resolució física dels llenços són diferents. Revisa escalat, origen de sprites, quads mutables i scissor en modificar el render.
- Roda manté els fons en baixa resolució i personatges/primer pla en alta resolució per reduir el cost. No traslladis totes les capes a alta resolució sense mesurar el rendiment.
- `--bench=N` indica segons, no fotogrames. Compara les mesures en les mateixes condicions i no extrapolis una prova de render per programari a tots els mòbils.

## Publicació web

1. Verifica el contingut i les proves adequades (`make validate`, `make unit`; comprova els codis de sortida). Per canvis només de documentació, valida la guia i els enllaços, sense regenerar el joc.
2. `sh tools/build_web.sh` prepara una candidata i imprimeix la ruta `releases/<id>`; sense `--activate` no canvia la web activa. Revisa l'script si el derivat ha canviat aquest contracte.
3. Prova la candidata amb perfils i emmagatzematge temporals. En un servidor de preview, no connectis les API a les partides de producció. Comprova l'arrencada real del motor, no només que el canvas s'hagi fet visible.
4. Quan publicar estigui autoritzat, comprova `manifest.json` i que la versió activa no hagi canviat durant la prova. `tools.web_release.activate_release(root, release)` activa una candidata existent canviant atòmicament `build/web`. No cal recompilar-la ni reiniciar el servidor.
5. Verifica la resposta HTTP i els hashes del HTML i dels recursos servits. JavaScript/WASM utilitzen `/releases/<id>/...`; els chunks del mapa es demanen a `/data/<escena>/<fitxer>`. Conserva la release anterior per poder revertir.

Mantén els continguts d'un poble (coordenades, missions locals i dades familiars) separats dels canvis reutilitzables del motor quan traslladis millores al kit.
