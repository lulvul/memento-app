#!/bin/sh
# Restore the app files saved by the last update.sh run. The recovery path
# for an update that passed sh -n but broke at runtime. Run from KUAL
# ("Memento: Roll back update").
#
# NEVER listed in app-manifest.txt: OTA must not be able to break the tool
# that undoes OTA.
HERE=$(dirname "$0")
APPDIR=$(cd "$HERE/.." && pwd)
. "$APPDIR/config.sh"

BK="$APPDIR/.backup"
VFILE="$APPDIR/app-version"

say() { fbink -c -m -M "$1" >/dev/null 2>&1; }

if [ ! -d "$BK" ]; then
  say "No backup found.
Nothing to roll back to."
  sleep 2
  exit 1
fi

fail=0
# no spaces in app paths, so a line-based read is safe
find "$BK" -type f | while read -r f; do
  rel="${f#"$BK"/}"
  [ "$rel" = "app-version" ] && continue
  mkdir -p "$APPDIR/$(dirname "$rel")"
  cp "$f" "$APPDIR/$rel.new" && mv "$APPDIR/$rel.new" "$APPDIR/$rel" || exit 1
done || fail=1

if [ "$fail" = "1" ]; then
  say "Rollback FAILED partway.
Reinstall over USB."
  sleep 3
  exit 1
fi

if [ -f "$BK/app-version" ]; then
  cp "$BK/app-version" "$VFILE"
else
  rm -f "$VFILE"
fi
sync

v=""
[ -f "$VFILE" ] && v=$(tr -d ' \r\n' < "$VFILE")
say "Rolled back.
Now on ${v:-unknown version}"
sleep 2
exit 0
