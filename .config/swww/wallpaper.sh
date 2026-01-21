#!/bin/bash

# Ensure this matches your actual directory
WALLPAPER_DIR="$HOME/wallpapers/"

# 1. Generate the list with icons for Rofi
menu() {
    # FIXED: Use the variable WALLPAPER_DIR instead of the malformed path
    find "${WALLPAPER_DIR}" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" \) | while read -r path; do
        # Display the filename but attach the full path as the icon
        echo -en "$(basename "$path")\0icon\x1f$path\n"
    done
}

main() {
    # 2. Call Rofi with icon support enabled
    choice=$(menu | rofi -dmenu -i -p "Select Wallpaper:" -show-icons -config ~/.config/rofi/config.rasi)

    # If user cancels, exit
    [[ -z "$choice" ]] && exit 1

    # Get the full path back
    selected_wallpaper=$(find "${WALLPAPER_DIR}" -name "$choice" | head -n 1)

    # 3. Apply Wallpaper and Colors
    swww img "$selected_wallpaper" --transition-type any --transition-fps 60 --transition-duration .5
    wal -i "$selected_wallpaper" -n --cols16
    
    # 4. Sync UI Components
    swaync-client --reload-css
    pywalfox update
    
    # Update Waybar (triggers the CSS template we created)
    pkill -USR2 waybar
    
    # Update Kitty colors instantly
    cat ~/.cache/wal/colors-kitty.conf > ~/.config/kitty/current-theme.conf
    killall -SIGUSR1 kitty 2>/dev/null

    # 5. Extract colors for CAVA
    # Ensure the file exists before sourcing to avoid errors
    if [ -f "$HOME/.cache/wal/colors.sh" ]; then
        source "$HOME/.cache/wal/colors.sh"
        cava_config="$HOME/.config/cava/config"
        # Using double quotes for sed to allow variable expansion
        sed -i "s/^gradient_color_1 = .*/gradient_color_1 = '$color2'/" "$cava_config"
        sed -i "s/^gradient_color_2 = .*/gradient_color_2 = '$color3'/" "$cava_config"
        pkill -USR2 cava 2>/dev/null
    fi

    # 6. Save current wallpaper reference
    cp "$selected_wallpaper" "$HOME/wallpapers/pywallpaper.jpg"
}

main