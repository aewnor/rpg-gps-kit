---
name: rpg-gps-kit
description: Crear un joc RPG 2D (LÖVE 11.5 + love.js) d'un poble real a partir d'unes coordenades GPS amb el kit rpg-gps-kit — mapa d'OpenStreetMap, gràfics pixel art i música generats per codi, serveis i missions del lloc. Fes-lo servir quan demanin «un joc del meu poble», «el joc de Roda però en un altre poble» o mantenir i validar mapes, missions, interiors, controls o publicacions web de Roda RPG i jocs derivats del kit.
---

# RPG GPS Kit — joc nou des d'una ubicació GPS

Motor de l'aventura «Roda de Berà» convertit en kit. Tot el que surt a la pantalla es genera: el mapa de l'OSM,
els tiles i sprites (`tools/make_tiles.py`, `tools/make_sprites.py`, paleta de 32 colors de `tools/pixel.py`),
la música i els efectes (sintetitzats a `src/audio.lua` en arrencar), els interiors (`src/world/procgen.lua`)
i les missions. No cal cap fitxer d'art ni d'àudio extern.

## Kit i joc derivat

Repositori: [aewnor/rpg-gps-kit](https://github.com/aewnor/rpg-gps-kit). Per crear un poble nou, parteix del kit; per modificar un joc existent, treballa al seu repositori. Comprova `git status` i la revisió abans de copiar canvis: Roda i el kit poden tenir funcionalitats diferents. Conserva les modificacions locals; un canvi publicat pot encara no tenir commit.

Per editar interiors, gràfics, controls mòbils o publicar la web, consulta [references/maintenance.md](references/maintenance.md). Distingeix les invariants del motor dels exemples específics de Roda. Actualitzar aquesta guia no incorpora automàticament codi al kit.

## Flux de treball

```sh
cp -r rpg-gps-kit ~/joc-<lloc> && cd ~/joc-<lloc>
python3 tools/new_location.py --name "<Lloc>" --lat <lat> --lon <lon> [--size-km 3.2]
make newmaps        # make_streets → make_services → make_missions → make maps
make art            # make_locals (rètols de l'OSM) → make_tiles → make_sprites
make validate       # validate_content.py + palette_check.py: ha de dir «VALIDACIÓ OK»
make unit           # mira el codi de sortida, no el text (alguns tests imprimeixen OK i després peten)
love .              # o el servidor web: python3 tools/web_server.py (port 8102)
```

- `--size-km`: 3,2 km (800×800 caselles) va bé per a un poble; 6,4 km és el mapa de Roda. Més gran → més
  temps de `make maps` i més memòria al navegador. El costat sempre és múltiple de 32 (el tros del motor).
- `new_location.py` canvia `t.identity` de `conf.lua` a `rpg-<slug>`: cada joc té la seva carpeta de partides
  (`~/.local/share/love/rpg-<slug>`). El servidor web la llegeix de `conf.lua`. Executa aquest generador només en una còpia destinada al poble nou.
- Les proves de flux han d'usar un `XDG_DATA_HOME` temporal per no tocar partides reals. `make validate` escriu informes a `maps/source`: una còpia amb aquest directori enllaçat al projecte original no està aïllada.
- Proves de flux: `SDL_VIDEODRIVER=offscreen love . --test=tests/<x>_flow.lua --mute` (les de família amb
  `--keephome`). Les de `tests/roda/` només serveixen per al mapa original de Roda.

## On viu cada cosa

| Què | On |
|---|---|
| Projecció (origen NO, latitud de referència, 4 m/casella, mida) | `data/world.json`, llegit per `tools/osmlib.py` |
| OSM descarregat | `cartography/municipio.osm.gz`, límit `cartography/limite.osm.gz` |
| Carrers i places amb nom (cartells, missions) | `data/streets.json` (`make_streets.py`) |
| Serveis amb personatge (escola, metge, súper…) | `data/services.json` (`make_services.py`, editable a mà) |
| Rètols de botigues | `data/locals.json` (`make_locals.py`: directori de comerços si n'hi ha, si no l'OSM) |
| Missions | `data/missions.json` = capítol «poble» generat + capítols de `data/missions.base.json` |
| Retocs del mapa | `maps/source/map-overrides.json` (ponts, rampes, nivells, edificis), `map-edits.json` (editor) |
| Mapa compilat | `maps/runtime/` (no es versiona; `make maps`) |
| Nom del lloc al joc | `src/place.lua` (`Place.name()`, `Place.of()` → «de X»/«d'X») |

## Mapa: coses que cal saber

- **Bits de col·lisió**: 0-1 tipus a nivell 0 · 4 transitable a nivell 1 (tauler de pont) · 8 transitable a
  nivell -1 (túnel) · 16 rampa · 32 pendent de revisar (bloquejat). Un pont que fa «mur invisible» sol ser una
  rampa que falta o un `layer` d'OSM mal posat: corregeix-ho amb `ramps_add` / `level_overrides` a
  `map-overrides.json`, no tocant `import_osm.py`.
- **OSM amb `layer=-1` a tot un camí** (p. ex. un camí rural sencer) el converteix en túnel: posa
  `level_overrides` a 0 per a aquell `way/<id>`.
- **Overpass**: demana només `rel["type"="multipolygon"]`. Amb totes les relacions (límits, rutes) la
  descàrrega passa de 16 MB a 90 MB.
- `realdata.neutral()` substitueix l'ortofoto i el MDT quan no n'hi ha (el kit no en porta): terreny pla,
  verd mitjà. Amb ortofoto PNOA/MDT (`tools/sat_pipeline.py`, només Espanya) el terreny i el color de les
  teulades són més fidels.
- Les coves, la torre, la masmorra i el cau del drac (`decorate_map.py`) busquen camp pla lluny de les cases al
  voltant del punt d'inici. Si no hi caben, fes el mapa més gran (`--size-km`) o mou-les amb `landmark_offsets`.
- Els ids d'objectes amagats es fan amb slugs únics: si afegeixes generadors, evita ids repetits (el
  validador els rebutja).

## Missions

- Objectius: `area:<nom>`, `street:<nom>`, `service:<id>`, `friend:<id>`, `home`, `nearest:<tipus>`,
  `spot:<id>`, `door:<id>`, `chest:<id>`. Un pas pot portar `family='out'` (els pares surten de casa; si no, hi són sempre).
- `make_missions.py` canvia els llocs de Roda dels capítols base pels d'aquí (`subst`), les botigues de
  «compra» pels súpers locals i les portes de cova (`DOORS`). Si afegeixes un capítol a `missions.base.json`,
  fes servir objectius que existeixin a tot arreu (serveis, `home`, `nearest:`), o afegeix-ne el canvi.
- `make_missions.py` també escriu `data/perles.json`: les 7 Perles del Drac a places i parcs amb nom del lloc.
- L'editor web (`/editor`, sessió adulta del hub) exporta i importa campanyes en JSON per a un LLM.

## Accessibilitat (per a nens de 5 anys)

- Veu: `Tts.say(text, interrupt, voice)`; `Tts.gender(nom)` tria veu masculina o femenina pel nom del personatge.
  A la web, la veu es tria pel nom o canviant el to; les paraules es ressalten amb els missatges `tts_word`.
- Mode majúscules (`src/ui/upper.lua`): pega `love.graphics.print/printf` i `Font:getWidth/getWrap`.
- Pronúncies especials: `data/tts_lexicon.json` (només afecta l'àudio).

## Dades privades — mai al repositori

`home.json`, `maps/private/`, `casa_privada*`, `*.local.json` i `~/.local/share/<identity>-sync` són de
cada família (ubicació real de casa). Ja són a `.gitignore`; comprova `git status` abans de cada commit.

## Errors que ja han passat

- `make unit` amb `grep OK` amagava fallades: mira `$?`.
- Un mapa de test fals sense `in_bounds`/`cell` trencava l'assistència de conducció: protegeix l'accés.
- `Net.cancel_all` ha de conservar les peticions en curs (sincronització de perfils), excepte `/api/npc_chat`.
- No facis servir `pkill -f`/`pgrep -f` amb patrons que coincideixin amb el teu propi shell.
- No obris partides al navegador amb el perfil d'un nen actiu per provar coses: fes servir un perfil de proves.
