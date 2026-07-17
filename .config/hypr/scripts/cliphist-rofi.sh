#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# Clipboard history picker — cliphist + rofi, Pano-style card grid.
#   • cliphist stores everything you copy (see the wl-paste watchers in
#     hyprland.lua autostart). This shows the history in rofi; selecting an
#     entry re-copies it.
#   • Every entry renders to a uniform card image:
#       – images → big cover-cropped preview
#       – colors → solid swatch with the code
#       – text   → the text laid out at a FIXED font size (readable; long text
#                  clips at the top instead of shrinking to nothing)
#     Cards are cached in ~/.cache/cliphist/cards (keyed by content) and only
#     missing ones are (re)rendered, in parallel, so repeat opens are instant.
#     Text uses a fixed -pointsize so magick skips the slow caption auto-fit
#     search (~1.7s/card) — renders drop to ~0.3s and cache to zero.
#   • Bound to SUPER+V. Wipe history with SUPER+SHIFT+V (`cliphist wipe`).
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

ROFI_THEME="$HOME/.config/rofi/cliphist.rasi"
CARD_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/cliphist/cards"
LIMIT=15            # most-recent entries shown (3 rows of 5). Matches store cap.
SZ=300             # card source resolution (px, square). rofi downscales to the
                   # rasi element-icon size; don't lower or cached cards mismatch.
PT=21              # fixed text point size — legible at the displayed card size.
# ImageMagick needs a font *file*, not a family name — resolve via fontconfig.
FONT="$(fc-match -f '%{file}' 'Adwaita Mono' 2>/dev/null || true)"
[ -n "$FONT" ] || FONT="$(fc-match -f '%{file}' monospace 2>/dev/null || true)"
[ -n "$FONT" ] || FONT="$(fc-match -f '%{file}' sans 2>/dev/null || true)"
# Adwaita Mono has no CJK glyphs (they'd render as blank tofu). Noto Sans Mono
# CJK covers Latin + CJK in one file, so caption: stays left-aligned; used only
# for entries that actually contain CJK (see render_card). TC variant for
# Traditional-Chinese glyph forms.
CJKFONT="$(fc-match -f '%{file}' 'Noto Sans Mono CJK TC' 2>/dev/null || true)"
[ -n "$CJKFONT" ] || CJKFONT="$(fc-match -f '%{file}' 'Noto Sans CJK TC' 2>/dev/null || true)"
[ -n "$CJKFONT" ] || CJKFONT="$FONT"

if ! command -v cliphist >/dev/null 2>&1; then
    notify-send "Clipboard" "cliphist is not installed (sudo pacman -S cliphist)" 2>/dev/null || true
    exit 1
fi

# Without ImageMagick we can't render cards — fall back to a plain text list.
if ! command -v magick >/dev/null 2>&1; then
    selected="$(cliphist list | rofi -dmenu -i -p "Clipboard")"
    [ -z "${selected:-}" ] && exit 0
    printf '%s' "$selected" | cliphist decode | wl-copy
    exit 0
fi

mkdir -p "$CARD_DIR"
find "$CARD_DIR" -type f -mtime +14 -delete 2>/dev/null || true   # prune stale cards

# Card colours follow pywal so the strip tracks the wallpaper.
CARD_BG="#1e2127"; CARD_FG="#e8e8e8"
wal_colors="$HOME/.cache/wal/colors.sh"
if [ -f "$wal_colors" ]; then
    bg="$(sed -n "s/^background='\(.*\)'/\1/p" "$wal_colors")"
    fg="$(sed -n "s/^foreground='\(.*\)'/\1/p" "$wal_colors")"
    [ -n "$bg" ] && CARD_BG="$bg"
    [ -n "$fg" ] && CARD_FG="$fg"
fi

# Render one card (skips if cached). Args: outfile kind payload.
render_card() {
    local card="$1" kind="$2" payload="$3" tmp
    [ -f "$card" ] && return 0
    tmp="$card.tmp.$$"
    case "$kind" in
        image)
            cliphist decode "$payload" 2>/dev/null \
                | magick - -auto-orient -thumbnail "${SZ}x${SZ}^" \
                    -gravity center -extent "${SZ}x${SZ}" "PNG:$tmp" 2>/dev/null || return 0
            ;;
        color)
            magick -size "${SZ}x${SZ}" "xc:$payload" \
                \( -size "${SZ}x76" xc:"#000000aa" \) -gravity south -composite \
                -gravity south -fill white -font "$FONT" -pointsize 30 \
                -annotate +0+22 "$payload" "PNG:$tmp" 2>/dev/null || return 0
            ;;
        text)
            local txt f="$FONT"
            txt="$(cliphist decode "$payload" 2>/dev/null)"
            [ -z "$txt" ] && return 0
            # CJK / kana / hangul / fullwidth → switch to the Noto Mono CJK file
            # so the glyphs render instead of blank tofu.
            printf '%s' "$txt" | grep -qP '[\x{3000}-\x{9fff}\x{ac00}-\x{d7a3}\x{3040}-\x{30ff}\x{ff00}-\x{ffef}]' \
                && f="$CJKFONT"
            # Fixed -pointsize → no auto-fit search: fast AND legible. Long text
            # overflows and clips at the box bottom rather than shrinking away.
            # Transparent background so the rasi card tile shows through — the
            # text reads as a card, not floating text on the dark panel.
            magick -background none -fill "$CARD_FG" -font "$f" \
                -pointsize "$PT" -size "$((SZ-40))x$((SZ-40))" -gravity northwest \
                "caption:$txt" -background none -gravity northwest \
                -extent "${SZ}x${SZ}" "PNG:$tmp" 2>/dev/null || return 0
            ;;
    esac
    [ -f "$tmp" ] && mv "$tmp" "$card"
}
export -f render_card
export SZ PT FONT CJKFONT CARD_BG CARD_FG

# A copied colour code: a #hex (3/4/6/8 digit) or an rgb()/hsl() function.
is_color() {
    [[ "$1" =~ ^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$ ]] ||
    [[ "$1" =~ ^(rgb|rgba|hsl|hsla)\([0-9.,%[:space:]]+\)$ ]]
}

mapfile -t LINES < <(cliphist list | head -n "$LIMIT")
[ "${#LINES[@]}" -eq 0 ] && exit 0

rofi_in="$(mktemp)"; jobs="$(mktemp)"
trap 'rm -f "$rofi_in" "$jobs"' EXIT

for line in "${LINES[@]}"; do
    id=${line%%$'\t'*}
    content=${line#*$'\t'}
    key="$(printf '%s' "$line" | md5sum)"; card="$CARD_DIR/${key:0:16}.png"

    if [[ "$content" =~ ^\[\[\ binary\ data\ .*\ (png|jpe?g|bmp|gif|webp)\  ]]; then
        kind=image; payload=$id
    else
        trimmed="${content#"${content%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        if is_color "$trimmed"; then kind=color; payload=$trimmed
        else kind=text; payload=$id; fi
    fi

    # Selectable value stays the raw cliphist line so decode re-copies the exact
    # entry; display drives search; icon is the rendered card.
    printf '%s\0display\x1f%s\x1ficon\x1f%s\n' "$line" "$content" "$card" >>"$rofi_in"
    [ -f "$card" ] || printf '%s\037%s\037%s\0' "$card" "$kind" "$payload" >>"$jobs"
done

# Render any missing cards in parallel before handing the list to rofi.
if [ -s "$jobs" ]; then
    xargs -0 -P "$(nproc)" -n1 bash -c '
        IFS=$'"'"'\037'"'"'; set -f; rec=($1)
        render_card "${rec[0]}" "${rec[1]}" "${rec[2]}"' _ <"$jobs"
fi

selected="$(rofi -dmenu -i -p "Clipboard" -show-icons -theme "$ROFI_THEME" <"$rofi_in")"
[ -z "${selected:-}" ] && exit 0

printf '%s' "$selected" | cliphist decode | wl-copy
