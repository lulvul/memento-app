#!/bin/sh
# Input calibration probe. For 20 seconds, streams every /dev/input device to a
# raw file (keeping each device open the whole time, so nothing in a tap burst
# is dropped), then decodes them into /mnt/us/memento-probe.log tagged by device.
# Tap the four screen corners while it runs, then USB-mount and read the log (or
# paste it to Raq-2). From it: INPUT_DEV (the touch node), TOUCH_CODE_X/Y (the
# codes whose values track your finger), and TOUCH_X/Y_MIN/MAX (corner values).
HERE=$(dirname "$0")
APPDIR=$(cd "$HERE/.." && pwd)
. "$APPDIR/config.sh"

LOG=/mnt/us/memento-probe.log
RAWDIR=/mnt/us/memento-probe-raw
rm -rf "$RAWDIR"; mkdir -p "$RAWDIR"

# No framework stop: capturing input from /dev/input works regardless of what's
# on screen, so the probe stays safe (no black-screen risk). You won't see a
# live countdown over the library; just tap the 4 corners during the run.
trap 'kill $(jobs -p) 2>/dev/null' EXIT

sleep 2   # let the library finish repainting after KUAL exits
fbink -c -f -m -M "INPUT PROBE - 20s

Tap the 4 corners,
slowly, one at a time.

Log -> memento-probe.log" >/dev/null 2>&1
sleep 3

# stream each device to its own raw file (cat writes through, no stdio buffering)
for d in /dev/input/event*; do
  [ -e "$d" ] || continue
  n=$(basename "$d")
  cat "$d" > "$RAWDIR/$n.raw" &
done

end=$(( $(date +%s) + 20 ))
while [ "$(date +%s)" -lt "$end" ]; do
  left=$(( end - $(date +%s) ))
  fbink -c -m -M "PROBE running

tap the 4 corners

${left}s left" >/dev/null 2>&1
  sleep 2
done

kill $(jobs -p) 2>/dev/null
sync

# decode every raw capture into the log
{
  echo "=== Memento input probe ==="
  date
  echo "devices:"; ls /dev/input/event* 2>/dev/null
  echo "--- decoded events: each line is one input_event as u2 words ---"
  echo "--- 8 words = 16-byte event (32-bit); 12 words = 24-byte (64-bit) ---"
  for raw in "$RAWDIR"/*.raw; do
    [ -s "$raw" ] || continue
    name=$(basename "$raw" .raw)
    echo "### $name"
    # 8 words/line keeps 16-byte events one-per-line; 24-byte events wrap to 1.5
    # lines but the word order is intact and easy to read.
    od -A n -t u2 -v -w16 "$raw" | sed "s/^/$name : /"
  done
} > "$LOG"
rm -rf "$RAWDIR"

fbink -c -m -M "Probe done.

USB-mount and open
memento-probe.log
Paste it to Raq-2." >/dev/null 2>&1
sleep 3   # let the message stay before the framework (library) returns on exit
exit 0
