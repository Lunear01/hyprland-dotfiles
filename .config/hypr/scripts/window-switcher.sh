#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# Window switcher — hyprctl + rofi, GNOME alt-tab-style app picker.
#   • Lists every open window (across all workspaces) via `hyprctl clients`,
#     ordered most-recently-used first using Hyprland's focusHistoryID
#     (0 = current window, 1 = previous, …).
#   • The previous window is pre-selected, so a quick SUPER+TAB then Enter
#     jumps straight to your last app — just like GNOME's switcher.
#   • Icons are resolved from each window's class via the icon theme
#     (rofi -show-icons), titles drive fuzzy search.
#   • Selecting a window focuses it. Under the Lua config, raw
#     `hyprctl dispatch focuswindow …` is evaluated as Lua and fails, so we
#     focus via the Lua expression `hl.dsp.focus({ window = "address:…" })`.
#   • Bound to SUPER+TAB (see hyprland.lua). Theme tracks pywal via the
#     shared rofi config.
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

ROFI_THEME="$HOME/.config/rofi/config.rasi"

# Build the rofi input into a temp FILE: each row uses rofi's extended format
#   <address>\0display\x1f<class — title>\x1ficon\x1f<class>
# The NUL separating the value from its metadata can't survive a shell variable
# (command substitution strips NUL bytes), so we write to a file — same approach
# as cliphist-rofi.sh.
rofi_in="$(mktemp)"
trap 'rm -f "$rofi_in"' EXIT

hyprctl clients -j | python3 -c '
import json, sys

wins = [w for w in json.load(sys.stdin) if w.get("title") and w.get("mapped", True)]
# focusHistoryID: 0 = currently focused. Sort MRU-first but drop the current
# window to the bottom so the *previous* window lands on row 0 (GNOME-like).
def order(w):
    fh = w.get("focusHistoryID", 9999)
    return (fh == 0, fh)          # current window sinks to the end
wins.sort(key=order)

for w in wins:
    cls   = w.get("class") or w.get("initialClass") or "?"
    title = (w.get("title") or "").replace("\n", " ").strip()
    addr  = w["address"]
    ws    = w.get("workspace", {}).get("name", "")
    label = f"{cls} — {title}"
    if ws:
        label += f"  ·  {ws}"
    sys.stdout.write(f"{addr}\0display\x1f{label}\x1ficon\x1f{cls}\n")
' > "$rofi_in"

[ -s "$rofi_in" ] || exit 0

# Row 0 is the previous window (current was sunk to the bottom) — preselect it.
# rofi's extended-row format returns the value before the NUL (the address),
# not the displayed label.
addr="$(
    rofi -dmenu -i -p "Windows" -show-icons -selected-row 0 \
         -theme "$ROFI_THEME" <"$rofi_in"
)"

[ -z "${addr:-}" ] && exit 0

hyprctl dispatch "hl.dsp.focus({ window = \"address:$addr\" })" >/dev/null
