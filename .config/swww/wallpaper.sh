#!/bin/bash

# Ensure this matches your actual directory
WALLPAPER_DIR="$HOME/wallpapers/"
ROFI_THEME="~/dotfiles/.config/swww/wallpaper-grid.rasi" # Standard pywal rofi theme path

# 1. Generate the list with icons for Rofi
menu() {
    find "${WALLPAPER_DIR}" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" \) | while read -r path; do
        # Use the filename as the label and the full path as the icon
        echo -en "$(basename "$path")\0icon\x1f$path\n"
    done
}

main() {
    # 2. Call Rofi with pywal colors integrated via the -theme flag
    # We pass the pywal-generated Rasi file to override your base theme colors
    choice=$(menu | rofi -dmenu \
        -i \
        -p "Select Wallpaper:" \
        -show-icons \
        -theme "$ROFI_THEME" \
        -config ~/.config/rofi/config.rasi)

    # If user cancels, exit
    [[ -z "$choice" ]] && exit 1

    # Get the full path back
    selected_wallpaper=$(find "${WALLPAPER_DIR}" -name "$choice" | head -n 1)

    # 3. Apply Wallpaper (Using uwsm app prefix for proper session management)
    uwsm app -- swww img "$selected_wallpaper" --transition-type any --transition-fps 60 --transition-duration .5
    
    # 4. Generate Colors with Pywal
    # -q for quiet, -n to skip setting wallpaper (swww handles it), --cols16 for full palette
    wal -i "$selected_wallpaper" -q -n --cols16
    
    # 5. Sync UI Components
    uwsm app -- swaync-client --reload-css
    
    # Refresh Waybar colors
    pkill -USR2 waybar
    
    # Update Kitty colors instantly
    if [ -f "$HOME/.cache/wal/colors-kitty.conf" ]; then
        cp "$HOME/.cache/wal/colors-kitty.conf" "$HOME/.config/kitty/current-theme.conf"
        killall -SIGUSR1 kitty 2>/dev/null
    fi

    # 6. Extract colors for CAVA
    if [ -f "$HOME/.cache/wal/colors.sh" ]; then
        source "$HOME/.cache/wal/colors.sh"
        cava_config="$HOME/.config/cava/config"
        # Using sed to inject the new hex colors into cava config
        sed -i "s/^gradient_color_1 = .*/gradient_color_1 = '$color2'/" "$cava_config"
        sed -i "s/^gradient_color_2 = .*/gradient_color_2 = '$color3'/" "$cava_config"
        pkill -USR2 cava 2>/dev/null
    fi

    # 7. Save current wallpaper reference
    cp "$selected_wallpaper" "$HOME/wallpapers/pywallpaper.jpg"
}

main