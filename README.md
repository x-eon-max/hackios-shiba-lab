# HackiOS Shiba Lab — Google Pixel 8 (Tensor G3) Research & Porting

This laboratory brings together all reverse engineering, Device Tree analysis, bootloader adaptation patches, and userland modules required to port **HackiOS** (booting Apple's Darwin XNU kernel and running native iOS 16.5 userland) to the **Google Pixel 8** (*Shiba* / Tensor G3 SoC).

---

## 1. Directory Structure

```text
hackios-shiba-lab/
├── config/
│   ├── shiba.conf                   # Device profile (environment vars, bootargs, memory base)
│   ├── shiba.platform.c             # Platform definition for xnuloader
│   └── var.skel                     # Initial skeleton for /private/var
├── dts/
│   ├── hardware_map.md              # Tensor G3 hardware memory & controller specification
│   ├── zuma.dtsi                    # Base Device Tree Source (GICv3, odm bus, timers)
│   ├── zuma-cpu.dtsi                # 9-core CPU topology (4x A510, 4x A715, 1x X3)
│   ├── zuma-usi.dtsi                # Samsung Exynos USI serial controllers & registers
│   ├── zuma-common-touch.dtsi       # SPI bus 20 and touchscreen GPIO definitions
│   └── zuma-sec-touch.dtsi          # Samsung S6SY79x touch controller node
├── loader/
│   ├── loader.efi                   # Prebuilt ARM64 PE32+ UEFI loader tailored for Shiba
│   └── patches/
│       └── loader_shiba_platform.patch # Patch integrating platform_shiba into xnuloader
├── userland/
│   ├── include/
│   │   ├── shiba_input.h            # Touch event protocol declarations
│   │   └── mini.h                   # Micro-libc headers (libmini)
│   ├── src/
│   │   ├── init.c                   # Adapted PID 1 launchd with /shiba mount & checks
│   │   ├── stage0.c                 # Stage 0 loader with /shiba compatibility symlink
│   │   ├── inject.c                 # Backboardd & QuartzCore hooks (1080x2400 geometry)
│   │   ├── rwtouch.c                # Synthetic touch event injector for testing
│   │   ├── mini.c                   # Lightweight libc implementation (memset, printf, etc.)
│   │   └── start.S                  # Low-level AAPCS64 assembly entry point
│   └── prebuilt/
│       ├── init                     # Tested Mach-O 64-bit arm64 binary
│       ├── stage0                   # Tested Mach-O 64-bit arm64 binary
│       └── root.apfs                # Minimal bootable APFS ramdisk container (4 MB)
├── tools/
│   ├── mkapfs.py                    # Standalone pure-Python APFS container builder
│   └── mkpayload.py                 # Multi-component XNUP payload assembler
└── scripts/
    ├── run_qemu_test.sh             # Automated validation test harness under QEMU ARM64
    ├── run_live_gui.sh              # Live QEMU execution with graphical GTK display
    ├── run_full_ios.sh              # Full iOS 16.5 boot script with SpringBoard & CoverSheet
    ├── push_to_pixel.sh             # Automated ADB deployment script for physical Pixel 8
    ├── build_userland.sh            # Mach-O cross-compilation & APFS image packaging
    ├── extract_dtb.sh               # Live Device Tree extractor from connected Pixel 8
    └── screendump.sh                # PPM / PNG framebuffer capture helper
```

---

## 2. Progress & Validated Milestones

### Verified in QEMU ARM64 Test Harness
* **Darwin XNU Kernel Boot**: Version `22.5.0` (iOS 16.5 release) successfully initialized.
* **APFS Container Mount**: Apple's native APFS driver mounts the ramdisk container (`root.apfs`) on `/dev/md1` and `system.apfs` on `/dev/md0`.
* **Process 1 (PID 1) Execution**: `/sbin/launchd` (`init`) gains full control of userspace.
* **BSD System Primitives**: Validated BSD syscalls (`fork`, `execve`, `pipe`, `mmap`, `devfs`, `sysctl`) with zero assertion errors (`[ ok ]`).
* **Shiba Platform Integration**: Mount point `/shiba` and touch device nodes `/dev/shiba-touch` recognized.
* **Full SpringBoard & CoverSheet**: In full iOS runs, `backboardd` dismisses the Apple boot logo and passes screen control to `SpringBoard`, rendering the iOS 16 CoverSheet lockscreen with full widgets and clock.

### Verified on Physical Google Pixel 8 (Tensor G3)
* **Automated ADB Transfer**: Full deployment bundle (~2.65 GB) transferred to `/sdcard/Download/hackios/`.
* **Portability Fixes**: Replaced raw Linux `os.copy_file_range` with streaming fallback chunking for Android Bionic compatibility.
* **XNU Address Window Configuration**: Identified 7 GB virtual window (`QEMU_RAM_GB=7`) required to map `system.apfs` at `0xFC000000` above resident ramdisk offsets without triggering contiguous RAM exhaustion.
* **Hardware Hypervisor Discovery**: Confirmed Google's **pKVM** (*Protected KVM* / `kvm.arm-protected`) active on Pixel 8 with native `/dev/kvm` support.

---

## 3. Quick Start

### 1. Run the QEMU Test Harness
Verify the kernel and userland boot sequence in a headless test harness:
```bash
./scripts/run_qemu_test.sh
```

### 2. Recompile Userland & Rebuild `root.apfs`
Cross-compile the custom Mach-O binaries and assemble the APFS ramdisk:
```bash
./scripts/build_userland.sh
```

### 3. Extract Device Tree from a Connected Pixel 8
Extract the live Device Tree from your device over USB:
```bash
./scripts/extract_dtb.sh --adb
```

### 4. Deploy to Physical Pixel 8 via ADB
Automatically sync the complete bundle (`system.apfs`, kernel, UEFI firmware, and runner scripts) to your phone:
```bash
./scripts/push_to_pixel.sh
```

---

## 4. Hardware Virtualization (pKVM) on Pixel 8

On Google Pixel 8 (Tensor G3), Google includes **pKVM** (Protected KVM) in the firmware. This allows hardware-accelerated virtualization directly on the phone's Cortex-X3 and Cortex-A715 cores:

1. **Android 15 / 16 Linux Terminal**:
   * Enable Developer Options: **Settings > System > Developer options**.
   * Turn on **Linux development environment / Terminal**.
   * Launch the official Google Terminal app (Debian guest with direct `/dev/kvm` access).
2. **Native KVM Execution**:
   * Run QEMU with hardware acceleration:
     ```bash
     qemu-system-aarch64 -accel kvm -cpu host ...
     ```
   * iOS boots in **under 30 seconds** at full native hardware speed, avoiding software TCG translation overhead!

---

## 5. Physical Pixel 8 Bare-Metal Roadmap

1. **Boot Firmware Shim**: Implement a lightweight LinuxBoot / kexec trampoline payload to load `loader.efi` directly from ABL (`fastboot boot boot.img`).
2. **Native Display Driver**: Map the Samsung DPU (Exynos DRM) controller for 1080×2400 120Hz native OLED framebuffer output.
3. **Touchscreen Driver**: Bridge Samsung S6SY79x SPI touch reports into normalized HackiOS touch protocol packets.

---

## Disclaimer
HackiOS is an independent research project and is not affiliated with, authorized, or endorsed by Apple Inc. or Google LLC. iOS, iPhone, and Apple are trademarks of Apple Inc. Android, Pixel, and Google are trademarks of Google LLC.
