#!/usr/bin/env python3
"""
Shiba Metal2Vulkan Pipeline Compiler & Translator
-------------------------------------------------
Translates iOS 16.5 Apple Intermediate Representation (AIR) shaders
from .metallib containers into standard Vulkan SPIR-V pipelines and
pipeline metadata descriptors for Google Pixel 8 (ARM Mali-G715 / Tensor G3).

Powered by metal2vulkan (https://github.com/steelbrain/metal2vulkan).
"""

import os
import sys
import json
import struct
import argparse
import subprocess
from pathlib import Path

DEFAULT_M2V_PATHS = [
    os.path.expanduser("~/metal2vulkan/target/release/metal2vulkan"),
    os.path.expanduser("~/metal2vulkan/target/debug/metal2vulkan"),
    "/usr/local/bin/metal2vulkan",
    "/usr/bin/metal2vulkan"
]

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_PROFILE = SCRIPT_DIR / "mali_g715_profile.json"


TYPES = {0: 'vertex', 1: 'fragment', 2: 'kernel', 3: 'unqualified', 4: 'visible',
         5: 'extern', 6: 'intersection'}


class MetallibReader:
    """Parses Apple .metallib container binary format to inspect functions."""

    def __init__(self, path):
        self.path = Path(path)
        with open(self.path, "rb") as f:
            self.data = f.read()
        self.functions = []
        self.function_meta = []
        self._parse()

    def _parse(self):
        b = self.data
        if len(b) < 32 or b[:4] != b"MTLB":
            raise ValueError(f"Invalid metallib magic: {b[:4]}")
        funcs_off = struct.unpack_from('<Q', b, 0x18)[0]
        p = funcs_off
        if p >= len(b):
            return
        count = struct.unpack_from('<I', b, p)[0]
        p += 4
        for _ in range(count):
            if p + 4 > len(b):
                break
            size = struct.unpack_from('<I', b, p)[0]
            q, end = p + 4, p + size
            f = {}
            while q < end and q + 6 <= len(b):
                tag = b[q:q + 4]
                if tag == b'ENDT':
                    break
                ln = struct.unpack_from('<H', b, q + 4)[0]
                val = b[q + 6:q + 6 + ln]
                if tag == b'NAME':
                    f['name'] = val.rstrip(b'\0').decode('utf-8', 'replace')
                elif tag == b'TYPE':
                    f['type'] = TYPES.get(val[0], 'type%d' % val[0])
                q += 6 + ln
            name = f.get('name')
            if name and name not in self.functions:
                self.functions.append(name)
                self.function_meta.append(f)
            p = end


def find_metal2vulkan_binary():
    """Locate the metal2vulkan translator binary."""
    env_bin = os.environ.get("METAL2VULKAN_BIN")
    if env_bin and os.path.isfile(env_bin) and os.access(env_bin, os.X_OK):
        return env_bin
    for p in DEFAULT_M2V_PATHS:
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    # Try PATH
    import shutil
    which = shutil.which("metal2vulkan")
    if which:
        return which
    return None


def translate_function(m2v_bin, metallib_path, func_name, out_dir, profile_path, extra_args=None):
    """
    Translates a single function from a metallib into Vulkan SPIR-V.
    """
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    out_spv = out_dir / f"{func_name}.spv"
    out_meta = out_dir / f"{func_name}.json"

    cmd = [
        str(m2v_bin),
        str(metallib_path),
        str(out_spv),
        "--profile", str(profile_path),
        "--function", func_name,
        "--emit-meta", str(out_meta),
        "--no-spirv-val"
    ]
    if extra_args:
        cmd.extend(extra_args)

    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    return res.returncode == 0, res.stdout, res.stderr, out_spv, out_meta


def batch_translate_library(m2v_bin, metallib_path, out_dir, profile_path):
    """
    Reads all entry points in a metallib and translates each to SPIR-V.
    """
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    reader = MetallibReader(metallib_path)
    print(f"[*] Processing {metallib_path.name} ({len(reader.functions)} functions detected)")
    results = {}
    success_count = 0

    # Common function constant heuristics
    common_constants = [
        [],  # try without constants first
        ["--constant", "0:uint:8"],
        ["--constant", "0:bool:false"],
        ["--constant", "0:uint:1"],
    ]

    # Find candidate vertex shader if any
    candidate_vertex = None
    for meta in reader.function_meta:
        if meta.get("type") == "vertex":
            candidate_vertex = meta.get("name")
            break

    import re
    const_pattern = re.compile(r"FunctionConstant\s*\{\s*index:\s*(\d+)\s*\}")

    for meta in reader.function_meta:
        fn = meta.get("name")
        ftype = meta.get("type", "kernel")
        ok = False
        last_err = ""

        # For fragment shaders, attempt to pair with vertex shader
        extra_render_args = []
        if ftype == "fragment" and candidate_vertex:
            extra_render_args = [
                "--function", candidate_vertex,
                "--fragment", fn,
                "--color-format", "0:BGRA8Unorm"
            ]

        # Iterative auto-resolution of required function constants
        active_constants = []
        max_attempts = 6
        for attempt in range(max_attempts):
            out_spv = Path(out_dir) / f"{fn}.spv"
            out_meta = Path(out_dir) / f"{fn}.json"

            cmd = [
                str(m2v_bin),
                str(metallib_path),
                str(out_spv),
                "--profile", str(profile_path),
                "--emit-meta", str(out_meta),
                "--no-spirv-val"
            ]
            if extra_render_args:
                cmd.extend(extra_render_args)
            else:
                cmd.extend(["--function", fn])
            cmd.extend(active_constants)

            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            ok = res.returncode == 0
            spv = out_spv
            meta = out_meta
            last_err = res.stderr.strip()

            if ok:
                break

            # Check if metal2vulkan requested a specific missing function constant
            match = const_pattern.search(last_err)
            if match:
                missing_idx = match.group(1)
                # Try uint:8 first (standard bitdepth in iOS shaders)
                cand = f"{missing_idx}:uint:8"
                if cand not in active_constants:
                    active_constants.extend(["--constant", cand])
                    continue
                # If uint:8 already present, try bool:false
                cand_bool = f"{missing_idx}:bool:false"
                if cand_bool not in active_constants:
                    active_constants.remove(cand)
                    active_constants.extend(["--constant", cand_bool])
                    continue
            break

        if ok:
            print(f"  [PASS] ({ftype}) {fn} -> {spv.name}")
            success_count += 1
            results[fn] = {"status": "PASS", "spv": str(spv), "meta": str(meta)}
        else:
            # Print single-line summary of refusal reason
            refusal = last_err.split("\n")[-1] if last_err else "unknown refusal"
            print(f"  [SKIP] ({ftype}) {fn}: {refusal}")
            results[fn] = {"status": "SKIP", "error": refusal}

    print(f"[*] Completed {metallib_path.name}: {success_count}/{len(reader.functions)} entry points translated.")
    return results


def main():
    parser = argparse.ArgumentParser(description="Shiba Metal2Vulkan Compiler for iOS on Google Pixel 8")
    parser.add_argument("metallib", nargs="?", help="Path to input .metallib file")
    parser.add_argument("-o", "--out-dir", default="./vk_shaders", help="Output directory for SPIR-V and metadata")
    parser.add_argument("-p", "--profile", default=str(DEFAULT_PROFILE), help="Khronos Vulkan profile JSON")
    parser.add_argument("-f", "--function", help="Specific function/kernel name to translate")
    parser.add_argument("-c", "--constant", action="append", help="Function constant (ID:TYPE:VALUE)")
    parser.add_argument("--list", action="store_true", help="List entry points in the metallib and exit")
    parser.add_argument("--test", action="store_true", help="Run self-test against sample iOS shaders")
    args = parser.parse_args()

    m2v_bin = find_metal2vulkan_binary()
    if not m2v_bin and not args.list:
        print("[-] Error: metal2vulkan binary not found. Build it with:", file=sys.stderr)
        print("    cd ~/metal2vulkan && cargo build -p metal2vulkan --features cli", file=sys.stderr)
        sys.exit(1)

    if args.test:
        print("=== Running Shiba Metal2Vulkan Integration Test ===")
        print(f"[*] Found metal2vulkan at: {m2v_bin}")
        test_lib = Path("/home/ethan/dualsensectl-gui/hackios-kernel/ios165/rootfs/System/Library/VideoDecoders/AV1SW.metallib")
        if not test_lib.exists():
            print(f"[-] Test library not found at {test_lib}")
            sys.exit(1)

        test_out = Path("/tmp/shiba_m2v_test")
        extra = ["--constant", "0:uint:8"]
        ok, out, err, spv, meta = translate_function(
            m2v_bin, test_lib, "BlitKernel_Unorm", test_out, args.profile, extra_args=extra
        )
        if ok and spv.exists() and meta.exists():
            print(f"[+] SUCCESS: Compiled BlitKernel_Unorm ({spv.stat().st_size} bytes SPIR-V, {meta.stat().st_size} bytes metadata)")
            with open(meta, "r") as f:
                info = json.load(f)
            print(f"[+] Vulkan Pipeline Kind: {info.get('kind')}, Reconvergence: {info['stages'][0].get('reconvergence')}")
            sys.exit(0)
        else:
            print(f"[-] Test failed: {err}")
            sys.exit(1)

    if not args.metallib:
        parser.print_help()
        sys.exit(1)

    metallib_path = Path(args.metallib)
    if not metallib_path.is_file():
        print(f"[-] Error: file not found: {metallib_path}", file=sys.stderr)
        sys.exit(1)

    if args.list:
        reader = MetallibReader(metallib_path)
        print(f"Functions in {metallib_path.name}:")
        for fn in reader.functions:
            print(f"  - {fn}")
        sys.exit(0)

    if args.function:
        extra = []
        if args.constant:
            for c in args.constant:
                extra.extend(["--constant", c])
        ok, out, err, spv, meta = translate_function(
            m2v_bin, metallib_path, args.function, args.out_dir, args.profile, extra_args=extra
        )
        if ok:
            print(f"[+] Successfully compiled {args.function} to {spv}")
        else:
            print(f"[-] Failed to compile {args.function}: {err}", file=sys.stderr)
            sys.exit(1)
    else:
        batch_translate_library(m2v_bin, metallib_path, args.out_dir, args.profile)


if __name__ == "__main__":
    main()
