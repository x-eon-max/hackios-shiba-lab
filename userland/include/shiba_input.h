/*
 * /dev/shiba-touch: touch samples on their way from whoever produces them to the
 * program that turns them into HID events for the window server on Google Pixel 8 (Tensor G3).
 */
#ifndef _SYS_SHIBA_INPUT_H_
#define _SYS_SHIBA_INPUT_H_

#include <stdint.h>

#define SHIBA_TOUCH_DEVICE    "/dev/shiba-touch"

#define SHIBA_TOUCH_DOWN      1       /* a finger has landed */
#define SHIBA_TOUCH_MOVE      2
#define SHIBA_TOUCH_UP        3       /* it has lifted (x, y: where it was last) */
#define SHIBA_BUTTON_DOWN     4       /* a hardware button; `finger` says which, x and y are 0 */
#define SHIBA_BUTTON_UP       5

#define SHIBA_BUTTON_LOCK     1       /* the side/power button */
#define SHIBA_BUTTON_VOLUME_UP 2
#define SHIBA_BUTTON_VOLUME_DOWN 3
#define SHIBA_BUTTON_HOME     4

struct shiba_touch {
	uint64_t time;                  /* mach_absolute_time() when the sample was posted */
	uint32_t type;                  /* SHIBA_TOUCH_* or SHIBA_BUTTON_DOWN/UP */
	uint32_t finger;                /* which finger, from 0 (or which button) */
	uint32_t x, y;                  /* position on display: 0 = left/top edge, 65535 = right/bottom edge */
};

#ifdef KERNEL
/* For drivers; not from interrupt context. */
void shiba_touch_post(uint32_t type, uint32_t finger, uint32_t x, uint32_t y);
void shiba_input_init(void);
void shiba_sec_touch_init(void);        /* Samsung S6SY79x / ST FTS touch controller on Pixel 8 */
void shiba_cpufreq_init(void);          /* Zuma DVFS scaling */
#endif

#endif /* _SYS_SHIBA_INPUT_H_ */
