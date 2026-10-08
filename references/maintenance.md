# Maintaining RPG GPS games

[ Català ](maintenance.ca.md)

Read only the sections relevant to the task. Paths are relative to the repository of the game being edited.

## Interiors, furniture and existing saves

- `src/world/procgen.lua` generates interiors and decoration; `src/world/procmap.lua` turns them into maps and assigns chest flags. Review both when moving furniture or adding loot.
- Check spawn points, exits, doors between floors, NPCs and interaction points. A visible chest can be inaccessible if there is no legal position from which to face it. Validate against actual player collision and interaction range; tile-based approximations can report false failures at corners.
- Preserve seeds, random-number consumption order, rewards and existing chest flags. Reordering objects can change a numeric flag and grant a previously collected reward again. Use stable identifiers for new content and retain compatibility with old content.
- Roda has added `src/world/interior_access.lua`: check whether it exists before reusing it. `snapshot`/`replay` relocate decoration to accessible positions without regenerating loot; `legacy_index` preserves old flags. Do not assume this module is already in the kit.
- When available, run `tests/interior_access_cases.lua` and `tests/interior_access_flow.lua`; also test leaving, re-entering and continuing a saved game. Cover different interior types, seeds and floors when validating procedural generation, rather than just one interior.

## Mobile controls and magic

- `web/index.html` converts touch buttons into keyboard events; `src/input.lua` maps them to actions. Keep `data-key`, `data-code` and the JavaScript `CODES` map consistent (`v`, `86`, `KeyV` for casting magic).
- `src/scenes/world_scene.lua:cast_spell` retains `magic_quest` learning, level requirements and mana checks. `Magic.has_staff` accepts a staff equipped in either hand. A spellcasting button must not invoke weapon swapping through `Rpg.swap`.
- In the Roda version reviewed on 2026-10-08, the 🪄 button replaces the touch weapon-swap button. The kit may still have the R button; inspect the file before describing its behavior.
- Distinguish accidental browser zoom from a request to fill the screen. `touch-action:none`, `overscroll-behavior:none` and Safari gestures affect interaction, not the game's aspect ratio. Restrict gesture handlers to the game and controls without intercepting forms.
- If rendering scale changes, update the coordinate transformation in `Game:pointer` too. Stretching CSS alone can misalign touch input.
- Check portrait and landscape with `hasTouch`/`isMobile`, key press and release, simultaneous controls and the name form. Shrinking a desktop window does not necessarily activate `(pointer: coarse)`. Identify emulation as emulation: it does not test Safari on physical hardware.

## Resolution and performance

- In derived games with `src/render_resolution.lua`, logical coordinates differ from the physical canvas resolution. Review scaling, sprite origins, mutable quads and scissor rectangles when changing rendering.
- Roda keeps backgrounds at low resolution and characters/foreground at high resolution to reduce cost. Measure performance before moving every layer to high resolution.
- `--bench=N` specifies seconds, not frames. Compare measurements under the same conditions; do not extrapolate software-rendering results to all mobile devices.

## Web deployment

1. Validate content and run appropriate tests (`make validate`, `make unit`; check exit codes). For documentation-only changes, validate the guide and links without regenerating the game.
2. `sh tools/build_web.sh` prepares a candidate and prints its `releases/<id>` path; without `--activate`, it does not change the active website. Inspect the script if a derived game has changed this contract.
3. Test the candidate with temporary profiles and storage. Do not connect preview-server APIs to production saves. Verify that the engine actually starts, not merely that the canvas becomes visible.
4. Once deployment is authorized, check `manifest.json` and confirm the active version has not changed during testing. `tools.web_release.activate_release(root, release)` activates an existing candidate by atomically switching `build/web`. Rebuilding or restarting the server is unnecessary.
5. Verify HTTP responses and hashes of the served HTML and assets. JavaScript/WASM use `/releases/<id>/...`; map chunks are requested from `/data/<scene>/<file>`. Retain the previous release for rollback.

Keep town-specific content (coordinates, local quests and family data) separate from reusable engine changes when porting improvements to the kit.
