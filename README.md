# HackIOS Shiba Lab — Expérimentation Google Pixel 8 (Tensor G3)

Ce laboratoire regroupe l'ensemble des travaux de reverse-engineering, d'analyse du Device Tree, des correctifs de chargeur et des modules d'adaptation pour porter **HackIOS** (l'exécution de XNU Darwin et de l'userland natif iOS 16.5) sur le **Google Pixel 8** (*Shiba* / SoC Tensor G3).

---

## 1. Structure du Répertoire

```text
hackios-shiba-lab/
├── config/
│   ├── shiba.conf                   # Profil de périphérique (variables, bootargs, mémoire)
│   └── shiba.platform.c             # Définition de la plateforme pour xnuloader
├── dts/
│   ├── hardware_map.md              # Fiche technique du mapping matériel Tensor G3
│   ├── zuma.dtsi                    # Device Tree source de base (GICv3, bus odm, timers)
│   ├── zuma-cpu.dtsi                # Topologie 9 cœurs (4x A510, 4x A715, 1x X3)
│   ├── zuma-usi.dtsi                # Adresses et contrôleurs série USI Exynos
│   ├── zuma-common-touch.dtsi       # Bus SPI 20 et GPIOs d'écran tactile
│   └── zuma-sec-touch.dtsi          # Nœud du contrôleur tactile Samsung S6SY79x
├── loader/
│   ├── loader.efi                   # Chargeur UEFI ARM64 PE32+ compilé pour Shiba
│   └── patches/
│       └── loader_shiba_platform.patch # Patch pour intégrer Shiba dans xnuloader
├── userland/
│   ├── include/
│   │   ├── shiba_input.h            # Protocole des événements tactiles normalisés
│   │   └── mini.h                   # Déclarations micro-libc (libmini)
│   ├── src/
│   │   ├── init.c                   # PID 1 adapté avec point de montage et checks /shiba
│   │   ├── stage0.c                 # Stage 0 avec lien symbolique /shiba -> /redwood
│   │   ├── inject.c                 # Hooks Backboardd / QuartzCore (1080x2400)
│   │   ├── rwtouch.c                # Injecteur d'événements tactiles pour tests
│   │   ├── mini.c                   # Implémentation libc légère (bzero, memset, etc.)
│   │   └── start.S                  # Point d'entrée assembleur AAPCS64
│   └── prebuilt/
│       ├── init                     # Binaire Mach-O 64-bit arm64 testé
│       ├── stage0                   # Binaire Mach-O 64-bit arm64 testé
│       └── root.apfs                # Conteneur APFS amorçable (4 Mo)
├── tools/
│   ├── mkapfs.py                    # Générateur d'images APFS sous Linux
│   └── mkpayload.py                 # Assembleur de conteneur XNUP (kernel + ramdisk)
└── scripts/
    ├── run_qemu_test.sh             # Banc de test automatisé sous QEMU ARM64
    ├── build_userland.sh            # Script de cross-compilation Mach-O
    └── extract_dtb.sh               # Outil d'extraction DTS pour Pixel 8
```

---

## 2. État d'Avancement & Résultats

### Validé dans le banc de test QEMU ARM64
* **Démarrage du noyau XNU** : Version `22.5.0` (Darwin iOS 16.5) initialisée avec succès.
* **Support APFS** : Le pilote APFS lit et monte l'image mémoire `root.apfs`.
* **Exécution du Processus 1** : L'exécutable `/sbin/launchd` (`init`) prend le contrôle de l'espace utilisateur.
* **Primitives système** : Primitives BSD (`fork`, `pipe`, `mmap`, `devfs`, `sysctl`) validées avec succès (`[ ok ]`).
* **Namespace Shiba** : Le point de montage `/shiba` et les nœuds tactiles `/dev/shiba-touch` sont reconnus.

---

## 3. Utilisation Rapide

### Lancer le test QEMU
Pour rejouer le boot complet du noyau et de l'userland :
```bash
./scripts/run_qemu_test.sh
```

### Recompiler l'Userland et générer `root.apfs`
```bash
./scripts/build_userland.sh
```

### Extraire le Device Tree d'un Pixel 8 réel
```bash
./scripts/extract_dtb.sh --adb
```

---

## 4. Feuille de Route pour le Pixel 8 Physique

1. **Firmware de démarrage** : Développer un shim intermédiaire (LinuxBoot / Kexec payload) pour charger `loader.efi` et passer outre l'absence d'EDK2/Mu-Silicium sur Tensor G3.
2. **Pilote Framebuffer** : Mapper le contrôleur d'affichage Samsung DPU pour obtenir la console vidéo native sur la dalle 1080×2400.
3. **Extraction de l'IPSW iOS 16.5** : Exécuter `ios165/fetch.sh` pour générer `system.apfs` (2.5 Go) contenant `SpringBoard` et la `dyld_shared_cache`.
