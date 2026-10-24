#!/usr/bin/env bash
# Boots full iOS 16.5 under QEMU virt with GTK graphical display
set -e
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_DIR="$ROOT_DIR/../hackios-kernel"

echo "=== Launching full HackIOS iOS 16.5 under QEMU virt (GTK) ==="

SECS=${1:-3600}

# Automatically resize QEMU window for 1080p desktop view (9:19.5 aspect ratio, max 950px height)
(
    for i in {1..30}; do
        if WID=$(xdotool search --name "QEMU" 2>/dev/null | head -n 1); [ -n "$WID" ]; then
            xdotool windowsize "$WID" 450 950 2>/dev/null || true
            break
        fi
        sleep 0.5
    done
) &

cd "$KERNEL_DIR"
DISPLAY=:0 QEMU_SMP=4 CMDLINE="cpus=4" exec ./qemu/run-ios.sh "$SECS" -display gtk,zoom-to-fit=on </dev/null
