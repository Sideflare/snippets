#!/bin/bash

VMID="$1"
PHASE="$2"
EVENT="$3"
LOGFILE="/var/log/gpu-passthrough.log"

# Function to log with timestamp
log_message() {
    echo "$(date) [HOOK] VMID=$VMID PHASE=$PHASE EVENT=$EVENT - $1" >> "$LOGFILE"
}

log_message "Hook script triggered"

# Check if this VM has GPU passthrough configured
VM_CONFIG="/etc/pve/qemu-server/${VMID}.conf"

if [[ ! -f "$VM_CONFIG" ]]; then
    log_message "VM config file not found: $VM_CONFIG"
    exit 0
fi

# Look for hostpci lines with our GPU (07:00) or any GPU passthrough
GPU_PASSTHROUGH=$(grep -E "^hostpci[0-9]+:.*0000:07:00" "$VM_CONFIG" 2>/dev/null)

if [[ -z "$GPU_PASSTHROUGH" ]]; then
    log_message "No GPU passthrough detected for this VM, skipping"
    exit 0
fi

log_message "GPU passthrough detected: $GPU_PASSTHROUGH"

# Extract GPU PCI ID from the config
GPU_BDF=$(echo "$GPU_PASSTHROUGH" | grep -o "0000:07:00\.[0-9]" | head -1)
if [[ -z "$GPU_BDF" ]]; then
    # If specific function not found, assume .0
    GPU_BDF="0000:07:00.0"
fi

log_message "Using GPU PCI ID: $GPU_BDF"

case "$PHASE" in
    "pre-start")
        log_message "VM starting - binding GPU to vfio-pci"
        
        # Get current driver
        current_driver_path=$(readlink /sys/bus/pci/devices/$GPU_BDF/driver 2>/dev/null)
        if [ -n "$current_driver_path" ]; then
            current_driver=$(basename "$current_driver_path")
            log_message "Current driver: $current_driver"
            
            # Unbind from current driver
            if [ -e "/sys/bus/pci/devices/$GPU_BDF/driver/unbind" ]; then
                echo "$GPU_BDF" > /sys/bus/pci/devices/$GPU_BDF/driver/unbind
                log_message "Unbound $GPU_BDF from $current_driver"
                sleep 2
            fi
        else
            log_message "No driver currently bound to $GPU_BDF"
        fi
        
        # Bind to vfio-pci
        if [ -e "/sys/bus/pci/drivers/vfio-pci/bind" ]; then
            echo "$GPU_BDF" > /sys/bus/pci/drivers/vfio-pci/bind 2>/dev/null
            if [ $? -eq 0 ]; then
                log_message "Successfully bound $GPU_BDF to vfio-pci"
            else
                log_message "Failed to bind $GPU_BDF to vfio-pci"
            fi
        else
            log_message "vfio-pci driver not available"
        fi
        
        # Verify binding
        new_driver_path=$(readlink /sys/bus/pci/devices/$GPU_BDF/driver 2>/dev/null)
        if [ -n "$new_driver_path" ]; then
            new_driver=$(basename "$new_driver_path")
            log_message "GPU now bound to: $new_driver"
        else
            log_message "Warning: GPU not bound to any driver"
        fi
        ;;
        
    "post-stop")
        log_message "VM stopped - resetting GPU and binding back to amdgpu"
        
        # Call the reset script
        RESET_SCRIPT="/mnt/STORAGE/PVE/var/lib/vz/snippets/gpu_reset.sh"
        if [[ -f "$RESET_SCRIPT" && -x "$RESET_SCRIPT" ]]; then
            log_message "Calling reset script: $RESET_SCRIPT"
            "$RESET_SCRIPT" >> "$LOGFILE" 2>&1
        else
            log_message "Reset script not found or not executable: $RESET_SCRIPT"
            
            # Fallback: do basic reset here
            log_message "Performing fallback GPU reset"
            
            # Unbind from current driver
            current_driver_path=$(readlink /sys/bus/pci/devices/$GPU_BDF/driver 2>/dev/null)
            if [ -n "$current_driver_path" ]; then
                current_driver=$(basename "$current_driver_path")
                if [ -e "/sys/bus/pci/devices/$GPU_BDF/driver/unbind" ]; then
                    echo "$GPU_BDF" > /sys/bus/pci/devices/$GPU_BDF/driver/unbind
                    log_message "Unbound $GPU_BDF from $current_driver"
                fi
            fi
            
            sleep 3
            
            # Bind to amdgpu
            if [ -e "/sys/bus/pci/drivers/amdgpu/bind" ]; then
                echo "$GPU_BDF" > /sys/bus/pci/drivers/amdgpu/bind 2>/dev/null
                log_message "Bound $GPU_BDF back to amdgpu"
            fi
        fi
        ;;
        
    *)
        log_message "Unhandled phase: $PHASE"
        ;;
esac

log_message "Hook script completed"
exit 0
