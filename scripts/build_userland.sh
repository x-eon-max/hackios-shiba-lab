#!/usr/bin/env bash
# Assembles the full APFS ramdisk image for Shiba / virt with all unit tests
set -e
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== Assembling APFS Container (root.apfs) for Shiba ==="

INIT_BIN="$ROOT_DIR/userland/prebuilt/init"
[ -f "$INIT_BIN" ] || { echo "Error: init binary not found at $INIT_BIN"; exit 1; }

# Prepare static child binary
mkdir -p "$ROOT_DIR/userland/build_obj"
if [ ! -f "$ROOT_DIR/userland/build_obj/child" ]; then
    echo "[*] Creating static child binary..."
    python3 -c "
with open('$ROOT_DIR/../hackios-kernel/prebuilt/userland/hello', 'rb') as f:
    data = bytearray(f.read())
data[0x3e24:0x3e30] = bytes([
    0x30, 0x00, 0x80, 0x52,  # mov w16, #1 (SYS_exit)
    0x40, 0x05, 0x80, 0xd2,  # mov x0, #42 (exit 42)
    0x01, 0x10, 0x00, 0xd4   # svc #0x80
])
with open('$ROOT_DIR/userland/build_obj/child', 'wb') as f:
    f.write(data)
"
    chmod 0755 "$ROOT_DIR/userland/build_obj/child"
fi

# Prepare temporary root filesystem layout
TMP_ROOT=$(mktemp -d)
mkdir -p "$TMP_ROOT/sbin" "$TMP_ROOT/bin" "$TMP_ROOT/etc" "$TMP_ROOT/dev" \
         "$TMP_ROOT/share" "$TMP_ROOT/LaunchDaemons" "$TMP_ROOT/empty" "$TMP_ROOT/hal" "$TMP_ROOT/xpc" \
         "$TMP_ROOT/private/var" "$TMP_ROOT/private/preboot"

# init and launchd binaries
cp "$INIT_BIN" "$TMP_ROOT/sbin/init"
ln -sf init "$TMP_ROOT/sbin/launchd"

# Additional helper binaries
cp "$ROOT_DIR/userland/build_obj/child" "$TMP_ROOT/bin/child"
[ -f "$ROOT_DIR/../hackios-kernel/prebuilt/userland/var_store" ] && \
    cp "$ROOT_DIR/../hackios-kernel/prebuilt/userland/var_store" "$TMP_ROOT/bin/"
[ -f "$ROOT_DIR/../hackios-kernel/userland/com.redwood.varstore.plist" ] && \
    cp "$ROOT_DIR/../hackios-kernel/userland/com.redwood.varstore.plist" "$TMP_ROOT/LaunchDaemons/"

# Root symlinks & directories
mkdir -p "$TMP_ROOT/shiba/config" "$TMP_ROOT/shiba/shaders" "$TMP_ROOT/shiba/bin"
ln -sf /shiba "$TMP_ROOT/redwood"
cp "$ROOT_DIR/config/shiba.conf" "$TMP_ROOT/shiba/config/shiba.conf"
if [ -f "$ROOT_DIR/tools/metal2vulkan/mali_g715_profile.json" ]; then
    cp "$ROOT_DIR/tools/metal2vulkan/mali_g715_profile.json" "$TMP_ROOT/etc/mali_g715_profile.json"
    cp "$ROOT_DIR/tools/metal2vulkan/mali_g715_profile.json" "$TMP_ROOT/shiba/config/mali_g715_profile.json"
fi
ln -sf private/var/tmp "$TMP_ROOT/tmp"

# System configuration files
cat << 'EOF' > "$TMP_ROOT/etc/motd"
Darwin on Shiba (Tensor G3 / Pixel 8)

                    .:'
                 __ :'__
              .'`__`-'__``.
             :__________.-'
             :_________:
              :_________`-;
               `.__.-.__.'

       [ Apple Inc. - Darwin 22.5.0 ]
EOF

# rc script to keep the session alive
echo "sleep 999999" > "$TMP_ROOT/etc/rc"
cp "$ROOT_DIR/config/var.skel" "$TMP_ROOT/etc/var.skel"

# Test pattern file (300,000 bytes) for mmap/read verification
python3 -c "import sys; sys.stdout.buffer.write(bytes((i*31 + (i>>8)) & 0xff for i in range(300000)))" > "$TMP_ROOT/share/pattern.bin"

# Assemble APFS container
echo "[*] Packaging root.apfs..."
python3 "$ROOT_DIR/tools/mkapfs.py" -z -o "$ROOT_DIR/userland/prebuilt/root.apfs" redwood="$TMP_ROOT"
rm -rf "$TMP_ROOT"

echo "=== Success: APFS image created at $ROOT_DIR/userland/prebuilt/root.apfs ==="
