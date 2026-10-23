#!/usr/bin/env bash
# Test harness: Démarre XNU Darwin 22.5.0 + notre Userland APFS sous QEMU virt
set -e
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QEMU_DIR="$ROOT_DIR/../hackios-kernel/qemu"

echo "=== Démarrage du banc de test QEMU HackIOS (Darwin ARM64) ==="

# Vérification du noyau précompilé
KERNEL="$ROOT_DIR/../hackios-kernel/prebuilt/mach.development.bcm2837"
RAMDISK="$ROOT_DIR/userland/prebuilt/root.apfs"

[ -f "$KERNEL" ] || { echo "Erreur: noyau non trouvé à $KERNEL"; exit 1; }
[ -f "$RAMDISK" ] || { echo "Erreur: image APFS non trouvée à $RAMDISK"; exit 1; }

echo "[*] Génération du conteneur XNUP..."
python3 "$ROOT_DIR/tools/mkpayload.py" -o "$QEMU_DIR/payload.bin" \
    kernel="$KERNEL" ramdisk="$RAMDISK" \
    --cmdline "-v cpus=1"

echo "[*] Lancement de QEMU ARM64 (virt, GICv3, Cortex-A76)..."
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
        -display none -serial stdio -monitor none -no-reboot </dev/null 2>&1
) | tee "$ROOT_DIR/qemu_run.log" || true

echo ""
echo "=== Test terminé. Journal sauvegardé dans $ROOT_DIR/qemu_run.log ==="
