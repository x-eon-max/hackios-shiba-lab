# Google Tensor G3 (Zuma / Shiba) Hardware Specification for Darwin/XNU

Ce document récapitule les adresses physiques, les contrôleurs d'interruptions et la topologie matérielle extraits directement des arbres de périphériques officiels de Google AOSP (`android-gs-shusky-6.1-android16`).

---

## 1. Cartographie Mémoire (DRAM & MMIO)

| Région | Adresse Début | Adresse Fin | Taille | Description |
|---|---|---|---|---|
| **DRAM Physique** | `0x80000000` | `0x27FFFFFFF` | 8 Go | Mémoire principale physique (Shiba / Pixel 8) |
| **MMIO SoC Zuma** | `0x10000000` | `0x3FFFFFFF` | 768 Mo | Fenêtre globale des périphériques système |
| **TrustZone / Secure OS** | Carveout haut | Réservé | - | Réservé Titan M2 / Trusty OS |

---

## 2. Contrôleur d'interruptions (ARM GIC-v3 / GIC-600)

* **Compatibilité** : `arm,gic-v3` (nœud `interrupt-controller@10400000`)
* **GIC Distributor (GICD)** : `0x10400000` (taille: `0x10000`)
* **GIC Redistributors (GICR)** : `0x10440000` (taille: `0x200000`, 9 cœurs)

---

## 3. Topologie CPU ARMv9 (DynamIQ - 9 Cœurs)

| Core ID | MPIDR (`reg`) | Architecture | Capacité DMIPS | Cluster |
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

* **Décalage MPIDR (`core_shift`)** : `8`
* **Masque des cœurs lents (`small_cores`)** : `0x000F` (cœurs 0 à 3)
* **Cœur de boot recommandé (`bootcpu`)** : `8` (Cortex-X3)

---

## 4. Périphériques Système & Entrées/Sorties

* **Console Série (UART)** :
  * Samsung Exynos USI Serial (`samsung,exynos-uart`)
  * USI0 : `0x10880000`
  * USI1 : `0x10C80000`
* **Écran & Affichage** :
  * Dalle OLED Actua 1080 × 2400 (aspect 20:9, 120Hz)
  * Contrôleur : Samsung DPU (Exynos DRM)
* **Écran tactile** :
  * Contrôleur sur bus `spi_20` (driver Samsung `sec,sec_ts` S6SY79x ou ST `st,fts`)
  * IRQ GPIO : `gpn0[0]`
  * Reset GPIO : `gpp21[2]`
