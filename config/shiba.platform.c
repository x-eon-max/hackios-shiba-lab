/*
 * shiba: Google Pixel 8 (Tensor G3 / Zuma).
 * Paste into xnuloader/loader.c next to platform_redwood and add &platform_shiba to platforms[].
 */
static const struct platform platform_shiba = {
	.name = "shiba",
	.io_base = 0x10000000, .io_size = 0x30000000,   /* Window covering Zuma peripherals */
	.gic_dist = 0x10400000, .gic_redist = 0x10440000,
	.uart = 0,                                      /* Exynos UART via driver */
	.log_other_cpu = 1,
	.cores = 9, .core_shift = 8,
	.small_cores = 0x000F,                          /* Cores 0-3: Cortex-A510 (capacity 193) */
	.fb_base = 0x0,                                 /* Provided by UEFI GOP */
};
