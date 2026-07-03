# Memento shared rendering library. POSIX sh / busybox ash.
# Sourced by memento.sh. Assumes config.sh is already sourced.
#
# Rendering rule: compose a full screen as one multi-line string and draw it
# with a single `fbink -c` call. One e-ink refresh per screen, no flicker.
# Padding is built by direct string concatenation, never via $(...) capture,
# because command substitution strips trailing newlines.

# ---- screen geometry ---------------------------------------------------
# Populate COLS / ROWS / VW / VH from fbink's state dump. `fbink -e` prints
# shell-assignable variables (MAXCOLS, MAXROWS, viewWidth, viewHeight, ...).
geom_load() {
  eval "$(fbink -e 2>/dev/null | tr ';' '\n' | grep -E '^[A-Za-z_][A-Za-z0-9_]*=')" 2>/dev/null
  COLS="${MAXCOLS:-}"
  ROWS="${MAXROWS:-}"
  VW="${viewWidth:-${screenWidth:-}}"
  VH="${viewHeight:-${screenHeight:-}}"
  [ -n "$COLS" ] || COLS=30
  [ -n "$ROWS" ] || ROWS=40
  [ -n "$VW" ] || VW=600
  [ -n "$VH" ] || VH=800
  WRAP=$(( COLS - 2 ))
  [ "$WRAP" -lt 10 ] && WRAP=10
  LPP=$(( ROWS - FOOTER_ROWS - 1 ))   # body lines per page
  [ "$LPP" -lt 3 ] && LPP=3
}

name_to_title() {  # mac-and-cheese -> mac and cheese
  printf '%s' "$1" | sed 's/-/ /g'
}

# append $2 blank lines to the variable named $1
pad_lines() {  # $1 = varname, $2 = count
  _v=$(eval "printf '%s' \"\$$1\"")
  _n=0
  while [ "$_n" -lt "$2" ]; do _v="$_v
"; _n=$(( _n + 1 )); done
  eval "$1=\$_v"
}

# strip markdown markers to plain text, then word-wrap to $WRAP columns
recipe_wrapped() {  # $1 = name (no .md) -> wrapped plain text on stdout
  f="$RECIPE_DIR/$1.md"
  [ -f "$f" ] || { printf 'Recipe not found:\n%s\n' "$1"; return 1; }
  sed -e 's/^#\{1,6\}[[:space:]]*//' -e 's/\*\*//g' -e 's/`//g' "$f" \
    | { fold -s -w "$WRAP" 2>/dev/null || fold -w "$WRAP"; }
}

# ---- list of synced recipes -------------------------------------------
# Writes one recipe stem per line to $LISTFILE, sets $LIST_COUNT.
build_list() {
  LISTFILE="/tmp/memento.list"
  : > "$LISTFILE"
  for p in "$RECIPE_DIR"/*.md; do
    [ -f "$p" ] || continue
    b=$(basename "$p")
    printf '%s\n' "${b%.md}" >> "$LISTFILE"
  done
  LIST_COUNT=$(wc -l < "$LISTFILE" | tr -d ' ')
}

# ---- draw a centered message (sync status, errors, splash) -------------
msg() {  # $1 = text (may contain \n)
  fbink -c -m -M "$1" >/dev/null 2>&1
}

# ---- draw the cover / off-state frame ---------------------------------
# The memento home screen and the frame that persists when the device sleeps.
# Self-contained: recomputes its counts from disk so the sleep-watcher can call
# it from a background subshell. Reads STATE_DIR cooks + RECIPE_DIR file count.
draw_cover() {
  cooks=$(cook_count)
  recipes=$(ls "$RECIPE_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')
  fbink -c -m -M "$COOKBOOK_NAME


$cooks cooks       $recipes recipes" >/dev/null 2>&1
}

# ---- draw the settings screen ------------------------------------------
# Version comes from $APP_DIR/app-version, written by update.sh (and seeded by
# the initial USB deploy). Counts recomputed from disk like draw_cover.
draw_settings() {
  v=$(tr -d ' \r\n' < "$APP_DIR/app-version" 2>/dev/null)
  cooks=$(cook_count)
  recipes=$(ls "$RECIPE_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')
  fbink -c -m -M "SETTINGS

software ${v:-unknown}
$cooks cooks   $recipes recipes

center = update software
left = sync recipes

top = back" >/dev/null 2>&1
}

# ---- draw the cook-mode screen ----------------------------------------
# $1 = recipe stem. Shown while the cook-mode timer runs; the honesty gate
# (COOK_MIN_SECS) is checked in memento.sh when the player taps done.
draw_cooking() {
  title=$(name_to_title "$1")
  mins=$(( COOK_MIN_SECS / 60 ))
  fbink -c -m -M "Cooking

$title

Tap center when done
(cook mode needs $mins min)

top = cancel" >/dev/null 2>&1
}

# ---- draw the recipe list ---------------------------------------------
# $1 = selected index (0-based), $2 = list page (0-based). Sets LIST_PAGES.
draw_list() {
  sel="$1"; page="$2"
  LIST_PAGES=$(( (LIST_COUNT + LPP - 1) / LPP ))
  [ "$LIST_PAGES" -lt 1 ] && LIST_PAGES=1
  a=$(( page * LPP + 1 ))
  b=$(( a + LPP - 1 ))
  [ "$b" -gt "$LIST_COUNT" ] && b="$LIST_COUNT"

  scr="MEMENTO   $LIST_COUNT recipes
"
  i="$a"
  while [ "$i" -le "$b" ]; do
    title=$(name_to_title "$(sed -n "${i}p" "$LISTFILE")")
    if [ "$(( i - 1 ))" -eq "$sel" ]; then
      scr="$scr
> $title"
    else
      scr="$scr
  $title"
    fi
    i=$(( i + 1 ))
  done

  drawn=$(( b - a + 1 ))
  [ "$drawn" -lt 0 ] && drawn=0
  pad=$(( LPP - drawn - 1 ))    # -1 for the title line
  [ "$pad" -lt 0 ] && pad=0
  pad_lines scr "$pad"
  scr="$scr
L=up  R=down  mid=open
top=cover   bottom=settings"
  fbink -c -x 1 -y 1 "$scr" >/dev/null 2>&1
}

# ---- draw one page of a recipe ----------------------------------------
# $1 = name, $2 = page (0-based). Clamps page, sets TOTAL_PAGES.
draw_recipe() {
  name="$1"; page="$2"
  tmp="/tmp/memento.page"
  recipe_wrapped "$name" > "$tmp"
  L=$(wc -l < "$tmp" | tr -d ' ')
  [ "$L" -lt 1 ] && L=1
  TOTAL_PAGES=$(( (L + LPP - 1) / LPP ))
  [ "$TOTAL_PAGES" -lt 1 ] && TOTAL_PAGES=1
  [ "$page" -ge "$TOTAL_PAGES" ] && page=$(( TOTAL_PAGES - 1 ))
  [ "$page" -lt 0 ] && page=0
  RPAGE="$page"   # report the clamped page back to caller
  a=$(( page * LPP + 1 ))
  b=$(( a + LPP - 1 ))
  scr=$(sed -n "${a},${b}p" "$tmp")

  drawn=$(( b > L ? L - a + 1 : LPP ))
  [ "$drawn" -lt 0 ] && drawn=0
  pad=$(( LPP - drawn ))
  [ "$pad" -lt 0 ] && pad=0
  pad_lines scr "$pad"
  # mastery readout on the line the footer would otherwise leave blank
  n=$(cooks_for "$name")
  if [ "$n" -lt 1 ]; then
    mline="center tap = cook this"
  else
    mline="$n cooks   $(mastery_tier "$n")"
  fi
  scr="$scr
$mline
top=list   L=prev  R=next   pg $(( page + 1 ))/$TOTAL_PAGES"
  fbink -c -x 1 -y 1 "$scr" >/dev/null 2>&1
}
