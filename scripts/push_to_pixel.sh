#!/usr/bin/env bash
# ==============================================================================
# Script de déploiement automatique de HackIOS iOS 16.5 sur Google Pixel 8 via ADB
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KERNEL_DIR="$(cd "$LAB_DIR/../hackios-kernel" && pwd)"
STAGING_DIR="/tmp/hackios_pixel_deploy"

echo "================================================================"
echo "    Déploiement de HackIOS iOS 16.5 sur Google Pixel 8 (ADB)   "
echo "================================================================"

# 1. Vérification de la présence d'ADB
command -v adb >/dev/null 2>&1 || {
    echo "Erreur : ADB n'est pas installé sur votre PC."
    echo "Installez-le avec : sudo pacman -S android-tools (ou sudo apt install adb)"
    exit 1
}

# 2. Vérification de la connexion de l'appareil
echo "[*] Recherche d'un appareil Android connecté via USB..."
DEVICES=$(adb devices | grep -v "List of devices" | grep "device$" || true)

if [ -z "$DEVICES" ]; then
    echo ""
    echo "Aucun appareil Android détecté en mode débogage USB."
    echo "Veuillez :"
    echo "  1. Brancher votre Google Pixel 8 à ce PC avec un câble USB."
    echo "  2. Activer les 'Options pour les développeurs' sur le Pixel 8 :"
    echo "     (Paramètres > À propos du téléphone > appuyer 7 fois sur 'Numéro de build')."
    echo "  3. Activer 'Débogage USB' dans Paramètres > Système > Options pour les développeurs."
    echo "  4. Accepter l'autorisation de débogage sur l'écran du Pixel 8 ('Toujours autoriser ce PC')."
    echo ""
    echo "Réessayez ensuite en relançant ce script."
    exit 1
fi

DEVICE_MODEL=$(adb shell getprop ro.product.model 2>/dev/null || echo "Android Device")
DEVICE_SOC=$(adb shell getprop ro.soc.model 2>/dev/null || echo "ARM64")
echo "[+] Appareil détecté : $DEVICE_MODEL (SoC: $DEVICE_SOC)"

# 3. Vérification des fichiers prérequis sur le PC
echo "[*] Vérification des images iOS 16.5 locales..."
[ -f "$KERNEL_DIR/userland/system.apfs" ] || { echo "Erreur: $KERNEL_DIR/userland/system.apfs est manquant."; exit 1; }
[ -f "$KERNEL_DIR/userland/root.apfs" ] || { echo "Erreur: $KERNEL_DIR/userland/root.apfs est manquant."; exit 1; }
[ -f "$KERNEL_DIR/prebuilt/mach.development.bcm2837" ] || { echo "Erreur: Noyau mach.development.bcm2837 manquant."; exit 1; }

# 4. Préparation du dossier de transfert (Staging)
echo "[*] Préparation du pack de déploiement dans $STAGING_DIR..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR/userland"
mkdir -p "$STAGING_DIR/prebuilt"
mkdir -p "$STAGING_DIR/xnuloader"
mkdir -p "$STAGING_DIR/qemu"

# Liens ou copies des fichiers clés
cp "$KERNEL_DIR/userland/system.apfs" "$STAGING_DIR/userland/"
cp "$KERNEL_DIR/userland/root.apfs" "$STAGING_DIR/userland/"
cp "$KERNEL_DIR/prebuilt/mach.development.bcm2837" "$STAGING_DIR/prebuilt/"
cp "$KERNEL_DIR/prebuilt/loader.efi" "$STAGING_DIR/prebuilt/" 2>/dev/null || true
cp "$KERNEL_DIR/xnuloader/mkpayload.py" "$STAGING_DIR/xnuloader/"
cp "$KERNEL_DIR/xnuloader/loader.efi" "$STAGING_DIR/xnuloader/" 2>/dev/null || true

# Copie des scripts QEMU
cp -r "$KERNEL_DIR/qemu/"* "$STAGING_DIR/qemu/"
rm -f "$STAGING_DIR/qemu/ram.img" "$STAGING_DIR/qemu/payload.bin" "$STAGING_DIR/qemu/vars.fd"

# Embarquer le firmware UEFI directement pour éviter les dépendances manquantes sur Android
if [ -f /usr/share/edk2/aarch64/QEMU_EFI.fd ]; then
    cp /usr/share/edk2/aarch64/QEMU_EFI.fd "$STAGING_DIR/qemu/"
    cp /usr/share/edk2/aarch64/QEMU_VARS.fd "$STAGING_DIR/qemu/" 2>/dev/null || true
fi

# 5. Créer le script d'exécution autonome pour le Pixel 8
cat <<'EOF' > "$STAGING_DIR/setup_and_run_pixel.sh"
#!/usr/bin/env bash
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "=== Lancement de HackIOS iOS 16.5 sur Google Pixel 8 ==="

# 1. Vérifications des outils
command -v python3 >/dev/null 2>&1 || { echo "Veuillez installer python3 (pkg install python ou apt install python3)"; exit 1; }
command -v qemu-system-aarch64 >/dev/null 2>&1 || { echo "Veuillez installer QEMU (pkg install qemu-system-aarch64 ou apt install qemu-system-arm)"; exit 1; }

# 2. Construction du conteneur ram.img sparse s'il n'existe pas encore
if [ ! -f qemu/ram.img ] || [ userland/system.apfs -nt qemu/ram.img ]; then
    echo "[*] Initialisation du stockage ram.img (2.4 Go)..."
    python3 - userland/system.apfs qemu/ram.img $((0xFC000000 - 0x40000000)) $((12 << 30)) <<'PY'
import os, sys
src = os.open(sys.argv[1], os.O_RDONLY)
dst = os.open(sys.argv[2], os.O_RDWR | os.O_CREAT | os.O_TRUNC, 0o644)
offset, size = int(sys.argv[3]), int(sys.argv[4])
os.ftruncate(dst, size)
total, done = os.fstat(src).st_size, 0
if hasattr(os, 'copy_file_range'):
    try:
        while done < total:
            done += os.copy_file_range(src, dst, total - done, done, offset + done)
    except Exception:
        done = 0
if done < total:
    os.lseek(src, 0, os.SEEK_SET)
    os.lseek(dst, offset, os.SEEK_SET)
    while True:
        chunk = os.read(src, 8 * 1024 * 1024)
        if not chunk: break
        os.write(dst, chunk)
os.close(src)
os.close(dst)
print(f"ram.img prêt")
PY
fi

# 3. Paramètres optimisés pour le Pixel 8 (Tensor G3, 8 Go RAM)
export QEMU_RAM_GB=4
export QEMU_FORCE=1
export QEMU_SMP=4
export CMDLINE="cpus=4"

if [ -f "$DIR/qemu/QEMU_EFI.fd" ]; then
    export QEMU_EFI="$DIR/qemu/QEMU_EFI.fd"
    export QEMU_VARS="$DIR/qemu/QEMU_VARS.fd"
fi

# 4. Gestion de l'affichage
SECS=${1:-3600}
if [ -n "$DISPLAY" ]; then
    echo "[*] Affichage détecté sur $DISPLAY (Termux-X11 / X11)"
    exec ./qemu/run-ios.sh "$SECS" -display x11
else
    echo "[*] Aucun DISPLAY détecté. Démarrage avec serveur VNC sur le port 5900..."
    echo "[*] Ouvrez votre application AVNC sur le Pixel 8 et connectez-vous à 127.0.0.1:5900"
    exec ./qemu/run-ios.sh "$SECS" -display vnc=:0
fi
EOF
chmod +x "$STAGING_DIR/setup_and_run_pixel.sh"

# 6. Transfert via ADB
TARGET_PATH="/sdcard/Download/hackios"
echo "[*] Nettoyage de l'ancien dossier cible sur le Pixel 8 ($TARGET_PATH)..."
adb shell rm -rf "$TARGET_PATH" 2>/dev/null || true
adb shell mkdir -p "$TARGET_PATH"

echo "[*] Transfert des fichiers vers le Pixel 8 via ADB (environ 2.5 Go)..."
adb push "$STAGING_DIR/." "$TARGET_PATH/"

echo ""
echo "================================================================"
echo "          TRANSFERT TERMINÉ AVEC SUCCÈS SUR LE PIXEL 8 !        "
echo "================================================================"
echo ""
echo "Pour lancer iOS 16.5 sur votre Pixel 8 :"
echo ""
echo "--- MÉTHODE AVEC TERMUX (Recommandée pour le tactile) ---"
echo "1. Ouvrez l'application 'Termux-X11' sur votre Pixel 8."
echo "2. Dans l'application 'Termux', tapez :"
echo "     pkg install qemu-system-aarch64 python x11-repo termux-x11-nightly -y"
echo "     termux-setup-storage"
echo "     cp -r /sdcard/Download/hackios ~/hackios"
echo "     cd ~/hackios"
echo "     export DISPLAY=:0"
echo "     ./setup_and_run_pixel.sh"
echo ""
echo "--- MÉTHODE AVEC LE TERMINAL LINUX ANDROID 15 (AVF) ---"
echo "1. Dans le Terminal Linux de Google (Debian) :"
echo "     sudo apt update && sudo apt install -y qemu-system-arm python3"
echo "     cp -r /sdcard/Download/hackios ~/hackios"
echo "     cd ~/hackios"
echo "     ./setup_and_run_pixel.sh"
echo "2. Ouvrez l'application AVNC sur votre téléphone et connectez-vous à 127.0.0.1:5900"
echo ""
