#!/bin/bash

# GPU Reset Script - Called by hook script after VM shutdown
# Performs vendor-reset and rebinds GPU to amdgpu driver

GPU_BDF="0000:07:00.0"
GPU_AUDIO_BDF="0000:07:00.1"
LOGFILE="/var/log/gpu-reset.log"

# Function to log with timestamp
log_msg() {
    echo "$(date) [RESET] $1" >> "$LOGFILE"
}

# Function to safely get current driver
get_current_driver() {
    local device="$1"
    if [[ -e "/sys/bus/pci/devices/$device/driver" ]]; then
        basename $(readlink "/sys/bus/pci/devices/$device/driver" 2>/dev/null)
    else
        echo "none"
    fi
}

# Function to unbind device from current driver
unbind_device() {
    local device="$1"
    local current_driver=$(get_current_driver "$device")
    
    if [[ "$current_driver" != "none" ]]; then
        echo "$device" > "/sys/bus/pci/devices/$device/driver/unbind" 2>/dev/null
        if [[ $? -eq 0 ]]; then
            log_msg "Unbound $device from $current_driver"
            return 0
        else
            log_msg "WARNING: Failed to unbind $device from $current_driver"
            return 1
        fi
    else
        log_msg "$device not bound to any driver"
        return 0
    fi
}

# Function to bind device to specific driver
bind_device() {
    local device="$1"
    local driver="$2"
    
    if [[ -d "/sys/bus/pci/drivers/$driver" ]]; then
        echo "$device" > "/sys/bus/pci/drivers/$driver/bind" 2>/dev/null
        if [[ $? -eq 0 ]]; then
            log_msg "Successfully bound $device to $driver"
            return 0
        else
            log_msg "ERROR: Failed to bind $device to $driver"
            return 1
        fi
    else
        log_msg "ERROR: Driver $driver not available"
        return 1
    fi
}

# Function to perform vendor reset
vendor_reset_device() {
    local device="$1"
    log_msg "Performing vendor reset on $device"
    
    # Check if vendor_reset module is loaded
    if ! lsmod | grep -q vendor_reset; then
        log_msg "WARNING: vendor_reset module not loaded"
        return 1
    fi
    
    # Perform the actual vendor reset via sysfs if available
    if [[ -f "/sys/bus/pci/devices/$device/vendor_reset" ]]; then
        echo 1 > "/sys/bus/pci/devices/$device/vendor_reset" 2>/dev/null
        log_msg "Vendor reset triggered via sysfs"
    else
        log_msg "Vendor reset sysfs interface not available, relying on driver cycling"
    fi
    
    return 0
}

# Main reset sequence
log_msg "Starting GPU reset sequence"

# Get initial states
gpu_driver=$(get_current_driver "$GPU_BDF")
audio_driver=$(get_current_driver "$GPU_AUDIO_BDF")
log_msg "Initial state - GPU: $gpu_driver, Audio: $audio_driver"

# Unbind from current drivers
unbind_device "$GPU_BDF"
unbind_device "$GPU_AUDIO_BDF"

# Wait for unbind to complete
sleep 1

# Perform vendor reset
vendor_reset_device "$GPU_BDF"

# Wait for reset to complete
sleep 3

# Bind to amdgpu (GPU) and snd_hda_intel (Audio)
bind_device "$GPU_BDF" "amdgpu"
bind_device "$GPU_AUDIO_BDF" "snd_hda_intel"

# Verify final state
final_gpu_driver=$(get_current_driver "$GPU_BDF")
final_audio_driver=$(get_current_driver "$GPU_AUDIO_BDF")
log_msg "Final state - GPU: $final_gpu_driver, Audio: $final_audio_driver"

# Check if reset was successful
if [[ "$final_gpu_driver" == "amdgpu" ]]; then
    log_msg "GPU reset completed successfully"
    exit 0
else
    log_msg "WARNING: GPU not bound to amdgpu after reset"
    exit 1
fi
