#!/bin/bash
WAYBAR_DIR="$HOME/.config/waybar"
STYLECSS="$WAYBAR_DIR/style.css"
CONFIG="$WAYBAR_DIR/config"
ASSETS="$WAYBAR_DIR/assets"
THEMES="$WAYBAR_DIR/themes"

menu() {
    find "${ASSETS}" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" \) | awk '{print "img:"$0}'
}

main() {
    choice=$(menu | wofi -c ~/.config/wofi/waybar -s ~/.config/wofi/style-waybar.css --show dmenu --prompt "  Select Waybar (Scroll with Arrows)" -n)
    selected_wallpaper=$(echo "$choice" | sed 's/^img://')
    echo "$selected_wallpaper"

    # Map asset filename (without extension) to theme directory name
    # "main" is the only case where the asset name differs from the theme dir
    declare -A theme_map=(
        ["experimental"]="experimental"
        ["main"]="default"
        ["line"]="line"
        ["zen"]="zen"
    )

    key=$(basename "$selected_wallpaper" | sed 's/\.[^.]*$//')
    theme="${theme_map[$key]}"
    [[ -z "$theme" ]] && exit 0

    cat "$THEMES/$theme/style-$theme.css" > "$STYLECSS"
    cat "$THEMES/$theme/config-$theme" > "$CONFIG"
    pkill waybar && waybar
}

main
