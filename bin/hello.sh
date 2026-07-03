#!/bin/sh
# Minimal diagnostic: does fbink draw on this device at all?
# No framework stop, so zero black-screen risk. After KUAL exits to the library
# we wait briefly for the library to finish repainting, then draw on top of it
# with a forced flash refresh and hold it on screen.
HERE=$(dirname "$0")
APPDIR=$(cd "$HERE/.." && pwd)
. "$APPDIR/config.sh"

# log which fbink we resolved + what it reports about the screen
echo "FBINK_BIN=$FBINK_BIN" > /mnt/us/memento-fbink.txt
fbink -e >> /mnt/us/memento-fbink.txt 2>&1
echo "fbink exit: $?" >> /mnt/us/memento-fbink.txt

sleep 3   # let the post-KUAL library redraw settle so it doesn't paint over us
fbink -c -f -m -M "MEMENTO TEST

If you can read this,
fbink works.

closes in 10s"
echo "draw exit: $?" >> /mnt/us/memento-fbink.txt
sleep 10
exit 0
