#!/usr/bin/env bash
# GPU utilisation / VRAM / temperature for GpuStats.qml.
# Prefers amdgpu/radeon sysfs (gpu_busy_percent + mem_info_vram_*); falls back
# to nvidia-smi. Emits `key=value` lines (util/vramUsed/vramTotal/temp); missing
# fields are simply omitted and the QML parser defaults them.
set -u

c=''
for d in /sys/class/drm/card*/device/gpu_busy_percent; do
    [ -e "$d" ] && c="${d%/gpu_busy_percent}" && break
done

if [ -n "$c" ]; then
    echo "util=$(cat "$c/gpu_busy_percent" 2>/dev/null)"
    echo "vramUsed=$(cat "$c/mem_info_vram_used" 2>/dev/null)"
    echo "vramTotal=$(cat "$c/mem_info_vram_total" 2>/dev/null)"
    echo "temp=$(cat "$c"/hwmon/hwmon*/temp1_input 2>/dev/null | head -1)"
elif command -v nvidia-smi >/dev/null; then
    read -r u mu mt t < <(nvidia-smi \
        --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu \
        --format=csv,noheader,nounits | head -1 | tr -d ',')
    echo "util=$u"
    echo "vramUsed=$((mu * 1048576))"
    echo "vramTotal=$((mt * 1048576))"
    echo "temp=$((t * 1000))"
fi
