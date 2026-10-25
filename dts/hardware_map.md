# Google Tensor G3 (Zuma / Shiba) Hardware Specification for Darwin/XNU

This specification documents the physical address maps, interrupt controllers, and CPU topology extracted from official Google AOSP Device Trees (`android-gs-shusky-6.1-android16`).

---

## 1. Memory Map (Physical DRAM & MMIO)

| Region | Start Address | End Address | Size | Description |
|---|---|---|---|---|
| **Physical DRAM** | `0x80000000` | `0x27FFFFFFF` | 8 GB | Main physical memory (Pixel 8 / Shiba) |
| **Zuma SoC MMIO** | `0x10000000` | `0x3FFFFFFF` | 768 MB | Global peripheral register window |
| **TrustZone / Secure OS** | High carveout | Reserved | - | Titan M2 / Trusty OS secure reservation |

---

## 2. Interrupt Controller (ARM GIC-v3 / GIC-600)

* **Compatibility**: `arm,gic-v3` (`interrupt-controller@10400000` node)
* **GIC Distributor (GICD)**: `0x10400000` (size: `0x10000`)
* **GIC Redistributors (GICR)**: `0x10440000` (size: `0x200000`, 9 cores)

---

## 3. ARMv9 CPU Topology (DynamIQ - 9 Cores)

| Core ID | MPIDR (`reg`) | Architecture | DMIPS Capacity | Cluster |
|---|---|---|---|---|
| **Core 0** | `0x000` | ARM Cortex-A510 | 193 | LITTLE (Cluster 0) |
| **Core 1** | `0x100` | ARM Cortex-A510 | 193 | LITTLE (Cluster 0) |
| **Core 2** | `0x200` | ARM Cortex-A510 | 193 | LITTLE (Cluster 0) |
| **Core 3** | `0x300` | ARM Cortex-A510 | 193 | LITTLE (Cluster 0) |
| **Core 4** | `0x400` | ARM Cortex-A715 | 927 | MID (Cluster 1) |
| **Core 5** | `0x500` | ARM Cortex-A715 | 927 | MID (Cluster 1) |
| **Core 6** | `0x600` | ARM Cortex-A715 | 927 | MID (Cluster 1) |
| **Core 7** | `0x700` | ARM Cortex-A715 | 927 | MID (Cluster 1) |
| **Core 8** | `0x800` | ARM Cortex-X3 | 1024 | BIG (Cluster 2) |

* **MPIDR Shift (`core_shift`)**: `8`
* **Slow Cores Mask (`small_cores`)**: `0x000F` (cores 0 through 3)
* **Recommended Boot Core (`bootcpu`)**: `8` (Cortex-X3)

---

## 4. Peripherals & I/O

* **Serial Console (UART)**:
  * Samsung Exynos USI Serial (`samsung,exynos-uart`)
  * USI0: `0x10880000`
  * USI1: `0x10C80000`
* **Display**:
  * Actua OLED Display (1080 × 2400, 20:9 aspect ratio, 120 Hz)
  * Controller: Samsung DPU (Exynos DRM)
* **Touchscreen**:
  * Connected over `spi_20` bus (Samsung `sec,sec_ts` S6SY79x or ST `st,fts` driver)
  * GPIO IRQ: `gpn0[0]`
  * GPIO Reset: `gpp21[2]`

---

## 5. GPU & Hardware Graphics Acceleration (Mali-G715 & Metal2Vulkan)

* **Architecture**: ARM Mali-G715 Immortalis (10 cores, Valhall 5th Generation / CSF)
* **MMIO Base Address**: `0x1F000000` (length `0x480000` / 4.5 MB)
* **GIC Interrupts**:
  * `IRQ_G3D_IRQJOB_G3D` (GIC SPI 160)
  * `IRQ_G3D_IRQMMU_G3D` (GIC SPI 161)
  * `IRQ_G3D_IRQGPU_G3D` (GIC SPI 162)
* **Firmware / CSF**: Command Stream Frontend (firmware-driven job submission)
* **Vulkan Driver Baseline**:
  * Vulkan API version: 1.3
  * Hardware features: Timeline semaphores, dynamic rendering, synchronization2, descriptor indexing
* **Metal2Vulkan Acceleration Layer**:
  * **Role**: Translates Apple AIR (Apple Intermediate Representation / LLVM bitcode inside `.metallib` files) directly to Vulkan SPIR-V 1.3 / 1.2.
  * **Runtime Bridge**: `ShibaMetal` driver exposing native `_MTLDevice` / `<MTLDeviceSPI>` Objective-C runtime classes backed by `metal2vulkan-runtime` on top of Mali Vulkan (`libvulkan.so`).
  * **Pipeline Cache**: Pre-compiled SPIR-V pipelines for QuartzCore and system frameworks to achieve sub-millisecond draw calls without runtime JIT compilation delays.

