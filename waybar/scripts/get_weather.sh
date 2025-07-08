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
    
    #Fallback to system timezone
    timedatectl | grep "Time zone" | cut -d'/' -f2 | xargs echo
}

get_weather() {
    local location="${1// /+}"  # URL encode spaces
    local timeout=3
    local retries=2
    
    # Try multiple wttr.in servers
    for server in "wttr.in" "v2.wttr.in" "en.wttr.in"; do
        for ((i=1; i<=retries; i++)); do
            # Get compact format with exactly one space between emoji and temp
            text=$(curl -s --max-time $timeout "https://$server/$location?format=%c+%t&m" | sed 's/  */ /g')
            
            # Get detailed tooltip (forcing metric units with ?m)
            tooltip=$(curl -s --max-time $timeout "https://$server/$location?format=%l:+%c+%t+%w+%p&m")
            
            if [[ -n "$text" && -n "$tooltip" ]]; then
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
get_weather "$location"
