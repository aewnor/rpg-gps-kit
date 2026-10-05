# RPG GPS kit — flujo de producción. Requiere python3 (numpy, Pillow), LÖVE 11.5 y luajit.
PY ?= python3
LOVE ?= love
HEADLESS = SDL_VIDEODRIVER=offscreen

.PHONY: all art maps newmaps validate test unit integration package bench run clean

all: art maps validate

art:
	cd tools && $(PY) make_locals.py && $(PY) make_tiles.py && $(PY) make_sprites.py

maps:
	cd tools && $(PY) make_streets.py && $(PY) make_roads.py && $(PY) import_osm.py && $(PY) decorate_map.py && $(PY) make_caves.py && $(PY) make_dungeon.py && $(PY) compile_maps.py && $(PY) make_overview.py && $(PY) make_minimap.py

# lloc nou (després de tools/new_location.py): serveis i missions de l'OSM del lloc, i el mapa sencer
newmaps:
	cd tools && $(PY) make_streets.py && $(PY) make_services.py && $(PY) make_missions.py
	$(MAKE) maps

validate:
	cd tools && $(PY) validate_content.py && $(PY) palette_check.py

unit:
	luajit tests/radio_cases.lua
	luajit tests/casino_cultural_cases.lua
	$(PY) tests/nature_cases.py
	luajit tests/profile_pets_cases.lua
	luajit tests/store_layout_cases.lua
	$(PY) tests/variety_assets.py
	$(PY) tests/levels_cases.py
	$(PY) tests/zone_polish_cases.py
	luajit tests/variety_cases.lua
	luajit tests/sync_cases.lua
	luajit tests/house_layouts_cases.lua
	luajit tests/vehicle_assist_cases.lua
	luajit tests/fishing_cases.lua
	luajit tests/errands_cases.lua
	luajit tests/net_cases.lua
	node tests/net_bridge.cjs
	luajit tests/owner_cases.lua
	luajit tests/webui_cases.lua
	$(PY) tests/web_server_cases.py
	$(PY) tests/campaigns_cases.py
	$(PY) tests/release_cases.py
	luajit tests/profile_save_cases.lua
	luajit tests/name_input_cases.lua
	luajit tests/collision_cases.lua
	luajit tests/save_cases.lua
	luajit tests/combat_cases.lua
	luajit tests/rpg_cases.lua
	luajit tests/family_cases.lua
	luajit tests/rest_cases.lua
	luajit tests/fauna_cases.lua
	luajit tests/minigames_cases.lua
	luajit tests/juice_cases.lua
	luajit tests/missions_cases.lua
	luajit tests/building_cases.lua
	luajit tests/combat6_cases.lua
	$(PY) tests/paperdoll_cases.py
	cd tools && $(PY) ../tests/map_validation.py
	$(PY) tests/zones_cases.py
	$(PY) tests/buildings_cases.py
	$(PY) tests/marina_cases.py
	luajit tests/tts_cases.lua

integration:
	$(HEADLESS) $(LOVE) . --test --mute

test: unit integration

package:
	$(PY) tools/make_variety.py
	rm -rf build/pkg && mkdir -p build/pkg
	cp -r main.lua conf.lua src data build/pkg/
	mkdir -p build/pkg/maps build/pkg/assets build/pkg/docs
	cp -r maps/runtime build/pkg/maps/
	cp -r assets/runtime build/pkg/assets/
	cp docs/credits.md README.md build/pkg/docs/
	rm -f build/pkg/src/devtools.lua
	cd build/pkg && zip -9 -qr ../roda-rpg.love .
	@ls -la build/roda-rpg.love

bench:
	$(HEADLESS) $(LOVE) . --bench=600 --mute

run:
	$(LOVE) .

clean:
	rm -rf build maps/runtime
