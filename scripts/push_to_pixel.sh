#!/usr/bin/env bash
# ==============================================================================
# Automated Deployment Script for HackIOS iOS 16.5 on Google Pixel 8 via ADB
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KERNEL_DIR="$(cd "$LAB_DIR/../hackios-kernel" && pwd)"
STAGING_DIR="/tmp/hackios_pixel_deploy"

echo "================================================================"
echo "    Deploying HackIOS iOS 16.5 to Google Pixel 8 (ADB)          "
echo "================================================================"

# 1. Check for ADB presence
command -v adb >/dev/null 2>&1 || {
    echo "Error: ADB is not installed on this PC."
    echo "Install it via: sudo pacman -S android-tools (or sudo apt install adb)"
    exit 1
}

# 2. Check device connection
echo "[*] Scanning for connected Android device over USB..."
DEVICES=$(adb devices | grep -v "List of devices" | grep "device$" || true)

if [ -z "$DEVICES" ]; then
    echo ""
    echo "No Android device detected in USB debugging mode."
    echo "Please:"
    echo "  1. Connect your Google Pixel 8 to this PC via USB."
    echo "  2. Enable Developer Options on Pixel 8:"
    echo "     (Settings > About phone > tap 'Build number' 7 times)."
    echo "  3. Enable 'USB debugging' in Settings > System > Developer options."
    echo "  4. Accept debugging authorization prompt on phone screen ('Always allow from this computer')."
    echo ""
    echo "Then retry running this script."
    exit 1
fi

DEVICE_MODEL=$(adb shell getprop ro.product.model 2>/dev/null || echo "Android Device")
DEVICE_SOC=$(adb shell getprop ro.soc.model 2>/dev/null || echo "ARM64")
echo "[+] Detected device: $DEVICE_MODEL (SoC: $DEVICE_SOC)"

# 3. Check local prerequisites
echo "[*] Checking local iOS 16.5 image prerequisites..."
[ -f "$KERNEL_DIR/userland/system.apfs" ] || { echo "Error: $KERNEL_DIR/userland/system.apfs is missing."; exit 1; }
[ -f "$KERNEL_DIR/userland/root.apfs" ] || { echo "Error: $KERNEL_DIR/userland/root.apfs is missing."; exit 1; }
[ -f "$KERNEL_DIR/prebuilt/mach.development.bcm2837" ] || { echo "Error: Kernel mach.development.bcm2837 is missing."; exit 1; }

# 4. Prepare deployment staging directory
echo "[*] Preparing deployment pack in $STAGING_DIR..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR/userland"
mkdir -p "$STAGING_DIR/prebuilt"
mkdir -p "$STAGING_DIR/xnuloader"
mkdir -p "$STAGING_DIR/qemu"

# Copy or link key files
cp "$KERNEL_DIR/userland/system.apfs" "$STAGING_DIR/userland/"
cp "$KERNEL_DIR/userland/root.apfs" "$STAGING_DIR/userland/"
cp "$KERNEL_DIR/prebuilt/mach.development.bcm2837" "$STAGING_DIR/prebuilt/"
cp "$KERNEL_DIR/prebuilt/loader.efi" "$STAGING_DIR/prebuilt/" 2>/dev/null || true
cp "$KERNEL_DIR/xnuloader/mkpayload.py" "$STAGING_DIR/xnuloader/"
cp "$KERNEL_DIR/xnuloader/loader.efi" "$STAGING_DIR/xnuloader/" 2>/dev/null || true

# Copy QEMU harness scripts
cp -r "$KERNEL_DIR/qemu/"* "$STAGING_DIR/qemu/"
rm -f "$STAGING_DIR/qemu/ram.img" "$STAGING_DIR/qemu/payload.bin" "$STAGING_DIR/qemu/vars.fd"

# Include UEFI firmware to prevent missing dependencies on Android
if [ -f /usr/share/edk2/aarch64/QEMU_EFI.fd ]; then
    cp /usr/share/edk2/aarch64/QEMU_EFI.fd "$STAGING_DIR/qemu/"
    cp /usr/share/edk2/aarch64/QEMU_VARS.fd "$STAGING_DIR/qemu/" 2>/dev/null || true
fi

# 5. Create standalone runner script for Pixel 8
cat <<'EOF' > "$STAGING_DIR/setup_and_run_pixel.sh"
#!/usr/bin/env bash
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "=== Starting HackIOS iOS 16.5 on Google Pixel 8 ==="

# 1. Tooling check
command -v python3 >/dev/null 2>&1 || { echo "Please install python3 (pkg install python or apt install python3)"; exit 1; }
command -v qemu-system-aarch64 >/dev/null 2>&1 || { echo "Please install QEMU (pkg install qemu-system-aarch64 or apt install qemu-system-arm)"; exit 1; }

# 2. Build ram.img sparse container if needed
if [ ! -f qemu/ram.img ] || [ userland/system.apfs -nt qemu/ram.img ]; then
    echo "[*] Initializing ram.img storage container (2.4 GB)..."
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
print("ram.img initialized.")
PY
fi

# 3. Optimized configuration for Pixel 8 (Tensor G3, 8 GB RAM)
# Guest needs 7 GB virtual address window to place system.apfs (2.4 GB at 0xFC000000)
# Demand paging ensures this uses only ~2.5 GB of actual physical host RAM.
export QEMU_RAM_GB=7
export QEMU_FORCE=1
export QEMU_SMP=4
export CMDLINE="cpus=4"

if [ -f "$DIR/qemu/QEMU_EFI.fd" ]; then
    export QEMU_EFI="$DIR/qemu/QEMU_EFI.fd"
    export QEMU_VARS="$DIR/qemu/QEMU_VARS.fd"
fi

# 4. Display handling
SECS=${1:-86400}
if [ -n "$DISPLAY" ]; then
    echo "[*] Display detected on $DISPLAY (Termux-X11 / X11)"
    exec bash ./qemu/run-ios.sh "$SECS" -display x11
else
    echo "[*] No DISPLAY detected. Starting VNC server on port 5900..."
    echo "[*] Connect via RealVNC Viewer on Pixel 8 to 127.0.0.1:5900"
    exec bash ./qemu/run-ios.sh "$SECS" -display vnc=:0
fi
EOF
chmod +x "$STAGING_DIR/setup_and_run_pixel.sh"

# 6. Push via ADB
TARGET_PATH="/sdcard/Download/hackios"
echo "[*] Cleaning destination folder on Pixel 8 ($TARGET_PATH)..."
adb shell rm -rf "$TARGET_PATH" 2>/dev/null || true
adb shell mkdir -p "$TARGET_PATH"

echo "[*] Transferring deployment bundle via ADB (~2.5 GB)..."
adb push "$STAGING_DIR/." "$TARGET_PATH/"

echo ""
echo "================================================================"
echo "          TRANSFER SUCCESSFULLY COMPLETED ON PIXEL 8!           "
echo "================================================================"
echo ""
echo "To boot iOS 16.5 on your Pixel 8:"
echo ""
echo "--- METHOD A: USING TERMUX (With VNC or Termux-X11) ---"
echo "1. In Termux, run:"
echo "     pkg install qemu-system-aarch64-headless qemu-utils python -y"
echo "     termux-setup-storage"
echo "     cp -r /sdcard/Download/hackios ~/hackios"
echo "     cd ~/hackios"
echo "     ./setup_and_run_pixel.sh"
echo "2. Open RealVNC Viewer on your phone and connect to 127.0.0.1:5900"
echo ""
echo "--- METHOD B: USING ANDROID 15/16 LINUX TERMINAL (AVF / pKVM) ---"
echo "1. In Google's Linux Terminal (Debian):"
echo "     sudo apt update && sudo apt install -y qemu-system-arm python3"
echo "     cp -r /sdcard/Download/hackios ~/hackios"
echo "     cd ~/hackios"
echo "     ./setup_and_run_pixel.sh"
echo "2. Connect with VNC to 127.0.0.1:5900"
echo ""
