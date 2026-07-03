#!/bin/sh
# Canary for the lighter screen-takeover approach: keep the Amazon framework
# RUNNING (so powerd / suspend still work), but freeze the window manager
# (awesome) and hide the status bar (pillow) so nothing repaints over us or
# steals our taps. SIGCONT reliably restores it on exit - no service restart.
# Logs with sync so the log survives even a hard reboot.
HERE=$(dirname "$0")
APPDIR=$(cd "$HERE/.." && pwd)
. "$APPDIR/config.sh"

LOG=/mnt/us/memento-ui.log
log() { echo "$(date +%T) $1" >> "$LOG"; sync; }
: > "$LOG"; log "start FBINK_BIN=$FBINK_BIN"

FROZEN=0
thaw() {
  [ "$FROZEN" = "1" ] && killall -CONT awesome >/dev/null 2>&1
  lipc-set-prop com.lab126.pillow disableEnablePillow enable >/dev/null 2>&1
  lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home >/dev/null 2>&1
  log "thawed (awesome CONT, pillow enabled, home requested)"
}
trap thaw EXIT

lipc-set-prop com.lab126.pillow disableEnablePillow disable >/dev/null 2>&1
log "pillow disabled"
killall -STOP awesome >/dev/null 2>&1 && FROZEN=1
log "awesome STOP FROZEN=$FROZEN"
sleep 1

fbink -c -f -m -M "UI FROZEN (framework up)

Press POWER to sleep,
then press it again to wake.

Auto-restores in 25s."
log "drew test screen exit=$?"

sleep 25
log "done, restoring"
exit 0
