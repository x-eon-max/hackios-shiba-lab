#!/usr/bin/env bash
# Démarre le système complet iOS 16.5 sous QEMU virt avec affichage graphique GTK
set -e
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_DIR="$ROOT_DIR/../hackios-kernel"

echo "=== Lancement de HackIOS iOS 16.5 complet sous QEMU virt (GTK) ==="

SECS=${1:-3600}

# Redimensionne automatiquement la fenêtre pour un écran 1080p (ratio 9:19.5, hauteur 950px max)
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
