#!/usr/bin/env bash
# Compile les outils userland Mach-O ARM64 pour Shiba et assemble l'image APFS
set -e
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== Compilation des binaires Mach-O 64-bit pour Shiba ==="

TRIPLE="arm64-apple-darwin"
CLANG_FLAGS="-target $TRIPLE -fuse-ld=lld -nostdlib -ffreestanding -fno-stack-protector -fno-builtin"
LINK_FLAGS="-Wl,-e,_start -Wl,-pagezero_size,0x100000000 -Wl,-alias,_memset,_bzero"
INCLUDES="-I$ROOT_DIR/userland/include"

mkdir -p "$ROOT_DIR/userland/build_obj"

# 1. Compilation de la micro-libc
clang -target $TRIPLE -c "$ROOT_DIR/userland/src/mini.c" $INCLUDES -o "$ROOT_DIR/userland/build_obj/mini.o"
clang -target $TRIPLE -c "$ROOT_DIR/userland/src/start.S" -o "$ROOT_DIR/userland/build_obj/start.o"

# 2. Compilation des outils statiques
for prog in init stage0; do
    echo "[*] Compilation de $prog..."
    clang $CLANG_FLAGS $LINK_FLAGS \
        "$ROOT_DIR/userland/src/$prog.c" \
        "$ROOT_DIR/userland/build_obj/mini.o" \
        "$ROOT_DIR/userland/build_obj/start.o" \
        $INCLUDES \
        -o "$ROOT_DIR/userland/build_obj/$prog"
    
    file "$ROOT_DIR/userland/build_obj/$prog"
done

# 3. Assemblage du conteneur APFS (root.apfs)
echo "[*] Construction de root.apfs..."
TMP_ROOT=$(mktemp -d)
mkdir -p "$TMP_ROOT/sbin" "$TMP_ROOT/bin" "$TMP_ROOT/etc" "$TMP_ROOT/dev" "$TMP_ROOT/private/var" "$TMP_ROOT/private/preboot"
cp "$ROOT_DIR/userland/build_obj/init" "$TMP_ROOT/sbin/init"
ln -sf init "$TMP_ROOT/sbin/launchd"
cp "$ROOT_DIR/userland/build_obj/stage0" "$TMP_ROOT/sbin/stage0"
ln -sf /redwood "$TMP_ROOT/shiba"

python3 "$ROOT_DIR/tools/mkapfs.py" -z -o "$ROOT_DIR/userland/prebuilt/root.apfs" redwood="$TMP_ROOT"
rm -rf "$TMP_ROOT"

echo "=== Succès : Image générée dans $ROOT_DIR/userland/prebuilt/root.apfs ==="
