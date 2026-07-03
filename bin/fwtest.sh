#!/bin/sh
# Diagnostic: does fbink draw after the framework is stopped, using KOReader's
# survival pattern? The framework SIGTERMs its children when it stops, so we
# IGNORE TERM around the stop (trap '' TERM) instead of dying on it.
# Always restarts the framework on exit. Logs each step to /mnt/us/memento-fw.log.
HERE=$(dirname "$0")
APPDIR=$(cd "$HERE/.." && pwd)
. "$APPDIR/config.sh"

LOG=/mnt/us/memento-fw.log
echo "start $(date)" > "$LOG"
echo "FBINK_BIN=$FBINK_BIN" >> "$LOG"

cleanup() { cd / ; start lab126_gui >/dev/null 2>&1; echo "fw restarted" >> "$LOG"; }
trap cleanup EXIT
trap '' TERM HUP                 # survive the framework teardown SIGTERM

stop lab126_gui >/dev/null 2>&1
echo "stopped lab126_gui, survived" >> "$LOG"
usleep 1250000 2>/dev/null || sleep 2   # let teardown finish before drawing

fbink -c -f -m -M "TEST 1 of 2

framework stopped
+ FLASH refresh

(8s)"
echo "draw1 (flash) exit: $?" >> "$LOG"
sleep 8

fbink -c -m -M "TEST 2 of 2

framework stopped
+ normal refresh

(8s)"
echo "draw2 (normal) exit: $?" >> "$LOG"
sleep 8

echo "done" >> "$LOG"
exit 0
