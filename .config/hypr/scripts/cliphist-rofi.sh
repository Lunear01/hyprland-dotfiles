#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# Clipboard history picker — cliphist + rofi, Pano/Copyous-style card strip.
#   • cliphist stores everything you copy (see the wl-paste watchers in
#     hyprland.lua autostart). This shows the history in rofi; selecting an
#     entry re-copies it.
#   • Every entry is rendered to a uniform card image so the strip looks
#     consistent:
#       – images    → cover-cropped thumbnail
#       – colors    → solid swatch with the code (any #hex / rgb()/hsl())
#       – text      → the text laid out to fill the whole card
#     Cards are cached in ~/.cache/cliphist/cards (keyed by content) and only
#     missing ones are (re)rendered, in parallel, so repeat opens are instant.
#   • Bound to SUPER+V. Wipe history with SUPER+SHIFT+V (`cliphist wipe`).
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

ROFI_THEME="$HOME/.config/rofi/cliphist.rasi"
CARD_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/cliphist/cards"
LIMIT=60            # most-recent entries shown in the strip
SZ=300              # rendered card size (px, square)
# ImageMagick needs a font *file*, not a family name — resolve via fontconfig.
FONT="$(fc-match -f '%{file}' 'Adwaita Sans' 2>/dev/null || true)"
[ -n "$FONT" ] || FONT="$(fc-match -f '%{file}' sans 2>/dev/null || true)"

if ! command -v cliphist >/dev/null 2>&1; then
    notify-send "Clipboard" "cliphist is not installed (sudo pacman -S cliphist)" 2>/dev/null || true
    exit 1
fi

# Without ImageMagick we can't render cards — fall back to a plain text list.
if ! command -v magick >/dev/null 2>&1; then
    selected="$(cliphist list | rofi -dmenu -i -p "Clipboard" -theme "$ROFI_THEME")"
    [ -z "${selected:-}" ] && exit 0
    printf '%s' "$selected" | cliphist decode | wl-copy
    exit 0
fi

mkdir -p "$CARD_DIR"
find "$CARD_DIR" -type f -mtime +14 -delete 2>/dev/null || true   # prune stale cards

# Card colours follow pywal so the strip tracks the wallpaper. Parse the two
# values out rather than sourcing colors.sh (it has unbound-var side effects).
CARD_BG="#1e2127"
CARD_FG="#e8e8e8"
wal_colors="$HOME/.cache/wal/colors.sh"
if [ -f "$wal_colors" ]; then
    bg="$(sed -n "s/^background='\(.*\)'/\1/p" "$wal_colors")"
    fg="$(sed -n "s/^foreground='\(.*\)'/\1/p" "$wal_colors")"
    [ -n "$bg" ] && CARD_BG="$bg"
    [ -n "$fg" ] && CARD_FG="$fg"
fi

# Render a single card (skips if already cached). Args: outfile kind payload.
#   image → payload is the cliphist id (decoded from the store)
#   color → payload is the colour string (e.g. #1a2b3c, rgb(…))
#   text  → payload is the cliphist id (full text decoded from the store)
render_card() {
    local card="$1" kind="$2" payload="$3" tmp
    [ -f "$card" ] && return 0
    # Output is forced to PNG: ($tmp has no image extension, so magick would
    # otherwise fall back to the input pseudo-format — CAPTION/XC — and fail).
    tmp="$card.tmp.$$"
    case "$kind" in
        image)
            cliphist decode "$payload" 2>/dev/null \
                | magick - -auto-orient -thumbnail "${SZ}x${SZ}^" \
                    -gravity center -extent "${SZ}x${SZ}" "PNG:$tmp" 2>/dev/null || return 0
            ;;
        color)
            # Swatch + a translucent footer carrying the code, so the label is
            # legible on any background colour.
            magick -size "${SZ}x${SZ}" "xc:$payload" \
                \( -size "${SZ}x70" xc:"#000000aa" \) -gravity south -composite \
                -gravity south -fill white -font "$FONT" -pointsize 30 \
                -annotate +0+20 "$payload" "PNG:$tmp" 2>/dev/null || return 0
            ;;
        text)
            local txt
            txt="$(cliphist decode "$payload" 2>/dev/null)"
            [ -z "$txt" ] && return 0
            # caption: word-wraps and auto-sizes the font to fill the box, so
            # short snippets read large and long ones shrink to fit.
            magick -background "$CARD_BG" -fill "$CARD_FG" -font "$FONT" \
                -size "$((SZ-44))x$((SZ-44))" -gravity northwest "caption:$txt" \
                -background "$CARD_BG" -gravity center -extent "${SZ}x${SZ}" "PNG:$tmp" 2>/dev/null || return 0
            ;;
    esac
    [ -f "$tmp" ] && mv "$tmp" "$card"
}
export -f render_card
export SZ FONT CARD_BG CARD_FG

# A copied colour code: a #hex (3/4/6/8 digit) or an rgb()/hsl() function.
is_color() {
    [[ "$1" =~ ^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$ ]] ||
    [[ "$1" =~ ^(rgb|rgba|hsl|hsla)\([0-9.,%[:space:]]+\)$ ]]
}

mapfile -t LINES < <(cliphist list | head -n "$LIMIT")

rofi_in="$(mktemp)"   # rofi input (carries NUL/US metadata — can't live in a var)
jobs="$(mktemp)"      # NUL-delimited render jobs for xargs
trap 'rm -f "$rofi_in" "$jobs"' EXIT

for line in "${LINES[@]}"; do
    id=${line%%$'\t'*}
    content=${line#*$'\t'}
    key="$(printf '%s' "$line" | md5sum)"; key="${key:0:16}"
    card="$CARD_DIR/$key.png"

    if [[ "$content" =~ ^\[\[\ binary\ data\ .*\ (png|jpe?g|bmp|gif|webp)\  ]]; then
        kind=image; payload=$id
    else
        trimmed="${content#"${content%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        if is_color "$trimmed"; then
            kind=color; payload=$trimmed
        else
            kind=text; payload=$id
        fi
    fi

    # Selectable value stays the raw cliphist line so `decode` re-copies the
    # right entry; display drives search; icon is the rendered card.
    printf '%s\0display\x1f%s\x1ficon\x1f%s\n' "$line" "$content" "$card" >>"$rofi_in"
    [ -f "$card" ] || printf '%s\037%s\037%s\0' "$card" "$kind" "$payload" >>"$jobs"
done

# Render any missing cards in parallel before handing the list to rofi.
if [ -s "$jobs" ]; then
    xargs -0 -P "$(nproc)" -n1 bash -c '
        IFS=$'"'"'\037'"'"'; set -f; rec=($1)
        render_card "${rec[0]}" "${rec[1]}" "${rec[2]}"' _ <"$jobs"
fi

# Single horizontal strip docked at the bottom (see cliphist.rasi).
selected="$(rofi -dmenu -i -p "Clipboard" -show-icons -theme "$ROFI_THEME" <"$rofi_in")"

[ -z "${selected:-}" ] && exit 0

printf '%s' "$selected" | cliphist decode | wl-copy
