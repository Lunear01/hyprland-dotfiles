#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# Clipboard history picker — cliphist + rofi (handles text AND images)
#   • cliphist stores everything you copy (see the wl-paste watchers in
#     hyprland.lua autostart).
#   • This shows the history in rofi; selecting an entry re-copies it.
#   • Bound to SUPER+V. Wipe history with SUPER+SHIFT+V (`cliphist wipe`).
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

ROFI_CONFIG="$HOME/.config/rofi/config.rasi"

if ! command -v cliphist >/dev/null 2>&1; then
    notify-send "Clipboard" "cliphist is not installed (sudo pacman -S cliphist)" 2>/dev/null || true
    exit 1
fi

# Single-column, no-icon layout reads better for clipboard entries than the
# launcher's grid. Selected line keeps cliphist's id prefix so `decode` works.
selected="$(cliphist list | rofi -dmenu -i -p "Clipboard" \
    -config "$ROFI_CONFIG" \
    -theme-str 'listview { columns: 1; lines: 10; } element-icon { enabled: false; } window { width: 700px; }')"

[ -z "${selected:-}" ] && exit 0

printf '%s' "$selected" | cliphist decode | wl-copy
