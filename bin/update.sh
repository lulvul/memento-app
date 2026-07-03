#!/bin/sh
# OTA self-update: pull the app from GitHub raw (APP_SRC in config.sh) and
# install it. Runnable standalone from KUAL, or from the in-app settings
# screen (memento.sh re-execs itself after a successful update).
#
# Safe order: stage the WHOLE manifest to /tmp first, verify every file
# (md5 when md5sum exists, sh -n on every script), back up the current files
# to $APPDIR/.backup, then install by per-file rename (mv on the same fs is
# atomic; the running script survives because the old inode stays open).
# Nothing in APPDIR changes unless the entire staged set passes.
#
# Exit codes: 0 = updated, 3 = already up to date, 1 = failed (unchanged).
HERE=$(dirname "$0")
APPDIR=$(cd "$HERE/.." && pwd)
. "$APPDIR/config.sh"

VFILE="$APPDIR/app-version"
STAGE=/tmp/memento-update
MANI=/tmp/memento-app.manifest
BK="$APPDIR/.backup"

say() { fbink -c -m -M "$1" >/dev/null 2>&1; }

say "Checking for update..."

if ! fetch "$APP_SRC/VERSION" /tmp/memento-app.version; then
  say "Update check failed.
Check Wi-Fi / APP_SRC
(set in config.sh)"
  sleep 2
  exit 1
fi
remote=$(tr -d ' \r\n' < /tmp/memento-app.version)
local_v=""
[ -f "$VFILE" ] && local_v=$(tr -d ' \r\n' < "$VFILE")
if [ -z "$remote" ]; then
  say "Update check failed:
empty VERSION from server."
  sleep 2
  exit 1
fi
if [ "$remote" = "$local_v" ]; then
  say "Up to date.
$local_v"
  sleep 2
  exit 3
fi

say "Updating to $remote ..."

if ! fetch "$APP_SRC/app-manifest.txt" "$MANI"; then
  say "Update failed:
couldn't fetch manifest."
  sleep 2
  exit 1
fi

# --- stage + verify ------------------------------------------------------
rm -rf "$STAGE"
mkdir -p "$STAGE"
have_md5=0
command -v md5sum >/dev/null 2>&1 && have_md5=1

fail() {
  say "Update failed:
$1

Nothing was changed."
  rm -rf "$STAGE"
  sleep 3
  exit 1
}

while read -r sum path; do
  [ -z "$path" ] && continue
  mkdir -p "$STAGE/$(dirname "$path")"
  fetch "$APP_SRC/$path" "$STAGE/$path" || fail "download of $path"
  if [ "$have_md5" = "1" ]; then
    got=$(md5sum "$STAGE/$path" | awk '{print $1}')
    [ "$got" = "$sum" ] || fail "checksum of $path"
  fi
  case "$path" in
    *.sh) sh -n "$STAGE/$path" 2>/dev/null || fail "syntax check of $path" ;;
  esac
done < "$MANI"

# --- back up what we're about to replace ---------------------------------
rm -rf "$BK"
mkdir -p "$BK"
while read -r sum path; do
  [ -z "$path" ] && continue
  if [ -f "$APPDIR/$path" ]; then
    mkdir -p "$BK/$(dirname "$path")"
    cp "$APPDIR/$path" "$BK/$path" || fail "backup of $path"
  fi
done < "$MANI"
[ -f "$VFILE" ] && cp "$VFILE" "$BK/app-version"

# --- install: copy to .new on the same fs, then atomic rename ------------
while read -r sum path; do
  [ -z "$path" ] && continue
  mkdir -p "$APPDIR/$(dirname "$path")"
  cp "$STAGE/$path" "$APPDIR/$path.new" && mv "$APPDIR/$path.new" "$APPDIR/$path" \
    || fail "install of $path (run rollback)"
done < "$MANI"

printf '%s\n' "$remote" > "$VFILE"
sync
rm -rf "$STAGE"

say "Updated to $remote"
sleep 1
exit 0
