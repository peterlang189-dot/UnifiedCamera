/**
 * image_processor.cpp - N-API 接口实现
 *
 * 提供 ArkTS ↔ C++ 的桥接层，处理参数解析和类型转换
 */

#include "image_processor.h"
#include "camera_native.h"
#include <hilog/log.h>
#include <cstring>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3200
#define LOG_TAG "UnifiedCamera-NAPI"

using namespace UnifiedCamera;

// ============================================================
// 辅助宏和工具函数
// ============================================================

/**
 * 从 ArrayBuffer 获取原始指针
 */
static inline uint8_t* GetBufferData(napi_env env, napi_value buffer, size_t* outSize = nullptr) {
    void* data = nullptr;
    size_t length = 0;
    napi_get_arraybuffer_info(env, buffer, &data, &length);
    if (outSize) *outSize = length;
    return static_cast<uint8_t*>(data);
}

/**
 * 创建 ArrayBuffer 并复制数据
 */
static napi_value CreateArrayBuffer(napi_env env, const uint8_t* data, size_t size) {
    void* bufferData = nullptr;
    napi_value result;
    napi_create_arraybuffer(env, size, &bufferData, &result);
    if (bufferData && data) {
        std::memcpy(bufferData, data, size);
    }
    return result;
}

// ============================================================
// N-API: nv21ToRGBA
// ============================================================

napi_value NAPI_Nv21ToRGBA(napi_env env, napi_callback_info info) {
    OH_LOG_INFO(LOG_APP, "[NAPI] nv21ToRGBA called");

    // 获取参数
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 3) {
        OH_LOG_ERROR(LOG_APP, "[NAPI] nv21ToRGBA: 参数不足! 需要 (buffer, width, height)");
        napi_throw_error(env, nullptr, "Need 3 arguments: (buffer, width, height)");
        return nullptr;
    }

    // 解析参数
    size_t nv21Size = 0;
    uint8_t* nv21Data = GetBufferData(env, args[0], &nv21Size);

    uint32_t width = 0, height = 0;
    napi_get_value_uint32(env, args[1], &width);
    napi_get_value_uint32(env, args[2], &height);

    if (!nv21Data || width == 0 || height == 0) {
        napi_throw_error(env, nullptr, "Invalid arguments");
        return nullptr;
    }

    // 分配输出缓冲区 (RGBA = 4 bytes per pixel)
    const size_t rgbaSize = width * height * 4;
    std::vector<uint8_t> rgbaBuffer(rgbaSize);

    // 调用原生转换
    ImageProcessor::nv21ToRGBA(nv21Data, rgbaBuffer.data(), width, height);

    OH_LOG_INFO(LOG_APP, "[NAPI] nv21ToRGBA: %{public}dx%{public}d, NV21=%{public}zu bytes → RGBA=%{public}zu bytes",
                width, height, nv21Size, rgbaSize);

    return CreateArrayBuffer(env, rgbaBuffer.data(), rgbaSize);
}

// ============================================================
// N-API: nv21ToNV12
// ============================================================

napi_value NAPI_Nv21ToNV12(napi_env env, napi_callback_info info) {
    OH_LOG_INFO(LOG_APP, "[NAPI] nv21ToNV12 called");

    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 3) {
        napi_throw_error(env, nullptr, "Need 3 arguments: (buffer, width, height)");
        return nullptr;
    }

    size_t nv21Size = 0;
    uint8_t* nv21Data = GetBufferData(env, args[0], &nv21Size);

    uint32_t width = 0, height = 0;
    napi_get_value_uint32(env, args[1], &width);
    napi_get_value_uint32(env, args[2], &height);

    if (!nv21Data || width == 0 || height == 0) {
        napi_throw_error(env, nullptr, "Invalid arguments");
        return nullptr;
    }

    const size_t nv12Size = width * height * 3 / 2;
    std::vector<uint8_t> nv12Buffer(nv12Size);

    ImageProcessor::nv21ToNV12(nv21Data, nv12Buffer.data(), width, height);

    return CreateArrayBuffer(env, nv12Buffer.data(), nv12Size);
}

// ============================================================
// N-API: applyFilter
// ============================================================

napi_value NAPI_ApplyFilter(napi_env env, napi_callback_info info) {
    OH_LOG_INFO(LOG_APP, "[NAPI] applyFilter called");

    size_t argc = 5;
    napi_value args[5] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 4) {
        napi_throw_error(env, nullptr, "Need at least 4 arguments: (rgbaBuffer, width, height, filterType, [strength])");
        return nullptr;
    }

    uint8_t* rgbaData = GetBufferData(env, args[0]);

    uint32_t width = 0, height = 0;
    napi_get_value_uint32(env, args[1], &width);
    napi_get_value_uint32(env, args[2], &height);

    int32_t filterType = 0;
    napi_get_value_int32(env, args[3], &filterType);

    double strength = 0.5;
    if (argc >= 5) {
        napi_get_value_double(env, args[4], &strength);
    }

    if (!rgbaData || width == 0 || height == 0) {
        napi_throw_error(env, nullptr, "Invalid arguments");
        return nullptr;
    }

    // 原地修改
    ImageProcessor::applyFilter(
        rgbaData,
        width,
        height,
        static_cast<FilterType>(filterType),
        static_cast<float>(strength)
    );

    OH_LOG_INFO(LOG_APP, "[NAPI] applyFilter: filter=%{public}d, strength=%.2f, %{public}dx%{public}d",
                filterType, strength, width, height);

    // 原地修改已生效，返回 undefined
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ============================================================
// N-API: adjustBrightness
// ============================================================

napi_value NAPI_AdjustBrightness(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 3) {
        napi_throw_error(env, nullptr, "Need 3 arguments: (buffer, pixelCount, factor)");
        return nullptr;
    }

    uint8_t* rgbaData = GetBufferData(env, args[0]);

    uint32_t pixelCount = 0;
    napi_get_value_uint32(env, args[1], &pixelCount);

    double factor = 0.0;
    napi_get_value_double(env, args[2], &factor);

    if (!rgbaData) {
        napi_throw_error(env, nullptr, "Invalid buffer");
        return nullptr;
    }

    ImageProcessor::adjustBrightness(rgbaData, pixelCount, static_cast<float>(factor));

    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ============================================================
// N-API: adjustContrast
// ============================================================

napi_value NAPI_AdjustContrast(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 3) {
        napi_throw_error(env, nullptr, "Need 3 arguments: (buffer, pixelCount, factor)");
        return nullptr;
    }

    uint8_t* rgbaData = GetBufferData(env, args[0]);

    uint32_t pixelCount = 0;
    napi_get_value_uint32(env, args[1], &pixelCount);

    double factor = 1.0;
    napi_get_value_double(env, args[2], &factor);

    if (!rgbaData) {
        napi_throw_error(env, nullptr, "Invalid buffer");
        return nullptr;
    }

    ImageProcessor::adjustContrast(rgbaData, pixelCount, static_cast<float>(factor));

    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ============================================================
// N-API: mirrorImage
// ============================================================

napi_value NAPI_MirrorImage(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 4) {
        napi_throw_error(env, nullptr, "Need 4 arguments: (buffer, width, height, direction)");
        return nullptr;
    }

    uint8_t* rgbaData = GetBufferData(env, args[0]);

    uint32_t width = 0, height = 0;
    napi_get_value_uint32(env, args[1], &width);
    napi_get_value_uint32(env, args[2], &height);

    int32_t direction = 0;  // 0=水平, 1=垂直
    napi_get_value_int32(env, args[3], &direction);

    if (!rgbaData || width == 0 || height == 0) {
        napi_throw_error(env, nullptr, "Invalid arguments");
        return nullptr;
    }

    if (direction == 0) {
        ImageProcessor::mirrorHorizontal(rgbaData, width, height);
    } else {
        ImageProcessor::mirrorVertical(rgbaData, width, height);
    }

    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ============================================================
// N-API: rotateImage
// ============================================================

napi_value NAPI_RotateImage(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 4) {
        napi_throw_error(env, nullptr, "Need 4 arguments: (buffer, width, height, angle)");
        return nullptr;
    }

    uint8_t* rgbaData = GetBufferData(env, args[0]);

    uint32_t width = 0, height = 0;
    napi_get_value_uint32(env, args[1], &width);
    napi_get_value_uint32(env, args[2], &height);

    int32_t angle = 0;
    napi_get_value_int32(env, args[3], &angle);

    if (!rgbaData || width == 0 || height == 0) {
        napi_throw_error(env, nullptr, "Invalid arguments");
        return nullptr;
    }

    // 旋转后尺寸可能变化 (90/270 度时宽高交换)
    uint32_t newWidth = width;
    uint32_t newHeight = height;
    if (angle == 90 || angle == 270) {
        newWidth = height;
        newHeight = width;
    }
    const size_t newSize = newWidth * newHeight * 4;
    std::vector<uint8_t> rotatedBuffer(newSize);

    ImageProcessor::rotateImage(rgbaData, rotatedBuffer.data(), width, height, angle);

    return CreateArrayBuffer(env, rotatedBuffer.data(), newSize);
}

// ============================================================
// N-API: getProcessorVersion
// ============================================================

napi_value NAPI_GetProcessorVersion(napi_env env, napi_callback_info info) {
    napi_value result;
    const char* version = "UnifiedCamera ImageProcessor v1.0.0 - NEON Enabled";
    napi_create_string_utf8(env, version, NAPI_AUTO_LENGTH, &result);
    return result;
}
