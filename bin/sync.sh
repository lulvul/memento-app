#!/bin/sh
# Pull recipe markdown into RECIPE_DIR. One-way.
# Works against the Mac server.py (LAN, http) or GitHub raw (cloud, https) -
# the difference is SERVER / MANIFEST_PATH / FILES_PREFIX and curl-vs-wget,
# all resolved in config.sh.
# Runnable standalone from KUAL, or called by memento.sh on launch.
HERE=$(dirname "$0")
APPDIR=$(cd "$HERE/.." && pwd)
. "$APPDIR/config.sh"

mkdir -p "$RECIPE_DIR"
fbink -c -m -M "Syncing from
$SERVER" >/dev/null 2>&1

if ! fetch "$SERVER$MANIFEST_PATH" /tmp/memento.manifest; then
  fbink -c -m -M "Sync failed.
Check server / Wi-Fi / URL.
(set in config.sh)" >/dev/null 2>&1
  sleep 2
  exit 1
fi

# Pull each file to a temp first, then move on success, so a transient
# failure never clobbers a good local copy. Keep the manifest's full list
# (not just what downloaded) as the set of recipes that should exist.
n=0
: > /tmp/memento.keep
while IFS= read -r f; do
  [ -z "$f" ] && continue
  echo "$f" >> /tmp/memento.keep
  if fetch "$SERVER$FILES_PREFIX$f" /tmp/memento.dl; then
    mv /tmp/memento.dl "$RECIPE_DIR/$f"
    n=$(( n + 1 ))
  fi
done < /tmp/memento.manifest

# Delete local recipes the manifest no longer lists (deletions propagate).
d=0
for local in "$RECIPE_DIR"/*.md; do
  [ -e "$local" ] || continue
  base=$(basename "$local")
  if ! grep -qx "$base" /tmp/memento.keep; then
    rm -f "$local"
    d=$(( d + 1 ))
  fi
done

if [ "$d" -gt 0 ]; then
  fbink -c -m -M "Synced $n recipes.
Removed $d." >/dev/null 2>&1
else
  fbink -c -m -M "Synced $n recipes." >/dev/null 2>&1
fi
sleep 1
exit 0
