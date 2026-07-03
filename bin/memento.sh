#!/bin/sh
# Memento - persistent standalone recipe app for jailbroken Kindle.
# Launched from KUAL; runs its own render + input loop until you quit.
# No KOReader: this app owns its rendering (fbink) and input (/dev/input).
HERE=$(dirname "$0")
APPDIR=$(cd "$HERE/.." && pwd)
. "$APPDIR/config.sh"
. "$HERE/lib.sh"
. "$HERE/state.sh"

[ -n "$FBINK_BIN" ] || { echo "fbink not found - checked libkh/koreader/usr paths"; exit 1; }

DBG=/mnt/us/memento-run.log
dbg() { echo "$(date +%T) $1" >> "$DBG"; sync; }
: > "$DBG"; dbg "launch FBINK_BIN=$FBINK_BIN"

# Keep the Amazon framework RUNNING (so powerd/suspend work and the e-ink keeps
# our last frame when you sleep), but freeze the window manager (awesome) and
# hide the status bar (pillow) so the home screen neither repaints over us nor
# opens books on our taps. SIGCONT restores it reliably on exit - no fragile
# service restart, no power-button freeze.
FROZEN=0
SLEEP_PID=""
cleanup() {
  [ -n "$SLEEP_PID" ] && kill "$SLEEP_PID" >/dev/null 2>&1
  killall lipc-wait-event >/dev/null 2>&1
  [ "$FROZEN" = "1" ] && killall -CONT awesome >/dev/null 2>&1
  lipc-set-prop com.lab126.pillow disableEnablePillow enable >/dev/null 2>&1
  lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home >/dev/null 2>&1
  dbg "cleanup: thawed UI"
}
trap cleanup EXIT

lipc-set-prop com.lab126.pillow disableEnablePillow disable >/dev/null 2>&1
killall -STOP awesome >/dev/null 2>&1 && FROZEN=1
dbg "froze UI FROZEN=$FROZEN"
sleep 1

input() { sh "$HERE/input.sh"; }

geom_load
dbg "geom COLS=$COLS ROWS=$ROWS LPP=$LPP"

state_init

# sync on launch (non-fatal if the Mac is offline)
sh "$HERE/sync.sh"
build_list

# Force the cover onto the screen whenever the device goes to sleep, so the
# off-state is always the memento (book name + cook count), not whatever screen
# you happened to be on. powerd emits goingToScreenSaver on the power button;
# we redraw the cover in that window before the panel freezes (KOReader draws
# its sleep screen the same way). Runs in the background alongside the input
# loop; cleanup() kills it. NOTE: needs on-device verification - the event name
# and the draw-before-freeze timing are the only unproven parts of this build.
sleep_watch() {
  command -v lipc-wait-event >/dev/null 2>&1 || { dbg "sleep_watch: no lipc-wait-event"; return 0; }
  lipc-wait-event -m -s 0 com.lab126.powerd '*' 2>/dev/null | while read -r ev; do
    case "$ev" in
      *goingToScreenSaver*) draw_cover; dbg "sleep: drew cover on $ev" ;;
    esac
  done
}
sleep_watch & SLEEP_PID=$!
dbg "sleep_watch pid=$SLEEP_PID"

if [ "${LIST_COUNT:-0}" -lt 1 ]; then
  msg "No recipes yet.

Run server.py on the Mac,
check the IP in config.sh,
then relaunch Memento."
  sleep 5
  exit 0
fi

# state
view="cover"    # cover | list | recipe | cooking | settings
sel=0           # selected list index (0-based)
rname=""        # open recipe stem
rpage=0         # recipe page (0-based)
cook_start=0    # epoch seconds when cook mode started

redraw() {
  case "$view" in
    cover)    draw_cover ;;
    list)     lpage=$(( sel / LPP )); draw_list "$sel" "$lpage" ;;
    recipe)   draw_recipe "$rname" "$rpage"; rpage="$RPAGE" ;;   # take clamped page back
    cooking)  draw_cooking "$rname" ;;
    settings) draw_settings ;;
  esac
}

redraw
while :; do
  act=$(input)
  dbg "view=$view act=$act sel=$sel rpage=$rpage"
  case "$view" in
  cover)
    case "$act" in
      SELECT|NEXT|PREV) view="list" ;;   # tap the cover to open the book
      MENU)             view="settings" ;;   # bottom strip = settings
      BACK|QUIT)        break ;;
      *)                continue ;;
    esac ;;
  settings)
    case "$act" in
      SELECT)
        # OTA self-update. update.sh stages+verifies+installs and draws its own
        # status; on success (rc 0) re-exec so we're immediately running the new
        # build. exec skips the EXIT trap on purpose: the WM stays frozen and the
        # new instance's freeze calls are idempotent, but the old background
        # sleep_watch must die here or it lingers with the old code.
        sh "$HERE/update.sh"
        if [ "$?" -eq 0 ]; then
          dbg "update applied -> exec restart"
          [ -n "$SLEEP_PID" ] && kill "$SLEEP_PID" >/dev/null 2>&1
          killall lipc-wait-event >/dev/null 2>&1
          exec sh "$APPDIR/bin/memento.sh"
        fi ;;                            # update.sh already showed the status
      PREV)      sh "$HERE/sync.sh"; build_list ;;   # left = re-sync recipes
      BACK|QUIT) view="cover" ;;
      *)         continue ;;
    esac ;;
  list)
    case "$act" in
      PREV)      sel=$(( sel > 0 ? sel - 1 : LIST_COUNT - 1 )) ;;
      NEXT)      sel=$(( sel < LIST_COUNT - 1 ? sel + 1 : 0 )) ;;
      SELECT)    rname=$(sed -n "$(( sel + 1 ))p" "$LISTFILE"); rpage=0; view="recipe" ;;
      BACK|QUIT) view="cover" ;;          # top strip backs out to the cover
      *)         continue ;;
    esac ;;
  recipe)
    case "$act" in
      NEXT)      rpage=$(( rpage + 1 )) ;;          # draw_recipe clamps to last page
      PREV)      if [ "$rpage" -gt 0 ]; then rpage=$(( rpage - 1 )); else view="list"; fi ;;
      SELECT)    cook_start=$(date +%s); view="cooking" ;;   # center tap = start cooking
      BACK|QUIT) view="list" ;;
      *)         continue ;;
    esac ;;
  cooking)
    case "$act" in
      SELECT)
        el=$(( $(date +%s) - cook_start ))
        if [ "$el" -ge "$COOK_MIN_SECS" ]; then
          log_cook "$rname"
          n=$(cooks_for "$rname")
          dbg "cook logged $rname el=$el total=$(cook_count) n=$n"
          # level-up moment: announce a tier crossing, else just "Logged"
          tier=$(mastery_tier "$n")
          if [ "$tier" != "$(mastery_tier $(( n - 1 )))" ] && [ -n "$tier" ]; then
            head="Now $tier!"
          else
            head="Logged"
          fi
          gap=$(next_gate "$n")
          [ -n "$gap" ] && sub="$n cooks   $gap" || sub="$n cooks"
          msg "$head

$(name_to_title "$rname")
$sub"
          sleep 2
          view="recipe"
        else
          left=$(( (COOK_MIN_SECS - el + 59) / 60 ))
          msg "Keep cooking

~$left min left
in cook mode"
          sleep 2
        fi ;;                              # stay in cooking until the gate passes
      BACK|QUIT) view="recipe" ;;          # cancel the cook
      *)         continue ;;
    esac ;;
  esac
  redraw
done

dbg "loop broke -> exiting, cleanup will thaw UI"
exit 0
