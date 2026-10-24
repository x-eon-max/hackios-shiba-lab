#!/usr/bin/env bash
# Launches QEMU with interactive video display (GTK window)
set -e
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QEMU_DIR="$ROOT_DIR/../hackios-kernel/qemu"

echo "=== Launching HackIOS under QEMU with live video output (GTK) ==="

KERNEL="$ROOT_DIR/../hackios-kernel/prebuilt/mach.development.bcm2837"
RAMDISK="$ROOT_DIR/userland/prebuilt/root.apfs"

[ -f "$KERNEL" ] || { echo "Error: kernel not found at $KERNEL"; exit 1; }
[ -f "$RAMDISK" ] || { echo "Error: APFS image not found at $RAMDISK"; exit 1; }

echo "[*] Packaging XNUP payload..."
python3 "$ROOT_DIR/tools/mkpayload.py" -o "$QEMU_DIR/payload.bin" \
    kernel="$KERNEL" ramdisk="$RAMDISK" \
    --cmdline "-v cpus=1"

echo "[*] Opening QEMU graphical window..."
cd "$QEMU_DIR"
exec qemu-system-aarch64 \
    -M virt,gic-version=3 \
    -cpu cortex-a76 \
    -smp 1 \
    -m 4G \
    -accel tcg,tb-size=384 \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/aarch64/QEMU_EFI.fd \
    -drive if=pflash,format=raw,file=vars.fd \
    -drive file=fat:rw:esp,format=raw,if=virtio \
    -device loader,file=payload.bin,addr=0xF0000000,force-raw=on \
    -device ramfb \
    -monitor tcp:127.0.0.1:4444,server,nowait \
    -global virtio-mmio.force-legacy=false \
    -device virtio-tablet-device \
    -device virtio-keyboard-device \
    -display gtk \
    -no-reboot \
    -serial stdio
