/*
 * ShibaMetal: Native Darwin Metal Driver backed by Metal2Vulkan
 *
 * Implements Apple's Metal plugin driver interface for Google Pixel 8 (Tensor G3 / Mali-G715).
 * Bridges Metal API calls directly to Vulkan via metal2vulkan.
 */

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <IOKit/IOKitLib.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>
#include <unistd.h>

#include "shiba_metal.h"

#define LOG_TAG "shiba_metal"

static void
shiba_log(const char *format, ...)
{
    char buf[512];
    va_list ap;
    va_start(ap, format);
    vsnprintf(buf, sizeof(buf), format, ap);
    va_end(ap);
    fprintf(stderr, "[%s:%d] %s\n", LOG_TAG, getpid(), buf);
}

/* Base class _MTLDevice imported dynamically */
@interface _MTLDevice : NSObject
@end

@protocol MTLDeviceSPI <NSObject>
@end

/*
 * ShibaMetalBuffer
 */
@interface ShibaMetalBuffer : NSObject {
@public
    shiba_m2v_buffer_t _backend_buf;
    void *_contents;
    NSUInteger _length;
}
- (void *)contents;
- (NSUInteger)length;
@end

@implementation ShibaMetalBuffer
- (instancetype)initWithLength:(NSUInteger)length options:(NSUInteger)options {
    self = [super init];
    if (self) {
        _length = length;
        _backend_buf = shiba_m2v_buffer_create(length, (uint32_t)options);
        if (_backend_buf) {
            _contents = shiba_m2v_buffer_contents(_backend_buf);
        } else {
            /* Fallback to anonymous shared memory if Vulkan allocator is unavailable */
            _contents = malloc(length);
            if (_contents) memset(_contents, 0, length);
        }
    }
    return self;
}

- (void *)contents {
    return _contents;
}

- (NSUInteger)length {
    return _length;
}

- (void)dealloc {
    if (_backend_buf) {
        shiba_m2v_buffer_destroy(_backend_buf);
        _backend_buf = NULL;
    } else if (_contents) {
        free(_contents);
        _contents = NULL;
    }
    [super dealloc];
}
@end

/*
 * ShibaMetalCommandQueue
 */
@interface ShibaMetalCommandQueue : NSObject {
@public
    shiba_m2v_queue_t _queue;
}
- (id)commandBuffer;
@end

@implementation ShibaMetalCommandQueue
- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = shiba_m2v_queue_create();
    }
    return self;
}

- (id)commandBuffer {
    /* Returns a basic autoreleased command buffer handle */
    return self;
}

- (void)commit {
    if (_queue) {
        shiba_m2v_queue_submit(_queue, NULL, NULL);
    }
}

- (void)waitUntilCompleted {
    if (_queue) {
        shiba_m2v_queue_wait_idle(_queue);
    }
}

- (void)dealloc {
    if (_queue) {
        shiba_m2v_queue_destroy(_queue);
        _queue = NULL;
    }
    [super dealloc];
}
@end

/*
 * ShibaMetalDevice
 */
@interface ShibaMetalDevice : _MTLDevice <MTLDeviceSPI> {
@public
    io_service_t _acceleratorPort;
    shiba_m2v_device_t _vkDevice;
}
- (id)initWithAcceleratorPort:(io_service_t)port;
- (NSUInteger)featureProfile;
- (uint64_t)maxBufferLength;
- (BOOL)supportsVertexAmplificationCount:(NSUInteger)count;
- (NSString *)name;
- (id)newBufferWithLength:(NSUInteger)length options:(NSUInteger)options;
- (id)newCommandQueue;
@end

@implementation ShibaMetalDevice

- (id)initWithAcceleratorPort:(io_service_t)port {
    self = [super init];
    if (self) {
        _acceleratorPort = port;
        shiba_log("Initializing ShibaMetalDevice with accelerator port %u (Mali-G715 / Vulkan)", (unsigned)port);

        /* Initialize the metal2vulkan runtime context */
        const char *profile = "/shiba/config/mali_g715_profile.json";
        if (access(profile, R_OK) != 0) {
            profile = "/etc/mali_g715_profile.json";
        }
        shiba_m2v_init(profile);
        _vkDevice = shiba_m2v_get_device();
        shiba_log("ShibaMetal: Vulkan device initialized (%p)", _vkDevice);
    }
    return self;
}

- (NSUInteger)featureProfile {
    /* Feature profile 2 = Apple Metal GPU Family Apple 4 / A11 / iOS 16.5 baseline */
    return 2;
}

- (uint64_t)maxBufferLength {
    return SHIBA_METAL_MAX_BUFFER_LENGTH;
}

- (BOOL)supportsVertexAmplificationCount:(NSUInteger)count {
    return count <= 1;
}

- (NSString *)name {
    return @"Google Tensor G3 (ARM Mali-G715 Immortalis / Vulkan 1.3)";
}

- (id)newBufferWithLength:(NSUInteger)length options:(NSUInteger)options {
    return [[[ShibaMetalBuffer alloc] initWithLength:length options:options] autorelease];
}

- (id)newCommandQueue {
    return [[[ShibaMetalCommandQueue alloc] init] autorelease];
}

- (BOOL)supportsFamily:(NSUInteger)family {
    /* MTLGPUFamilyApple4 (A11), MTLGPUFamilyCommon3 */
    if (family == 1004 || family == 3003) {
        return YES;
    }
    return NO;
}

@end

/*
 * Plugin entry point called by Metal.framework:
 * Loads the bundle and returns the principal class.
 */
__attribute__((constructor))
static void
shiba_metal_driver_init(void)
{
    shiba_log("ShibaMetal driver loaded into %s (PID %d)", getprogname() ? getprogname() : "unknown", getpid());
}
