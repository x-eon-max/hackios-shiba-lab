#!/usr/bin/env bash
# Utilitaire d'extraction du Device Tree pour Google Pixel 8 (Tensor G3)
set -e

echo "=== Extracteur de Device Tree pour Google Pixel 8 (Shiba) ==="

if [ "$1" == "--adb" ]; then
    echo "[*] Tentative de récupération depuis un Pixel 8 connecté en USB via ADB..."
    adb wait-for-device
    adb pull /sys/firmware/fdt shiba_extracted.dtb
    dtc -I dtb -O dts -o shiba_extracted.dts shiba_extracted.dtb
    echo "[+] DTS extrait dans shiba_extracted.dts"
    exit 0
fi

if [ -f "$1" ]; then
    IMAGE="$1"
    echo "[*] Décompression de $IMAGE..."
    TMP_OUT=$(mktemp -d)
    unpack_bootimg --boot_img "$IMAGE" --out "$TMP_OUT"
    if [ -f "$TMP_OUT/dtb" ]; then
        echo "[+] Table DTB trouvée. Décompilation..."
        dtc -I dtb -O dts -o shiba_extracted.dts "$TMP_OUT/dtb"
        echo "[+] DTS extrait dans shiba_extracted.dts"
    else
        echo "[-] Pas de section dtb trouvée dans l'image."
    fi
    rm -rf "$TMP_OUT"
    exit 0
fi

echo "Usage:"
echo "  $0 --adb                # Extrait depuis un Pixel 8 branché en mode ADB"
echo "  $0 vendor_boot.img      # Extrait depuis un vendor_boot.img extrait d'une factory image"
