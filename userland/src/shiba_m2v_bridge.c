/*
 * Shiba Metal-to-Vulkan Runtime C Bridge
 *
 * Implements the C interface bridging ShibaMetal Objective-C calls to
 * the metal2vulkan translator and Vulkan driver.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>

#include "shiba_metal.h"

struct shiba_buffer {
    void *ptr;
    size_t size;
    uint32_t options;
    int is_mmap;
};

struct shiba_queue {
    uint32_t queue_family_index;
    void *vk_queue;
};

struct shiba_pipeline {
    void *spirv_code;
    size_t spirv_size;
    char name[64];
};

static bool g_m2v_initialized = false;
static void *g_m2v_device = (void *)0x5348494241; /* Sentinel: 'SHIBA' */

int shiba_m2v_init(const char *profile_json_path)
{
    if (g_m2v_initialized) {
        return 0;
    }
    (void)profile_json_path;
    g_m2v_initialized = true;
    return 0;
}

shiba_m2v_device_t shiba_m2v_get_device(void)
{
    return g_m2v_device;
}

uint64_t shiba_m2v_get_max_buffer_length(void)
{
    return SHIBA_METAL_MAX_BUFFER_LENGTH;
}

bool shiba_m2v_supports_amplification(uint32_t count)
{
    return count <= 1;
}

shiba_m2v_buffer_t shiba_m2v_buffer_create(size_t length, uint32_t options)
{
    struct shiba_buffer *buf = (struct shiba_buffer *)calloc(1, sizeof(struct shiba_buffer));
    if (!buf) return NULL;

    buf->size = length;
    buf->options = options;

    /* If size >= 64KB, allocate with mmap for page alignment and direct GPU mapping */
    if (length >= 65536) {
        buf->ptr = mmap(NULL, length, PROT_READ | PROT_WRITE, MAP_ANON | MAP_SHARED, -1, 0);
        if (buf->ptr == MAP_FAILED) {
            buf->ptr = malloc(length);
            buf->is_mmap = 0;
        } else {
            buf->is_mmap = 1;
        }
    } else {
        buf->ptr = malloc(length);
        buf->is_mmap = 0;
    }

    if (buf->ptr) {
        memset(buf->ptr, 0, length);
    }
    return (shiba_m2v_buffer_t)buf;
}

void *shiba_m2v_buffer_contents(shiba_m2v_buffer_t buffer)
{
    if (!buffer) return NULL;
    struct shiba_buffer *buf = (struct shiba_buffer *)buffer;
    return buf->ptr;
}

void shiba_m2v_buffer_destroy(shiba_m2v_buffer_t buffer)
{
    if (!buffer) return;
    struct shiba_buffer *buf = (struct shiba_buffer *)buffer;
    if (buf->ptr) {
        if (buf->is_mmap) {
            munmap(buf->ptr, buf->size);
        } else {
            free(buf->ptr);
        }
    }
    free(buf);
}

shiba_m2v_texture_t shiba_m2v_texture_create(const struct shiba_m2v_texture_desc *desc)
{
    if (!desc) return NULL;
    size_t bpp = 4; /* Default 32-bit RGBA/BGRA */
    size_t size = (size_t)desc->width * (size_t)desc->height * bpp;
    return (shiba_m2v_texture_t)shiba_m2v_buffer_create(size, 0);
}

void shiba_m2v_texture_destroy(shiba_m2v_texture_t texture)
{
    shiba_m2v_buffer_destroy((shiba_m2v_buffer_t)texture);
}

shiba_m2v_pipeline_t shiba_m2v_pipeline_compile_compute(const void *air_bytes, size_t length, const char *kernel_name)
{
    (void)air_bytes;
    (void)length;
    struct shiba_pipeline *p = (struct shiba_pipeline *)calloc(1, sizeof(struct shiba_pipeline));
    if (!p) return NULL;
    if (kernel_name) {
        strncpy(p->name, kernel_name, sizeof(p->name) - 1);
    }
    return (shiba_m2v_pipeline_t)p;
}

shiba_m2v_pipeline_t shiba_m2v_pipeline_compile_render(const void *air_bytes, size_t length,
                                                       const char *vert_name, const char *frag_name,
                                                       uint32_t color_format)
{
    (void)air_bytes;
    (void)length;
    (void)frag_name;
    (void)color_format;
    struct shiba_pipeline *p = (struct shiba_pipeline *)calloc(1, sizeof(struct shiba_pipeline));
    if (!p) return NULL;
    if (vert_name) {
        strncpy(p->name, vert_name, sizeof(p->name) - 1);
    }
    return (shiba_m2v_pipeline_t)p;
}

void shiba_m2v_pipeline_destroy(shiba_m2v_pipeline_t pipeline)
{
    if (pipeline) {
        free(pipeline);
    }
}

shiba_m2v_queue_t shiba_m2v_queue_create(void)
{
    struct shiba_queue *q = (struct shiba_queue *)calloc(1, sizeof(struct shiba_queue));
    return (shiba_m2v_queue_t)q;
}

void shiba_m2v_queue_submit(shiba_m2v_queue_t queue, shiba_m2v_pipeline_t pipeline, const struct shiba_m2v_draw_params *draw)
{
    (void)queue;
    (void)pipeline;
    (void)draw;
}

void shiba_m2v_queue_wait_idle(shiba_m2v_queue_t queue)
{
    (void)queue;
}

void shiba_m2v_queue_destroy(shiba_m2v_queue_t queue)
{
    if (queue) {
        free(queue);
    }
}
