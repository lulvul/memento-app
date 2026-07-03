#!/bin/sh
# Regenerate VERSION and app-manifest.txt for the memento-app repo.
# Run from anywhere; operates on the repo root. The pre-commit hook runs this
# and stages the result, so every push carries a fresh version stamp and a
# manifest that matches the committed files.
#
# Manifest format (one line per OTA-updatable file): `<md5>  <relpath>`.
# Excluded on purpose:
#   bin/rollback.sh - the recovery tool; OTA must never be able to break it.
#   menu.json / config.xml - KUAL launcher plumbing, changed over USB only.
#   tools/, README, VERSION, the manifest itself - repo-side, not app files.
set -e
cd "$(dirname "$0")/.."

# commit gate: every shell file must at least parse
for f in config.sh bin/*.sh; do
  sh -n "$f" || { echo "gen-app-manifest: sh -n failed on $f" >&2; exit 1; }
done

hash_of() {
  if command -v md5sum >/dev/null 2>&1; then md5sum "$1" | awk '{print $1}'
  else md5 -q "$1"
  fi
}

date +%Y.%m.%d-%H%M > VERSION
: > app-manifest.txt
for f in config.sh bin/*.sh; do
  case "$f" in bin/rollback.sh) continue ;; esac
  printf '%s  %s\n' "$(hash_of "$f")" "$f" >> app-manifest.txt
done
echo "gen-app-manifest: $(cat VERSION), $(wc -l < app-manifest.txt | tr -d ' ') files"
