#!/bin/sh
# Diagnostic: can this device fetch the cloud (GitHub raw, HTTPS) recipes?
# Runs the real fetch sync.sh uses plus direct curl/wget probes, and writes
# precise results to /mnt/us/memento-tls.log so they can be read back over USB.
# No device shell needed - eject, tap this in KUAL, replug, read the log.
HERE=$(dirname "$0")
APPDIR=$(cd "$HERE/.." && pwd)
. "$APPDIR/config.sh"

LOG=/mnt/us/memento-tls.log
URL="https://raw.githubusercontent.com/lulvul/memento-recipes/main/manifest.txt"

log() { echo "$1" >> "$LOG"; sync; }

: > "$LOG"; sync
log "=== memento TLS check $(date 2>/dev/null) ==="
log "DL_BIN resolved to: [${DL_BIN:-<none>}]"
log "ls /usr/bin/curl: $(ls -l /usr/bin/curl 2>&1)"
log "command -v curl: $(command -v curl 2>&1)"
log "command -v wget: $(command -v wget 2>&1)"
log ""

# 1) the exact fetch() sync.sh will use
log "--- fetch() (what sync.sh uses) ---"
if fetch "$URL" /tmp/tls.out; then
  log "fetch OK. first line: $(head -1 /tmp/tls.out 2>&1)"
  RESULT="OK - cloud sync works"
else
  rc=$?
  log "fetch FAILED (exit $rc)."
  RESULT="FAILED - see log"
fi
log ""

# 2) curl direct, if one resolved
if [ -n "$DL_BIN" ]; then
  log "--- $DL_BIN direct ---"
  OUT=$("$DL_BIN" -fsSL "$URL" 2>&1); RC=$?
  log "exit $RC; out: $(echo "$OUT" | head -2)"
  log ""
fi

# 3) busybox wget over https, with and without cert check
log "--- wget https ---"
OUT=$(wget -q -O - "$URL" 2>&1); RC=$?
log "wget exit $RC; out: $(echo "$OUT" | head -2)"
OUT=$(wget -q --no-check-certificate -O - "$URL" 2>&1); RC=$?
log "wget --no-check-certificate exit $RC; out: $(echo "$OUT" | head -2)"

fbink -c -m -M "TLS check: $RESULT

Replug to Mac and read
/mnt/us/memento-tls.log" >/dev/null 2>&1
sleep 2
exit 0
