#!/usr/bin/env bash
# Test harness: Boots Darwin XNU 22.5.0 + custom APFS Userland under QEMU virt
set -e
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QEMU_DIR="$ROOT_DIR/../hackios-kernel/qemu"

echo "=== Starting HackIOS QEMU Test Harness (Darwin ARM64) ==="

# Check for prebuilt kernel and ramdisk
KERNEL="$ROOT_DIR/../hackios-kernel/prebuilt/mach.development.bcm2837"
RAMDISK="$ROOT_DIR/userland/prebuilt/root.apfs"

[ -f "$KERNEL" ] || { echo "Error: kernel not found at $KERNEL"; exit 1; }
[ -f "$RAMDISK" ] || { echo "Error: APFS image not found at $RAMDISK"; exit 1; }

echo "[*] Generating XNUP payload..."
python3 "$ROOT_DIR/tools/mkpayload.py" -o "$QEMU_DIR/payload.bin" \
    kernel="$KERNEL" ramdisk="$RAMDISK" \
    --cmdline "-v cpus=1"

echo "[*] Booting QEMU ARM64 (virt, GICv3, Cortex-A76)..."
(
    cd "$QEMU_DIR"
    timeout 15 qemu-system-aarch64 \
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
        -display none -serial stdio -no-reboot </dev/null 2>&1
) | tee "$ROOT_DIR/qemu_run.log" || true

echo ""
echo "=== Test finished. Execution log saved to $ROOT_DIR/qemu_run.log ==="
