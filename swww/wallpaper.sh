#!/bin/sh
# Changes wallpaper with swww + applies Pywal colors

if [ $# -lt 1 ] || [ ! -d "$1" ]; then
    printf "Usage:\n\t\e[1m%s\e[0m \e[4mDIRECTORY\e[0m\n" "$0"
    printf "\nApplies wallpaper with 'outer' transition + Pywal colors\n"
    exit 1
fi

# Select random image
WALLPAPER=$(find "$1" -type f -print0 | shuf -z -n 1 | tr -d '\0')


# Apply wallpaper with swww
swww img "$WALLPAPER" \
    --transition-type outer \
    --transition-fps 60 \
    --transition-duration 1.5 \
    --transition-pos center

# Generate Pywal color scheme
wal -i "$WALLPAPER" -n 2>/dev/null  # -n prevents terminal color changes

# Reload Waybar (if running)
if pgrep -x "waybar" >/dev/null; then
    killall -9 waybar
    killall -9 swaync
    swaync & 
    waybar &
fi

