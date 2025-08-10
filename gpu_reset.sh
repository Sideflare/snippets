#!/bin/bash

GPU_BDF="0000:07:00.0"   # PCI bus ID of your GPU
LOGFILE="/var/log/gpu-reset.log"

echo "$(date) Starting GPU reset sequence..." >> "$LOGFILE"

# Get current driver basename safely
current_driver_path=$(readlink /sys/bus/pci/devices/$GPU_BDF/driver 2>/dev/null)
if [ -n "$current_driver_path" ]; then
  current_driver=$(basename "$current_driver_path")
else
  current_driver="none"
fi
echo "$(date) Current driver before unbind: $current_driver" >> "$LOGFILE"

# Unbind from current driver if bound
if [ -e "/sys/bus/pci/devices/$GPU_BDF/driver" ]; then
  echo "$GPU_BDF" > /sys/bus/pci/devices/$GPU_BDF/driver/unbind
  echo "$(date) Unbound $GPU_BDF from $current_driver" >> "$LOGFILE"
else
  echo "$(date) No driver bound to $GPU_BDF" >> "$LOGFILE"
fi

# Wait a moment for reset to complete
sleep 3

# Bind back to amdgpu
echo "$GPU_BDF" > /sys/bus/pci/drivers/amdgpu/bind
echo "$(date) Bound $GPU_BDF to amdgpu" >> "$LOGFILE"

# Verify final driver safely
final_driver_path=$(readlink /sys/bus/pci/devices/$GPU_BDF/driver 2>/dev/null)
if [ -n "$final_driver_path" ]; then
  final_driver=$(basename "$final_driver_path")
else
  final_driver="none"
fi
echo "$(date) Final driver in use: $final_driver" >> "$LOGFILE"
