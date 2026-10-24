#!/usr/bin/env bash
# Device Tree Extraction Utility for Google Pixel 8 (Tensor G3)
set -e

echo "=== Device Tree Extractor for Google Pixel 8 (Shiba) ==="

if [ "$1" == "--adb" ]; then
    echo "[*] Extracting Device Tree from connected Pixel 8 over ADB..."
    adb wait-for-device
    adb pull /sys/firmware/fdt shiba_extracted.dtb
    dtc -I dtb -O dts -o shiba_extracted.dts shiba_extracted.dtb
    echo "[+] DTS successfully extracted to shiba_extracted.dts"
    exit 0
fi

if [ -f "$1" ]; then
    IMAGE="$1"
    echo "[*] Decompressing $IMAGE..."
    TMP_OUT=$(mktemp -d)
    unpack_bootimg --boot_img "$IMAGE" --out "$TMP_OUT"
    if [ -f "$TMP_OUT/dtb" ]; then
        echo "[+] Found DTB section. Decompiling..."
        dtc -I dtb -O dts -o shiba_extracted.dts "$TMP_OUT/dtb"
        echo "[+] DTS successfully extracted to shiba_extracted.dts"
    else
        echo "[-] No DTB section found in image."
    fi
    rm -rf "$TMP_OUT"
    exit 0
fi

echo "Usage:"
echo "  $0 --adb                # Extract from a connected Pixel 8 via ADB"
echo "  $0 vendor_boot.img      # Extract from a vendor_boot.img file"
