#!/bin/sh
# Build outside the active release; --activate switches only after a complete candidate.
set -eu
cd "$(dirname "$0")/.."
mkdir -p build releases
exec 9>build/.web-build.lock
flock -n 9 || { echo 'Ya hay una compilación web en curso' >&2; exit 1; }
activate=''
[ "${1:-}" != '--activate' ] || activate='--activate'
release_id="${RODA_RELEASE_ID:-web-$(date -u +%Y%m%d-%H%M%S)-$$}"
candidate="$(mktemp -d "$PWD/releases/.candidate-XXXXXX")"
trap 'rm -rf "$candidate"' EXIT HUP INT TERM
make package >/dev/null
[ -d tools/web/node_modules/love.js ] || (cd tools/web && npm ci --no-audit --no-fund)
tools/web/node_modules/.bin/love.js -c -t 'Roda de Berà' -m 268435456 build/roda-rpg.love "$candidate"
rm -rf "$candidate/theme"
# Expose FS.syncfs so web/persist.js can flush saves to IndexedDB (love.js only does it on beforeunload).
sed -i 's/Module\["FS_unlink"\]=FS.unlink;/Module["FS_unlink"]=FS.unlink;Module["FS_syncfs"]=FS.syncfs;/g' "$candidate/love.js"
grep -q 'Module\["FS_syncfs"\]=FS.syncfs' "$candidate/love.js" || { echo 'No se pudo exponer FS.syncfs en love.js' >&2; exit 1; }
cp web/index.html "$candidate/index.html"
cp -r web/editor "$candidate/editor"
cp -r maps/runtime "$candidate/map-data"
for file in web/*.js; do [ ! -f "$file" ] || cp "$file" "$candidate/"; done
python3 tools/web_release.py "$candidate" "$release_id" $activate
