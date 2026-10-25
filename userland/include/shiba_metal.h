/*
 * Shiba Metal-to-Vulkan Driver Interface for Google Pixel 8 (Tensor G3)
 *
 * Bridges Apple's Metal framework (MTLDevice / MTLDeviceSPI) to Vulkan 1.3
 * using metal2vulkan (ARM Mali-G715 Immortalis GPU).
 */
#ifndef _SHIBA_METAL_H_
#define _SHIBA_METAL_H_

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SHIBA_METAL_DRIVER_NAME        "ShibaMetal"
#define SHIBA_METAL_BUNDLE_ID          "com.google.shiba.metal"
#define SHIBA_METAL_MAX_BUFFER_LENGTH  (1ULL << 32) /* 4 GB */

/*
 * C-level FFI bridge declarations to metal2vulkan-runtime
 */
typedef void *shiba_m2v_device_t;
typedef void *shiba_m2v_queue_t;
typedef void *shiba_m2v_buffer_t;
typedef void *shiba_m2v_texture_t;
typedef void *shiba_m2v_pipeline_t;

struct shiba_m2v_texture_desc {
    uint32_t pixel_format;
    uint32_t width;
    uint32_t height;
    uint32_t depth;
    uint32_t mip_levels;
    uint32_t sample_count;
    uint32_t usage;
};

struct shiba_m2v_draw_params {
    uint32_t primitive_type;
    uint32_t vertex_start;
    uint32_t vertex_count;
    uint32_t instance_count;
};

/* Device lifecycle */
int shiba_m2v_init(const char *profile_json_path);
shiba_m2v_device_t shiba_m2v_get_device(void);
uint64_t shiba_m2v_get_max_buffer_length(void);
bool shiba_m2v_supports_amplification(uint32_t count);

/* Memory and Buffers */
shiba_m2v_buffer_t shiba_m2v_buffer_create(size_t length, uint32_t options);
void *shiba_m2v_buffer_contents(shiba_m2v_buffer_t buffer);
void shiba_m2v_buffer_destroy(shiba_m2v_buffer_t buffer);

/* Textures */
shiba_m2v_texture_t shiba_m2v_texture_create(const struct shiba_m2v_texture_desc *desc);
void shiba_m2v_texture_destroy(shiba_m2v_texture_t texture);

/* Pipelines and Shaders */
shiba_m2v_pipeline_t shiba_m2v_pipeline_compile_compute(const void *air_bytes, size_t length, const char *kernel_name);
shiba_m2v_pipeline_t shiba_m2v_pipeline_compile_render(const void *air_bytes, size_t length,
                                                       const char *vert_name, const char *frag_name,
                                                       uint32_t color_format);
void shiba_m2v_pipeline_destroy(shiba_m2v_pipeline_t pipeline);

/* Command Submission */
shiba_m2v_queue_t shiba_m2v_queue_create(void);
void shiba_m2v_queue_submit(shiba_m2v_queue_t queue, shiba_m2v_pipeline_t pipeline, const struct shiba_m2v_draw_params *draw);
void shiba_m2v_queue_wait_idle(shiba_m2v_queue_t queue);
void shiba_m2v_queue_destroy(shiba_m2v_queue_t queue);

#ifdef __cplusplus
}
#endif

#endif /* _SHIBA_METAL_H_ */
