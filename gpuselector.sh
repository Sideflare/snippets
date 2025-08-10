DUAL GPU SELECTOR

#GPUSelector.sh
#renderD128
#renderD129
#!/bin/bash

# A Shell script can communicate with FileFlows to determine which output to call next by using exit codes.
# Exit Code 0 = Finish Flow
# Exit Code 1 = Output 1 (renderD128)
# Exit Code 2 = Output 2 (renderD129)

# FileFlows variables
WorkingFile="{file.FullName}"
OriginalFile="{file.Orig.FullName}"

echo "Working on file: $WorkingFile"
echo "Original file location: $OriginalFile"

# Max processes per GPU
MAX_JOBS_PER_GPU=6

# Render devices
RENDER_DEVICES=(
    "/dev/dri/renderD129"  # default
    "/dev/dri/renderD128"
)

# Output mapping
declare -A DEVICE_TO_EXIT_CODE=(
    ["/dev/dri/renderD128"]=1
    ["/dev/dri/renderD129"]=2
)

# Count current FFmpeg processes using each render device
declare -A DEVICE_USAGE
for dev in "${RENDER_DEVICES[@]}"; do
    DEVICE_USAGE[$dev]=$(pgrep -a ffmpeg | grep -c "$dev")
    echo "$dev has ${DEVICE_USAGE[$dev]} active FFmpeg processes"
done

# Default device fallback
best_device="/dev/dri/renderD129"
lowest_usage=$((MAX_JOBS_PER_GPU + 1))

for dev in "${RENDER_DEVICES[@]}"; do
    usage="${DEVICE_USAGE[$dev]}"
    if [ "$usage" -lt "$MAX_JOBS_PER_GPU" ]; then
        if [ "$usage" -lt "$lowest_usage" ]; then
            best_device="$dev"
            lowest_usage="$usage"
        fi
    fi
done

exit_code=${DEVICE_TO_EXIT_CODE[$best_device]}

echo "✅ Selected device: $best_device (${DEVICE_USAGE[$best_device]} FFmpeg processes)"
echo "➡️ Exiting with code $exit_code (corresponds to FileFlows Output $exit_code)"
exit $exit_code
