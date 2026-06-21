/**
 * napi_init.cpp - N-API 模块初始化入口
 *
 * 注册所有原生方法到 ArkTS 可调用的模块对象
 */

#include <napi/native_api.h>
#include <hilog/log.h>
#include "image_processor.h"
#include "camera_native.h"

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3200
#define LOG_TAG "UnifiedCamera-Init"

/**
 * N-API 模块注册表
 * 定义 ArkTS 可调用的所有函数
 */
static napi_property_descriptor g_moduleExports[] = {
    // 格式转换
    {
        .utf8name = "nv21ToRGBA",
        .name = nullptr,
        .method = NAPI_Nv21ToRGBA,
        .getter = nullptr,
        .setter = nullptr,
        .value = nullptr,
        .attributes = napi_default,
        .data = nullptr
    },
    {
        .utf8name = "nv21ToNV12",
        .name = nullptr,
        .method = NAPI_Nv21ToNV12,
        .getter = nullptr,
        .setter = nullptr,
        .value = nullptr,
        .attributes = napi_default,
        .data = nullptr
    },
    // 滤镜
    {
        .utf8name = "applyFilter",
        .name = nullptr,
        .method = NAPI_ApplyFilter,
        .getter = nullptr,
        .setter = nullptr,
        .value = nullptr,
        .attributes = napi_default,
        .data = nullptr
    },
    // 亮度/对比度
    {
        .utf8name = "adjustBrightness",
        .name = nullptr,
        .method = NAPI_AdjustBrightness,
        .getter = nullptr,
        .setter = nullptr,
        .value = nullptr,
        .attributes = napi_default,
        .data = nullptr
    },
    {
        .utf8name = "adjustContrast",
        .name = nullptr,
        .method = NAPI_AdjustContrast,
        .getter = nullptr,
        .setter = nullptr,
        .value = nullptr,
        .attributes = napi_default,
        .data = nullptr
    },
    // 变换
    {
        .utf8name = "mirrorImage",
        .name = nullptr,
        .method = NAPI_MirrorImage,
        .getter = nullptr,
        .setter = nullptr,
        .value = nullptr,
        .attributes = napi_default,
        .data = nullptr
    },
    {
        .utf8name = "rotateImage",
        .name = nullptr,
        .method = NAPI_RotateImage,
        .getter = nullptr,
        .setter = nullptr,
        .value = nullptr,
        .attributes = napi_default,
        .data = nullptr
    },
    // 工具
    {
        .utf8name = "getProcessorVersion",
        .name = nullptr,
        .method = NAPI_GetProcessorVersion,
        .getter = nullptr,
        .setter = nullptr,
        .value = nullptr,
        .attributes = napi_default,
        .data = nullptr
    },
};

/**
 * 模块初始化回调
 * 当 ArkTS 层执行 `import nativeModule from 'libcamera_native.so'` 时调用
 *
 * @param env        N-API 环境句柄
 * @param exports    导出对象（待填充）
 * @return           导出对象
 */
static napi_value CameraNativeModuleInit(napi_env env, napi_value exports) {
    OH_LOG_INFO(LOG_APP, "================================================");
    OH_LOG_INFO(LOG_APP, "UnifiedCamera Native Module 初始化中...");
    OH_LOG_INFO(LOG_APP, "架构: %{public}s",
#ifdef __aarch64__
                "ARM64 (NEON 加速已启用)"
#else
                "Generic"
#endif
    );
    OH_LOG_INFO(LOG_APP, "================================================");

    // 注册所有函数到模块导出对象
    napi_status status = napi_define_properties(
        env,
        exports,
        sizeof(g_moduleExports) / sizeof(g_moduleExports[0]),
        g_moduleExports
    );

    if (status != napi_ok) {
        OH_LOG_ERROR(LOG_APP, "模块注册失败! status=%{public}d", status);
        return exports;
    }

    OH_LOG_INFO(LOG_APP, "模块注册成功: %{public}zu 个函数已导出",
                sizeof(g_moduleExports) / sizeof(g_moduleExports[0]));

    return exports;
}

/**
 * N-API 模块定义
 *
 * nm_modname: 模块名，ArkTS 层 import 时使用
 * nm_register_func: 模块初始化回调
 */
static napi_module g_cameraNativeModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = CameraNativeModuleInit,
    .nm_modname = "camera_native",
    .nm_priv = nullptr,
    .reserved = { 0 }
};

/**
 * 模块自动注册入口
 * 动态库加载时由 N-API 运行时自动调用
 */
extern "C" __attribute__((constructor)) void RegisterCameraNativeModule(void) {
    napi_module_register(&g_cameraNativeModule);
    OH_LOG_INFO(LOG_APP, "camera_native 模块已注册 (constructor)");
}
