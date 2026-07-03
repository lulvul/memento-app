#!/bin/sh
# Read ONE user action from the input device and print it, then exit.
# Output is exactly one of: NEXT PREV SELECT BACK QUIT NONE
# memento.sh calls this in a loop: act=$(sh input.sh)
#
# Three modes (set INPUT_MODE in config.sh):
#   stdin -> read one char (n/p/s/b/q) from stdin. For SSH/dev testing.
#   keys  -> EV_KEY button presses, mapped via KEY_* in config.sh.
#   touch -> tap zones on the touchscreen, calibrated via TOUCH_* in config.sh.
#            left third = PREV, middle = SELECT, right third = NEXT,
#            top-left corner = BACK.
HERE=$(dirname "$0")
APPDIR=$(cd "$HERE/.." && pwd)
. "$APPDIR/config.sh"

# --- stdin mode ---------------------------------------------------------
if [ "$INPUT_MODE" = "stdin" ]; then
  read -r c || { echo QUIT; exit 0; }
  case "$c" in
    n) echo NEXT ;; p) echo PREV ;; s) echo SELECT ;;
    b) echo BACK ;; q) echo QUIT ;; *) echo NONE ;;
  esac
  exit 0
fi

# --- pick the device ----------------------------------------------------
DEV="$INPUT_DEV"
if [ -z "$DEV" ]; then
  DEV=$(ls /dev/input/event* 2>/dev/null | head -1)
fi
if [ ! -e "$DEV" ]; then echo NONE; exit 0; fi

# Open the device ONCE and keep it open for the whole gesture. Reopening per
# event would drop the fast coordinate burst a single tap fires (the kernel
# only buffers events for an open client), so we read every event from the same
# fd 3 until we've decoded an action.
exec 3< "$DEV" || { echo NONE; exit 0; }

# Read one input_event from fd 3 and split into etype/ecode/evlo/evhi.
# Self-framing: read up to 24 bytes (covers both struct sizes), then decide by
# how many 2-byte words came back. 8 words => 16-byte event (32-bit time, e.g.
# Paperwhite 4); 12 words => 24-byte event (64-bit time, e.g. Paperwhite 5).
# The `type` word index follows: 4 (after a 4-word/8-byte time) or 8.
read_event() {
  ev=$(dd bs=24 count=1 <&3 2>/dev/null | od -A n -t u2 -v | tr '\n' ' ')
  [ -z "$ev" ] && return 1
  # shellcheck disable=SC2086
  set -- $ev
  if [ "$#" -ge 12 ]; then tidx=8; else tidx=4; fi
  eval "etype=\${$(( tidx + 1 ))}; ecode=\${$(( tidx + 2 ))}; evlo=\${$(( tidx + 3 ))}; evhi=\${$(( tidx + 4 ))}"
  return 0
}

decide_zone() {  # $1 = x, $2 = y -> echoes action
  awk -v x="$1" -v y="$2" -v xmin="$TOUCH_X_MIN" -v xmax="$TOUCH_X_MAX" \
      -v ymin="$TOUCH_Y_MIN" -v ymax="$TOUCH_Y_MAX" 'BEGIN{
    dx = xmax - xmin; dy = ymax - ymin;
    if (dx == 0) dx = 1; if (dy == 0) dy = 1;
    fx = (x - xmin) / dx; fy = (y - ymin) / dy;
    if (fx < 0) fx = 0; if (fx > 1) fx = 1;
    if (fy < 0) fy = 0; if (fy > 1) fy = 1;
    if (fy < 0.12) { print "BACK"; exit }     # full-width top strip = back/quit
    if (fy > 0.90) { print "MENU"; exit }     # full-width bottom strip = settings (cover only; ignored elsewhere)
    if (fx < 0.34) { print "PREV"; exit }     # left third
    if (fx > 0.66) { print "NEXT"; exit }     # right third
    print "SELECT";                            # middle
  }'
}

# --- keys mode ----------------------------------------------------------
if [ "$INPUT_MODE" = "keys" ]; then
  while read_event; do
    # EV_KEY (type 1), press (value 1)
    [ "$etype" = "1" ] || continue
    [ "$evlo" = "1" ] || continue
    case "$ecode" in
      "$KEY_NEXT")   echo NEXT;   exit 0 ;;
      "$KEY_PREV")   echo PREV;   exit 0 ;;
      "$KEY_SELECT") echo SELECT; exit 0 ;;
      "$KEY_BACK")   echo BACK;   exit 0 ;;
    esac
  done
  echo NONE; exit 0
fi

# --- touch mode (default) ----------------------------------------------
lastx=-1; lasty=-1
while read_event; do
  # track latest coordinates (EV_ABS, type 3)
  if [ "$etype" = "3" ]; then
    [ "$ecode" = "$TOUCH_CODE_X" ] && lastx="$evlo"
    [ "$ecode" = "$TOUCH_CODE_Y" ] && lasty="$evlo"
  fi
  released=0
  # BTN_TOUCH (EV_KEY 330) release
  [ "$etype" = "1" ] && [ "$ecode" = "330" ] && [ "$evlo" = "0" ] && released=1
  # ABS_MT_TRACKING_ID (code 57) == -1  (shows as 65535 in u2)
  [ "$etype" = "3" ] && [ "$ecode" = "57" ] && [ "$evlo" = "65535" ] && released=1
  if [ "$released" = "1" ] && [ "$lastx" -ge 0 ]; then
    act=$(decide_zone "$lastx" "$lasty")
    printf '%s x=%s y=%s -> %s\n' "$(date +%T)" "$lastx" "$lasty" "$act" >> /mnt/us/memento-input.log
    sync
    printf '%s\n' "$act"
    exit 0
  fi
done
echo NONE
exit 0
