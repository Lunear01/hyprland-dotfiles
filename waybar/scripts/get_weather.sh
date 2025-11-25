#!/usr/bin/env bash

# Weather script with automatic location detection
CACHE_DIR="$HOME/.cache/weather"
mkdir -p "$CACHE_DIR"

get_location() {
    # Try multiple geolocation services
    local services=(
        "curl -s https://ipinfo.io/city"
        "curl -s https://ifconfig.co/city" 
        "curl -s https://ipapi.co/city"
    )
    
    for service in "${services[@]}"; do
        location=$(eval "$service" 2>/dev/null | tr -d '\n')
        if [[ -n "$location" ]]; then
            echo "$location"
            return 0
        fi
    done
    
    # Fallback to system timezone
    timedatectl show --property=Timezone --value 2>/dev/null | cut -d'/' -f2
}

get_weather() {
    local location="${1// /+}"  # URL encode spaces
    local timeout=3
    local retries=2
    
    # Try multiple wttr.in servers
    for server in "wttr.in" "v2.wttr.in" "en.wttr.in"; do
        for ((i=1; i<=retries; i++)); do
            # Get compact format with exactly one space between emoji and temp
            text=$(curl -s --max-time $timeout "https://$server/$location?format=%c+%t&m" | sed 's/  */ /g' | tr -d '\n')
            
            # Get detailed tooltip (forcing metric units with ?m)
            tooltip=$(curl -s --max-time $timeout "https://$server/$location?format=%l:+%c+%t+%w+%p&m" | tr -d '\n')
            
            # Debug output - remove this after testing
            echo "DEBUG: server=$server, text='$text', tooltip='$tooltip'" >&2
            
            # FIX: Check if we have ANY valid data
            if [[ -n "$text" || -n "$tooltip" ]]; then
                # If text is empty but tooltip has data, extract basic info from tooltip
                if [[ -z "$text" && -n "$tooltip" ]]; then
                    # Extract just the emoji and temperature from tooltip
                    text=$(echo "$tooltip" | grep -o '[^:]*:[^+]*+[^°]*°C' | sed 's/.*: //' | head -1)
                fi
                
                # Ensure we have at least something for text
                if [[ -z "$text" ]]; then
                    text="⛅"
                fi
                
                echo "{\"text\":\"$text\", \"tooltip\":\"$tooltip\"}"
                return 0
            fi
            sleep 1
        done
    done
    
    # Final fallback
    echo '{"text":"🌡️", "tooltip":"Weather data unavailable"}'
}

# Main execution
location=$(get_location)
echo "Detected location: $location" >&2
get_weather "$location"
