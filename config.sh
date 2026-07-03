# Memento config - edit these for your setup. Sourced by every script.
# POSIX sh / busybox ash. No bashisms.

# --- fbink resolver -----------------------------------------------------
# fbink is installed (KOReader / libkh) but /mnt/us is not on KUAL's PATH, so a
# bare `fbink` call fails with "not found". Resolve it to an absolute path and
# wrap it as a function, so every `fbink ...` call in the scripts just works.
FBINK_BIN=""
for _c in /mnt/us/libkh/bin/fbink /mnt/us/koreader/fbink \
          /mnt/us/extensions/MRInstaller/bin/KHF/fbink /usr/bin/fbink; do
  if [ -x "$_c" ]; then FBINK_BIN="$_c"; break; fi
done
[ -z "$FBINK_BIN" ] && command -v fbink >/dev/null 2>&1 && FBINK_BIN="fbink"
fbink() { "$FBINK_BIN" "$@"; }

# --- HTTP client (TLS) --------------------------------------------------
# LAN sync to the Mac is plain http and busybox wget handles it. Cloud sync
# (GitHub raw) is https; busybox wget often can't do TLS, so prefer curl,
# which KOReader/libkh ship. Resolve an absolute curl, fall back to wget.
DL_BIN=""
for _c in /mnt/us/koreader/curl /mnt/us/libkh/bin/curl /usr/bin/curl; do
  if [ -x "$_c" ]; then DL_BIN="$_c"; break; fi
done
[ -z "$DL_BIN" ] && command -v curl >/dev/null 2>&1 && DL_BIN="curl"
# fetch <url> <outfile> -> 0 on success, nonzero on failure.
fetch() {
  if [ -n "$DL_BIN" ]; then
    "$DL_BIN" -fsSL -o "$2" "$1"   # add -k if your curl rejects GitHub's cert
  else
    wget -q -O "$2" "$1"
  fi
}

# --- Sync ---------------------------------------------------------------
# Where recipes come from. Two supported sources - the URL layout differs,
# so the three vars below move together. sync.sh uses $SERVER$MANIFEST_PATH
# and $SERVER$FILES_PREFIX<name>.md.
#
# (A) GitHub raw - Mac-free, always-on (ACTIVE). Needs the TLS curl above.
SERVER="https://raw.githubusercontent.com/lulvul/memento-recipes/main"
MANIFEST_PATH="/manifest.txt"
FILES_PREFIX="/"
#
# (B) Mac server.py over LAN (fallback if the device curl can't do TLS).
#     Re-check the IP if reassigned: `ipconfig getifaddr en0` on the Mac.
# SERVER="http://192.168.4.90:8000"
# MANIFEST_PATH="/manifest"
# FILES_PREFIX="/files/"

# --- OTA self-update ------------------------------------------------------
# Where the app's own code comes from (update.sh / settings screen). Separate
# repo from the recipes. The repo's pre-commit hook regenerates VERSION and
# app-manifest.txt on every commit; the device compares VERSION to its local
# app-version file and pulls the manifest set when they differ.
APP_SRC="https://raw.githubusercontent.com/lulvul/memento-app/main"

# --- Paths (on the Kindle) ----------------------------------------------
# Where this extension lives. Leave as-is unless you renamed the folder.
APP_DIR="/mnt/us/extensions/memento"
RECIPE_DIR="$APP_DIR/recipes"

# --- Memento game state -------------------------------------------------
# Persistent game state (cook log, later: heirlooms). MUST live outside
# RECIPE_DIR: sync.sh is a one-way, delete-aware pull and would wipe anything
# it manages. This dir is never touched by sync. Back it up to keep the memento.
STATE_DIR="/mnt/us/memento-state"
# Shown on the cover / off-state frame.
COOKBOOK_NAME="The Raque Family Cookbook"
# Cook-mode honesty signal: a cook only logs if cook mode ran at least this
# long (mechanics.md: ~5-10 min minimum). Pre-Phase-0 knob.
COOK_MIN_SECS=300

# Lane-1 mastery tiers: cook-count gates and their tier names, ascending and
# aligned 1:1. From mechanics.md lane 1; pre-Phase-0 knobs (the open question
# there is whether the higher gates should become time-aware - not yet).
TIER_GATES="1 3 5 10"
TIER_NAMES="Logged Drafted Illustrated Mastered"

# --- Input --------------------------------------------------------------
# How the app reads taps/keys. One of: touch | keys | stdin
#   touch -> touchscreen Kindle (most models). Needs the calibration below.
#   keys  -> button Kindle (page-turn buttons / 5-way). Needs KEY_* below.
#   stdin -> dev/testing over SSH: type n/p/s/b/q + Enter.
# Run bin/probe.sh on the device to find out which, and to fill in the
# numbers below.
INPUT_MODE="touch"

# The input device node. Empty = auto-pick the first /dev/input/event* that
# fires. probe.sh prints which node your taps/buttons come from; set it here
# so the app doesn't read the wrong device.
INPUT_DEV="/dev/input/event1"   # Paperwhite 5 touchscreen (from probe)

# (Auto-detected - no longer needs setting.) The app self-frames each event by
# size: 16-byte events on 32-bit Kindles (PW4), 24-byte on 64-bit (PW5). Kept
# here only as a reference knob.
EVENT_TIME_BYTES=8

# --- touch calibration (only used when INPUT_MODE=touch) ----------------
# The raw X range the digitizer reports across the screen width. Tap the far
# left and far right edges in probe.sh and read off the X values. The app maps
# X into thirds: left third = PREV, middle = SELECT, right third = NEXT.
# A short tap in the top-left corner = BACK/QUIT.
TOUCH_X_MIN=0
TOUCH_X_MAX=1236
TOUCH_Y_MIN=0
TOUCH_Y_MAX=1648
# event codes for the touch X/Y axis. Most Kindles use multitouch:
#   ABS_MT_POSITION_X=53, ABS_MT_POSITION_Y=54
# Older single-touch panels use ABS_X=0, ABS_Y=1. probe.sh shows which.
TOUCH_CODE_X=53
TOUCH_CODE_Y=54

# --- key calibration (only used when INPUT_MODE=keys) -------------------
# EV_KEY codes for navigation. Fill from probe.sh (press each button).
KEY_NEXT=""    # page forward
KEY_PREV=""    # page back
KEY_SELECT=""  # open / confirm
KEY_BACK=""    # back / quit

# --- Behavior -----------------------------------------------------------
# Stop the Kindle home-screen framework while the app runs, so it owns the
# screen and input (KOReader does this). On now that fbink is confirmed working.
# The app always restarts the framework on exit (EXIT trap), so a clean quit
# returns you to the library. If a script ever hard-crashes with the framework
# down, the screen stays blank - hold power ~40s to reboot (safe, nothing lost).
STOP_FRAMEWORK=1

# Reserve this many text rows at the bottom for the nav footer.
FOOTER_ROWS=2
