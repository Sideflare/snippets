#!/bin/bash
# lxcgrow.sh — Monitor an LXC container and grow its ZFS root disk when usage exceeds threshold.

# Safety: Require root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo $0)"
    exit 1
fi

# --- Get container list ---
echo "=== Available Containers ==="
pct list | awk 'NR>1 {print $1" - "$2" ("$3")"}'
echo
read -p "Enter container ID to monitor: " CTID

if ! pct status "$CTID" &>/dev/null; then
    echo "Container $CTID not found."
    exit 1
fi

# --- Get user threshold ---
read -p "Enter usage threshold percentage (e.g., 85): " THRESHOLD
if ! [[ "$THRESHOLD" =~ ^[0-9]{2}$ ]]; then
    echo "Invalid threshold format."
    exit 1
fi

# --- Get growth size ---
read -p "Enter growth amount in GB (e.g., 1): " GROW_GB
if ! [[ "$GROW_GB" =~ ^[0-9]+$ ]]; then
    echo "Invalid growth amount."
    exit 1
fi

# --- Interval selection ---
echo
echo "=== Select Monitoring Interval ==="
echo "1) 5s"
echo "2) 10s"
echo "3) 15s"
echo "4) 30s"
echo "5) 1m"
echo "6) 2m"
echo "7) 5m"
echo "8) Custom (e.g., 1:30 for 1m30s, 45 for 45s, 2m for 2 minutes)"
read -p "Choice: " CHOICE

case $CHOICE in
    1) INTERVAL=5 ;;
    2) INTERVAL=10 ;;
    3) INTERVAL=15 ;;
    4) INTERVAL=30 ;;
    5) INTERVAL=$((1*60)) ;;
    6) INTERVAL=$((2*60)) ;;
    7) INTERVAL=$((5*60)) ;;
    8) 
        read -p "Enter custom time: " CUSTOM
        if [[ "$CUSTOM" =~ ^[0-9]+$ ]]; then
            INTERVAL=$CUSTOM
        elif [[ "$CUSTOM" =~ ^([0-9]+):([0-9]{1,2})$ ]]; then
            INTERVAL=$(( ${BASH_REMATCH[1]}*60 + ${BASH_REMATCH[2]} ))
        elif [[ "$CUSTOM" =~ ^([0-9]+)m$ ]]; then
            INTERVAL=$(( ${BASH_REMATCH[1]}*60 ))
        else
            echo "Invalid format. Use seconds, m for minutes, or m:s."
            exit 1
        fi
    ;;
    *) echo "Invalid choice"; exit 1 ;;
esac

# --- Get ZFS volume path ---
ROOTVOL=$(pct config "$CTID" | awk '/^rootfs:/ {print $2}' | cut -d',' -f1)
if [[ -z "$ROOTVOL" ]]; then
    echo "Could not determine root ZFS volume."
    exit 1
fi

# --- Initialize counters ---
TOTAL_GROWTH=0

# --- Monitoring loop ---
echo
echo "Monitoring container $CTID every $INTERVAL seconds..."
echo "Threshold: $THRESHOLD% | Growth: +${GROW_GB}G each time"
echo "Press Ctrl+C to stop."
echo "----------------------------------------------"

while true; do
    # Check container status
    if ! pct status "$CTID" | grep -q running; then
        echo "$(date +"%F %T") - Container $CTID not running, waiting..."
        sleep "$INTERVAL"
        continue
    fi

    # Get usage %
    USAGE=$(pct exec "$CTID" -- df -P / | awk 'NR==2 {print $5}' | tr -d '%')

    # If usage >= threshold, grow
    if [[ "$USAGE" -ge "$THRESHOLD" ]]; then
        # Check free space on host ZFS pool
        POOL=$(echo "$ROOTVOL" | cut -d'/' -f1)
        AVAIL=$(zfs get -Hp avail "$POOL" | awk '{print int($3/1024/1024/1024)}') # GB

        if (( AVAIL < GROW_GB )); then
            echo "$(date +"%F %T") - Skipped: Low space on pool ($AVAIL GB free)"
        else
            CURRENT_SIZE=$(zfs get -Hp volsize "$ROOTVOL" | awk '{print int($3/1024/1024/1024)}')
            NEW_SIZE=$((CURRENT_SIZE + GROW_GB))

            # Grow disk
            pct set "$CTID" -rootfs "${ROOTVOL},size=${NEW_SIZE}G"
            TOTAL_GROWTH=$((TOTAL_GROWTH + GROW_GB))

            echo "$(date +"%F %T") - Usage ${USAGE}% >= ${THRESHOLD}% -> Grew by ${GROW_GB}G | New size: ${NEW_SIZE}G | Total grown: ${TOTAL_GROWTH}G"
        fi
    fi

    sleep "$INTERVAL"
done
