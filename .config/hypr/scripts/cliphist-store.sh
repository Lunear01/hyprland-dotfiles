#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# cliphist store + trim wrapper.
#   cliphist 0.7.0's `store -max-items N` does NOT trim the existing history
#   (verified: storing with -max-items 2 left 150+ items in place), so the
#   watchers in hyprland.lua call this instead. It stores whatever wl-paste
#   pipes in, then hard-trims the DB to the most-recent $KEEP entries.
#
#   KEEP = 14 = 2 pages of 7 in the SUPER+V picker (see cliphist-rofi.sh LIMIT
#   and cliphist.rasi columns).
# ─────────────────────────────────────────────────────────────────────────
KEEP=14

cliphist store                                    # stdin → history (from wl-paste)
cliphist list | tail -n +$((KEEP + 1)) | cliphist delete 2>/dev/null || true
