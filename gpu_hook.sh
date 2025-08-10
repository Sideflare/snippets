#!/bin/bash

VMID="$1"
EVENT="$2"
PHASE="$3"
LOGFILE="/var/log/gpu-reset.log"

echo "$(date) [HOOK] VMID=$VMID EVENT=$EVENT PHASE=$PHASE" >> "$LOGFILE"

if [[ "$VMID" == "1122" && "$EVENT" == "post-stop" ]]; then
  echo "$(date) [HOOK] Triggering GPU reset after VM shutdown." >> "$LOGFILE"
  /mnt/STORAGE/PVE/var/lib/vz/snippets/gpu_reset.sh >> "$LOGFILE" 2>&1
else
  echo "$(date) [HOOK] Ignored: VMID=$VMID EVENT=$EVENT PHASE=$PHASE" >> "$LOGFILE"
fi
