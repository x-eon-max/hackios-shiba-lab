#!/usr/bin/env bash
# Démarre le système complet iOS 16.5 sous QEMU virt avec affichage graphique GTK
set -e
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_DIR="$ROOT_DIR/../hackios-kernel"

echo "=== Lancement de HackIOS iOS 16.5 complet sous QEMU virt (GTK) ==="

SECS=${1:-300}

cd "$KERNEL_DIR"
DISPLAY=:0 CMDLINE="cpus=4" exec ./qemu/run-ios.sh "$SECS" -display gtk
