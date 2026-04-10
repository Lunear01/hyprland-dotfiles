#!/bin/bash

# Ensure this matches your actual directory
WALLPAPER_DIR="$HOME/wallpapers/"
ROFI_THEME="$HOME/dotfiles/.config/awww/wallpaper-grid.rasi"
ROFI_CONFIG="$HOME/.config/rofi/config.rasi"

menu() {
    find "${WALLPAPER_DIR}" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" \) | while read -r path; do
        # Use the filename as the label and the full path as the icon
        echo -en "$(basename "$path")\0icon\x1f$path\n"
    done
}

main() {
    choice=$(menu | rofi -dmenu \
        -i \
        -p "Select Wallpaper:" \
        -show-icons \
        -theme "$ROFI_THEME" \
        -config "$ROFI_CONFIG")

    [[ -z "$choice" ]] && exit 1

    selected_wallpaper=$(find "${WALLPAPER_DIR}" -name "$choice" | head -n 1)

    if [[ -z "$selected_wallpaper" ]] || [[ ! -f "$selected_wallpaper" ]]; then
        echo "Error: wallpaper not found"
        exit 1
    fi

    uwsm app -- awww img "$selected_wallpaper" --transition-type any --transition-fps 60 --transition-duration 0.5
    
    wal -i "$selected_wallpaper" -q -n --cols16
    
    uwsm app -- swaync-client --reload-css 2>/dev/null || true
    
    pkill -USR2 waybar 2>/dev/null || true
    
    if [ -f "$HOME/.cache/wal/colors-kitty.conf" ]; then
        cp "$HOME/.cache/wal/colors-kitty.conf" "$HOME/.config/kitty/current-theme.conf"
        killall -SIGUSR1 kitty 2>/dev/null || true
    fi

    cp "$selected_wallpaper" "$HOME/wallpapers/pywallpaper.jpg" 2>/dev/null || true
}

main