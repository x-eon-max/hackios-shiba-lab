#!/usr/bin/env bash
# Assemble l'image APFS complète pour Shiba / virt avec tous les tests unitaires
set -e
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== Assemblage du conteneur APFS (root.apfs) pour Shiba ==="

INIT_BIN="$ROOT_DIR/userland/prebuilt/init"
[ -f "$INIT_BIN" ] || { echo "Erreur: init non trouvé à $INIT_BIN"; exit 1; }

# Préparation du binaire statique child
mkdir -p "$ROOT_DIR/userland/build_obj"
if [ ! -f "$ROOT_DIR/userland/build_obj/child" ]; then
    echo "[*] Création du binaire statique child..."
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

# Préparation du répertoire racine temporaire
TMP_ROOT=$(mktemp -d)
mkdir -p "$TMP_ROOT/sbin" "$TMP_ROOT/bin" "$TMP_ROOT/etc" "$TMP_ROOT/dev" \
         "$TMP_ROOT/share" "$TMP_ROOT/LaunchDaemons" "$TMP_ROOT/empty" "$TMP_ROOT/hal" "$TMP_ROOT/xpc" \
         "$TMP_ROOT/private/var" "$TMP_ROOT/private/preboot"

# Binaires init et launchd
cp "$INIT_BIN" "$TMP_ROOT/sbin/init"
ln -sf init "$TMP_ROOT/sbin/launchd"

# Binaires additionnels
cp "$ROOT_DIR/userland/build_obj/child" "$TMP_ROOT/bin/child"
[ -f "$ROOT_DIR/../hackios-kernel/prebuilt/userland/var_store" ] && \
    cp "$ROOT_DIR/../hackios-kernel/prebuilt/userland/var_store" "$TMP_ROOT/bin/"
[ -f "$ROOT_DIR/../hackios-kernel/userland/com.redwood.varstore.plist" ] && \
    cp "$ROOT_DIR/../hackios-kernel/userland/com.redwood.varstore.plist" "$TMP_ROOT/LaunchDaemons/"

# Symlinks racine
ln -sf /redwood "$TMP_ROOT/shiba"
ln -sf private/var/tmp "$TMP_ROOT/tmp"

# Fichiers de configuration
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

# Script rc pour maintenir la machine active et éviter le bootloop (pause au lieu de reboot immédiat)
echo "sleep 999999" > "$TMP_ROOT/etc/rc"
cp "$ROOT_DIR/config/var.skel" "$TMP_ROOT/etc/var.skel"

# Fichier pattern (300 000 octets) pour le test mmap/read
python3 -c "import sys; sys.stdout.buffer.write(bytes((i*31 + (i>>8)) & 0xff for i in range(300000)))" > "$TMP_ROOT/share/pattern.bin"

# Assemblage du conteneur APFS
echo "[*] Construction de root.apfs..."
python3 "$ROOT_DIR/tools/mkapfs.py" -z -o "$ROOT_DIR/userland/prebuilt/root.apfs" redwood="$TMP_ROOT"
rm -rf "$TMP_ROOT"

echo "=== Succès : Image générée dans $ROOT_DIR/userland/prebuilt/root.apfs ==="
