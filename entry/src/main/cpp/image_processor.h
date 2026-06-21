/**
 * image_processor.h - N-API 暴露的接口声明
 *
 * 将 ImageProcessor 的功能通过 N-API 暴露给 ArkTS 层调用
 */

#ifndef IMAGE_PROCESSOR_NAPI_H
#define IMAGE_PROCESSOR_NAPI_H

#include <napi/native_api.h>

/**
 * N-API: nv21ToRGBA
 * 将 NV21 格式的图像数据转换为 RGBA
 *
 * ArkTS 调用:
 *   nativeModule.nv21ToRGBA(nv21Buffer: ArrayBuffer, width: number, height: number): ArrayBuffer
 */
napi_value NAPI_Nv21ToRGBA(napi_env env, napi_callback_info info);

/**
 * N-API: nv21ToNV12
 * 将 NV21 格式转换为 NV12 格式
 */
napi_value NAPI_Nv21ToNV12(napi_env env, napi_callback_info info);

/**
 * N-API: applyFilter
 * 对 RGBA 图像数据应用滤镜
 *
 * ArkTS 调用:
 *   nativeModule.applyFilter(rgbaBuffer: ArrayBuffer, width: number, height: number, filterType: number, strength: number): void
 */
napi_value NAPI_ApplyFilter(napi_env env, napi_callback_info info);

/**
 * N-API: adjustBrightness
 * 调整图像亮度
 */
napi_value NAPI_AdjustBrightness(napi_env env, napi_callback_info info);

/**
 * N-API: adjustContrast
 * 调整图像对比度
 */
napi_value NAPI_AdjustContrast(napi_env env, napi_callback_info info);

/**
 * N-API: mirrorImage
 * 翻转图像 (水平/垂直)
 */
napi_value NAPI_MirrorImage(napi_env env, napi_callback_info info);

/**
 * N-API: rotateImage
 * 旋转图像
 */
napi_value NAPI_RotateImage(napi_env env, napi_callback_info info);

/**
 * N-API: getProcessorVersion
 * 获取处理器版本信息
 */
napi_value NAPI_GetProcessorVersion(napi_env env, napi_callback_info info);

#endif // IMAGE_PROCESSOR_NAPI_H
