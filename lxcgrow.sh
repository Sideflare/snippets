#!/bin/bash
# lxcgrow.sh - Monitor LXC root disk usage (ZFS) and permanently expand if threshold exceeded.

# --- List containers ---
echo "=== Available LXC Containers ==="
pct list | awk 'NR>1 {print $1, $2, $3}' | column -t
read -p "Enter the CTID to monitor: " CTID

if ! pct status "$CTID" &>/dev/null; then
    echo "Error: Container $CTID does not exist."
    exit 1
fi

# --- Ask threshold ---
read -p "Enter usage threshold percentage (e.g., 85): " THRESHOLD
if ! [[ "$THRESHOLD" =~ ^[0-9]{2}$ ]] || [ "$THRESHOLD" -lt 1 ] || [ "$THRESHOLD" -gt 99 ]; then
    echo "Invalid percentage. Must be two digits between 01 and 99."
    exit 1
fi

# --- Ask grow amount ---
read -p "Enter amount to increase disk by when exceeded (in GB): " GROW_GB
if ! [[ "$GROW_GB" =~ ^[0-9]+$ ]] || [ "$GROW_GB" -lt 1 ]; then
    echo "Invalid number. Must be >= 1."
    exit 1
fi

# --- Interval menu ---
echo "=== Select Monitoring Interval ==="
select INTERVAL in 5s 10s 15s 30s 1m 2m 5m; do
    if [[ -n "$INTERVAL" ]]; then
        break
    else
        echo "Invalid selection. Try again."
    fi
done

# --- Get initial root disk size ---
BASE_DISK=$(pct config "$CTID" | grep -E 'rootfs' | sed -E 's/.*size=([0-9]+)G.*/\1/')
if ! [[ "$BASE_DISK" =~ ^[0-9]+$ ]]; then
    echo "Error: Could not determine rootfs size."
    exit 1
fi

# Array to hold expansion history
declare -a EXPANSIONS

clear
echo "Monitoring CTID $CTID every $INTERVAL..."
echo "Threshold: $THRESHOLD% | Increase: +${GROW_GB}G | Starting Size: ${BASE_DISK}G"
echo "Expansions are permanent. Press Ctrl+C to stop."
echo "------------------------------------------------------------"

# --- Monitor loop ---
while true; do
    USAGE=$(pct exec "$CTID" -- df -h / | awk 'NR==2 {gsub("%",""); print $5}')
    
    if [[ "$USAGE" -ge "$THRESHOLD" ]]; then
        OLD_SIZE=$BASE_DISK
        BASE_DISK=$((BASE_DISK + GROW_GB))
        
        pct resize "$CTID" rootfs "+${GROW_GB}G" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            ENTRY="$(date '+%F %T') | Usage: ${USAGE}% | Resized: ${OLD_SIZE}G → ${BASE_DISK}G"
            EXPANSIONS+=("$ENTRY")
        fi
    fi

    # Refresh display
    clear
    echo "Monitoring CTID $CTID every $INTERVAL..."
    echo "Threshold: $THRESHOLD% | Increase: +${GROW_GB}G | Current Size: ${BASE_DISK}G"
    echo "Expansions are permanent. Press Ctrl+C to stop."
    echo "------------------------------------------------------------"
    if [ ${#EXPANSIONS[@]} -eq 0 ]; then
        echo "No expansions yet."
    else
        printf "%s\n" "${EXPANSIONS[@]}"
    fi

    sleep "$INTERVAL"
done
