#!/bin/sh
# Memento game state - the first on-device persistence layer.
# POSIX sh / busybox ash. Sourced by memento.sh after config.sh.
#
# State lives in $STATE_DIR (config.sh), deliberately OUTSIDE RECIPE_DIR so the
# delete-aware sync.sh never clobbers it. The cook log is append-only: one line
# per real cooking event, tab-separated `YYYY-MM-DD\trecipe-stem`. This is the
# honest record everything else (mastery tiers, heirlooms) will be derived from.
#
# `sync` after each write: unflushed /mnt/us writes are lost on a power-button
# reboot - learned the hard way (see STATUS.md).

COOKS_LOG="$STATE_DIR/cooks.log"

state_init() {
  [ -d "$STATE_DIR" ] || mkdir -p "$STATE_DIR" 2>/dev/null
  [ -f "$COOKS_LOG" ] || : > "$COOKS_LOG"
}

# Append one cooking event. $1 = recipe stem (no .md).
log_cook() {
  state_init
  printf '%s\t%s\n' "$(date +%Y-%m-%d)" "$1" >> "$COOKS_LOG"
  sync
}

# Total cooks across all recipes.
cook_count() {
  state_init
  wc -l < "$COOKS_LOG" | tr -d ' '
}

# Cooks logged for one recipe. $1 = recipe stem.
cooks_for() {
  state_init
  awk -F'\t' -v r="$1" '$2==r{n++} END{print n+0}' "$COOKS_LOG"
}

# ---- mastery (lane 1) --------------------------------------------------
# Tier for a cook count. $1 = count -> echoes the highest tier name whose gate
# is met, or "" for 0 cooks. Walks TIER_GATES/TIER_NAMES in parallel.
mastery_tier() {
  n="$1"; tier=""; i=1
  for g in $TIER_GATES; do
    [ "$n" -ge "$g" ] && tier=$(echo "$TIER_NAMES" | cut -d' ' -f"$i")
    i=$(( i + 1 ))
  done
  echo "$tier"
}

# Proximity to the next tier. $1 = count -> "K more for <Tier>", or "" if the
# top tier is already reached.
next_gate() {
  n="$1"; i=1
  for g in $TIER_GATES; do
    if [ "$n" -lt "$g" ]; then
      echo "$(( g - n )) more for $(echo "$TIER_NAMES" | cut -d' ' -f"$i")"
      return
    fi
    i=$(( i + 1 ))
  done
  echo ""
}
