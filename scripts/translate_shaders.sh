#!/usr/bin/env bash
# Translates iOS 16.5 Metal shaders (.metallib) to Vulkan SPIR-V using metal2vulkan
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$ROOT_DIR/tools/metal2vulkan/shiba_m2v_compiler.py"
PROFILE="$ROOT_DIR/tools/metal2vulkan/mali_g715_profile.json"
OUT_DIR="${1:-$ROOT_DIR/build/vk_shaders}"

echo "=== Shiba Metal2Vulkan Batch Shader Translator ==="
echo "[*] Output directory: $OUT_DIR"
echo "[*] Vulkan Profile:  $PROFILE"

mkdir -p "$OUT_DIR"

# 1. Run integration self-test first
echo "[*] Running metal2vulkan verification test..."
python3 "$COMPILER" --test --profile "$PROFILE"

# 2. Locate iOS 16.5 system metallib libraries
IOS_ROOT="$ROOT_DIR/../hackios-kernel/ios165/rootfs"
if [ ! -d "$IOS_ROOT" ]; then
    echo "[!] Warning: iOS 16.5 rootfs not found at $IOS_ROOT."
    echo "[*] Self-test passed. Run with path to a .metallib to translate specific shaders."
    exit 0
fi

echo "[*] Scanning for key system shaders..."
SHADERS=(
    "$IOS_ROOT/System/Library/VideoDecoders/AV1SW.metallib"
    "$IOS_ROOT/System/Library/Frameworks/QuartzCore.framework/default.metallib"
    "$IOS_ROOT/System/Library/Extensions/AppleMetalGLRenderer.bundle/default.metallib"
)

for lib in "${SHADERS[@]}"; do
    if [ -f "$lib" ]; then
        echo ""
        echo "--------------------------------------------------------"
        echo "[*] Translating: $(basename "$lib")"
        echo "--------------------------------------------------------"
        lib_name=$(basename "$(dirname "$lib")")_$(basename "$lib" .metallib)
        python3 "$COMPILER" "$lib" -o "$OUT_DIR/$lib_name" -p "$PROFILE" || true
    fi
done

echo ""
echo "=== Shader translation complete. Artifacts saved to $OUT_DIR ==="
