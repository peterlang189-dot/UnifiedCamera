/**
 * camera_native.cpp - 原生图像处理模块实现
 *
 * 实现 N-API 暴露给 ArkTS 的接口，以及内部图像处理逻辑。
 * ARM64 平台使用 NEON SIMD 加速 YUV→RGB 转换。
 */

#include "camera_native.h"
#include <hilog/log.h>
#include <cstring>
#include <algorithm>
#include <cmath>

// 日志 Domain
#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3200
#define LOG_TAG "UnifiedCamera-Native"

namespace UnifiedCamera {

// ============================================================
// ImageProcessor 实现
// ============================================================

ImageProcessor::ImageProcessor() {
    OH_LOG_INFO(LOG_APP, "[ImageProcessor] 已创建, NEON=%{public}s",
#ifdef __ARM_NEON
                "ON"
#else
                "OFF"
#endif
    );
}

ImageProcessor::~ImageProcessor() {
    OH_LOG_INFO(LOG_APP, "[ImageProcessor] 已销毁");
}

// ----- NV21 → RGBA 转换 (标量版本) -----

void ImageProcessor::nv21ToRGBA(const uint8_t* nv21Data,
                                 uint8_t* rgbaOutput,
                                 uint32_t width,
                                 uint32_t height,
                                 int32_t rotation,
                                 bool flipHorizontal) {
    if (!nv21Data || !rgbaOutput || width == 0 || height == 0) {
        OH_LOG_ERROR(LOG_APP, "[ImageProcessor] nv21ToRGBA: 参数无效!");
        return;
    }

#ifdef __ARM_NEON
    // 尝试使用 NEON 加速路径
    if (rotation == 0 && !flipHorizontal) {
        nv21ToRGBA_NEON(nv21Data, rgbaOutput, width, height);
        return;
    }
#endif

    const uint32_t frameSize = width * height;
    const uint8_t* yPlane = nv21Data;
    const uint8_t* uvPlane = nv21Data + frameSize;

    for (uint32_t y = 0; y < height; y++) {
        for (uint32_t x = 0; x < width; x++) {
            uint32_t srcX = x;
            uint32_t srcY = y;

            // 应用水平翻转
            if (flipHorizontal) {
                srcX = width - 1 - x;
            }

            const uint32_t yIndex = srcY * width + srcX;
            const uint32_t uvIndex = (srcY / 2) * width + (srcX & ~1);

            // YUV → RGB (BT.601 limited range)
            const float Y = static_cast<float>(yPlane[yIndex]) - 16.0f;
            const float U = static_cast<float>(uvPlane[uvIndex]) - 128.0f;
            const float V = static_cast<float>(uvPlane[uvIndex + 1]) - 128.0f;

            // 计算 RGB
            float R = (Y * 1.164f + V * YUV_TO_RGB_R_V);
            float G = (Y * 1.164f + U * YUV_TO_RGB_G_U + V * YUV_TO_RGB_G_V);
            float B = (Y * 1.164f + U * YUV_TO_RGB_B_U);

            // Clamp 到 [0, 255]
            const uint32_t outIndex = (y * width + x) * 4;
            rgbaOutput[outIndex + 0] = static_cast<uint8_t>(std::max(0.0f, std::min(255.0f, R)));
            rgbaOutput[outIndex + 1] = static_cast<uint8_t>(std::max(0.0f, std::min(255.0f, G)));
            rgbaOutput[outIndex + 2] = static_cast<uint8_t>(std::max(0.0f, std::min(255.0f, B)));
            rgbaOutput[outIndex + 3] = 255; // Alpha
        }
    }
}

// ----- NV21 → NV12 转换 -----

void ImageProcessor::nv21ToNV12(const uint8_t* nv21Data,
                                 uint8_t* nv12Output,
                                 uint32_t width,
                                 uint32_t height) {
    if (!nv21Data || !nv12Output) return;

    const uint32_t frameSize = width * height;
    const uint32_t uvSize = frameSize / 2;

    // 复制 Y 平面
    std::memcpy(nv12Output, nv21Data, frameSize);

    // 交换 UV 分量: NV21 (VU VU...) → NV12 (UV UV...)
    const uint8_t* uvSrc = nv21Data + frameSize;
    uint8_t* uvDst = nv12Output + frameSize;

    for (uint32_t i = 0; i < uvSize; i += 2) {
        uvDst[i] = uvSrc[i + 1];       // U ← V
        uvDst[i + 1] = uvSrc[i];       // V ← U
    }
}

// ----- RGBA → JPEG 编码 (占位实现，实际使用 Image Kit) -----

bool ImageProcessor::rgbaToJPEG(const uint8_t* rgbaData,
                                 uint32_t width,
                                 uint32_t height,
                                 int32_t quality,
                                 uint8_t* jpegOutput,
                                 size_t* jpegSize) {
    // JPEG 编码需要通过 OH_ImagePacker 实现
    // 此处为占位代码，实际编码在 ArkTS 层完成
    OH_LOG_WARN(LOG_APP, "[ImageProcessor] rgbaToJPEG: 请使用 ArkTS 层的 ImagePacker 进行编码");
    if (jpegSize) *jpegSize = 0;
    return false;
}

// ============================================================
// 独立滤镜方法（从 applyFilter 拆分，每个方法只做一件事）
// ============================================================

void ImageProcessor::applyGrayscale(uint8_t* rgbaData, uint32_t pixelCount) {
    for (uint32_t i = 0; i < pixelCount; i++) {
        const uint32_t idx = i * 4;
        const uint8_t gray = static_cast<uint8_t>(
            rgbaData[idx] * 0.299f +
            rgbaData[idx + 1] * 0.587f +
            rgbaData[idx + 2] * 0.114f
        );
        rgbaData[idx] = rgbaData[idx + 1] = rgbaData[idx + 2] = gray;
    }
}

void ImageProcessor::applySepia(uint8_t* rgbaData, uint32_t pixelCount) {
    for (uint32_t i = 0; i < pixelCount; i++) {
        const uint32_t idx = i * 4;
        const float gray = rgbaData[idx] * 0.299f +
                           rgbaData[idx + 1] * 0.587f +
                           rgbaData[idx + 2] * 0.114f;
        rgbaData[idx] = static_cast<uint8_t>(std::min(255.0f, gray * 1.2f));
        rgbaData[idx + 1] = static_cast<uint8_t>(std::min(255.0f, gray * 0.9f));
        rgbaData[idx + 2] = static_cast<uint8_t>(std::min(255.0f, gray * 0.7f));
    }
}

void ImageProcessor::applyNegative(uint8_t* rgbaData, uint32_t pixelCount) {
    for (uint32_t i = 0; i < pixelCount; i++) {
        const uint32_t idx = i * 4;
        rgbaData[idx] = 255 - rgbaData[idx];
        rgbaData[idx + 1] = 255 - rgbaData[idx + 1];
        rgbaData[idx + 2] = 255 - rgbaData[idx + 2];
    }
}

void ImageProcessor::applyBlur(uint8_t* rgbaData, uint32_t width, uint32_t height) {
    const int32_t w = static_cast<int32_t>(width);
    const int32_t h = static_cast<int32_t>(height);
    std::vector<uint8_t> temp(w * h * 4);
    std::memcpy(temp.data(), rgbaData, w * h * 4);

    for (int32_t y = 1; y < h - 1; y++) {
        for (int32_t x = 1; x < w - 1; x++) {
            for (int32_t c = 0; c < 3; c++) {
                int32_t sum = 0;
                for (int32_t dy = -1; dy <= 1; dy++) {
                    for (int32_t dx = -1; dx <= 1; dx++) {
                        sum += temp[((y + dy) * w + (x + dx)) * 4 + c];
                    }
                }
                rgbaData[(y * w + x) * 4 + c] = static_cast<uint8_t>(sum / 9);
            }
        }
    }
}

void ImageProcessor::applySharpen(uint8_t* rgbaData, uint32_t width, uint32_t height) {
    const int32_t w = static_cast<int32_t>(width);
    const int32_t h = static_cast<int32_t>(height);
    std::vector<uint8_t> temp(w * h * 4);
    std::memcpy(temp.data(), rgbaData, w * h * 4);

    const int32_t kernel[3][3] = {
        { 0, -1,  0},
        {-1,  5, -1},
        { 0, -1,  0}
    };

    for (int32_t y = 1; y < h - 1; y++) {
        for (int32_t x = 1; x < w - 1; x++) {
            for (int32_t c = 0; c < 3; c++) {
                int32_t sum = 0;
                for (int32_t dy = -1; dy <= 1; dy++) {
                    for (int32_t dx = -1; dx <= 1; dx++) {
                        sum += temp[((y + dy) * w + (x + dx)) * 4 + c]
                             * kernel[dy + 1][dx + 1];
                    }
                }
                rgbaData[(y * w + x) * 4 + c] =
                    static_cast<uint8_t>(std::max(0, std::min(255, sum)));
            }
        }
    }
}

// ----- 滤镜分发表 -----

ImageProcessor::FilterFunc ImageProcessor::getFilterFunc(FilterType filter) {
    switch (filter) {
        case FilterType::GRAYSCALE:  return nullptr; // 特殊处理: 使用 applyGrayscale(pixelCount)
        case FilterType::SEPIA:      return nullptr; // 特殊处理: 使用 applySepia(pixelCount)
        case FilterType::MIRROR:     return nullptr; // 特殊处理: 使用 mirrorHorizontal
        case FilterType::NEGATIVE:   return nullptr; // 特殊处理: 使用 applyNegative(pixelCount)
        case FilterType::BRIGHTNESS: return nullptr; // 特殊处理: 使用 adjustBrightness + strength
        case FilterType::CONTRAST:   return nullptr; // 特殊处理: 使用 adjustContrast + strength
        case FilterType::BLUR:       return nullptr; // 特殊处理: 需要 width + height
        case FilterType::SHARPEN:    return nullptr; // 特殊处理: 需要 width + height
        default:                     return nullptr;
    }
}

// ----- 统一滤镜入口（重构后：轻量级分发） -----

void ImageProcessor::applyFilter(uint8_t* rgbaData,
                                  uint32_t width,
                                  uint32_t height,
                                  FilterType filter,
                                  float strength) {
    if (!rgbaData) return;

    const uint32_t pixelCount = width * height;

    switch (filter) {
        case FilterType::GRAYSCALE:
            applyGrayscale(rgbaData, pixelCount);
            break;

        case FilterType::SEPIA:
            applySepia(rgbaData, pixelCount);
            break;

        case FilterType::MIRROR:
            mirrorHorizontal(rgbaData, width, height);
            break;

        case FilterType::NEGATIVE:
            applyNegative(rgbaData, pixelCount);
            break;

        case FilterType::BRIGHTNESS:
            adjustBrightness(rgbaData, pixelCount, (strength - 0.5f) * 2.0f);
            break;

        case FilterType::CONTRAST:
            adjustContrast(rgbaData, pixelCount, strength * 2.0f);
            break;

        case FilterType::BLUR:
            applyBlur(rgbaData, width, height);
            break;

        case FilterType::SHARPEN:
            applySharpen(rgbaData, width, height);
            break;

        default:
            break;
    }
}

// ----- 亮度调整 -----

void ImageProcessor::adjustBrightness(uint8_t* rgbaData,
                                       uint32_t pixelCount,
                                       float factor) {
    uint8_t lut[256];
    buildBrightnessLUT(lut, factor);

    for (uint32_t i = 0; i < pixelCount; i++) {
        const uint32_t idx = i * 4;
        rgbaData[idx] = lut[rgbaData[idx]];
        rgbaData[idx + 1] = lut[rgbaData[idx + 1]];
        rgbaData[idx + 2] = lut[rgbaData[idx + 2]];
    }
}

// ----- 对比度调整 -----

void ImageProcessor::adjustContrast(uint8_t* rgbaData,
                                     uint32_t pixelCount,
                                     float factor) {
    uint8_t lut[256];
    buildContrastLUT(lut, factor);

    for (uint32_t i = 0; i < pixelCount; i++) {
        const uint32_t idx = i * 4;
        rgbaData[idx] = lut[rgbaData[idx]];
        rgbaData[idx + 1] = lut[rgbaData[idx + 1]];
        rgbaData[idx + 2] = lut[rgbaData[idx + 2]];
    }
}

// ----- 水平翻转 -----

void ImageProcessor::mirrorHorizontal(uint8_t* rgbaData,
                                       uint32_t width,
                                       uint32_t height) {
    const uint32_t rowBytes = width * 4;
    std::vector<uint8_t> row(rowBytes);

    for (uint32_t y = 0; y < height; y++) {
        uint8_t* rowStart = rgbaData + y * rowBytes;
        std::memcpy(row.data(), rowStart, rowBytes);

        for (uint32_t x = 0; x < width; x++) {
            const uint32_t srcIdx = (width - 1 - x) * 4;
            const uint32_t dstIdx = x * 4;
            rowStart[dstIdx] = row[srcIdx];
            rowStart[dstIdx + 1] = row[srcIdx + 1];
            rowStart[dstIdx + 2] = row[srcIdx + 2];
            rowStart[dstIdx + 3] = row[srcIdx + 3];
        }
    }
}

// ----- 垂直翻转 -----

void ImageProcessor::mirrorVertical(uint8_t* rgbaData,
                                     uint32_t width,
                                     uint32_t height) {
    const uint32_t rowBytes = width * 4;
    std::vector<uint8_t> row(rowBytes);

    for (uint32_t y = 0; y < height / 2; y++) {
        uint8_t* topRow = rgbaData + y * rowBytes;
        uint8_t* bottomRow = rgbaData + (height - 1 - y) * rowBytes;

        std::memcpy(row.data(), topRow, rowBytes);
        std::memcpy(topRow, bottomRow, rowBytes);
        std::memcpy(bottomRow, row.data(), rowBytes);
    }
}

// ----- 图像旋转 -----

void ImageProcessor::rotateImage(const uint8_t* src,
                                  uint8_t* dst,
                                  uint32_t width,
                                  uint32_t height,
                                  int32_t rotation) {
    if (!src || !dst) return;

    rotation = ((rotation % 360) + 360) % 360;  // 归一化

    switch (rotation) {
        case 90: {
            for (uint32_t y = 0; y < height; y++) {
                for (uint32_t x = 0; x < width; x++) {
                    const uint32_t srcIdx = (y * width + x) * 4;
                    const uint32_t dstIdx = ((x * height) + (height - 1 - y)) * 4;
                    std::memcpy(dst + dstIdx, src + srcIdx, 4);
                }
            }
            break;
        }

        case 180: {
            const uint32_t totalPixels = width * height;
            for (uint32_t i = 0; i < totalPixels; i++) {
                const uint32_t srcIdx = i * 4;
                const uint32_t dstIdx = (totalPixels - 1 - i) * 4;
                std::memcpy(dst + dstIdx, src + srcIdx, 4);
            }
            break;
        }

        case 270: {
            for (uint32_t y = 0; y < height; y++) {
                for (uint32_t x = 0; x < width; x++) {
                    const uint32_t srcIdx = (y * width + x) * 4;
                    const uint32_t dstIdx = ((width - 1 - x) * height + y) * 4;
                    std::memcpy(dst + dstIdx, src + srcIdx, 4);
                }
            }
            break;
        }

        default:
            // 0度或其他角度 → 直接复制
            std::memcpy(dst, src, width * height * 4);
            break;
    }
}

// ----- LUT 生成 -----

void ImageProcessor::buildBrightnessLUT(uint8_t* lut, float factor) {
    for (int32_t i = 0; i < 256; i++) {
        float val = static_cast<float>(i) + factor * 128.0f;
        lut[i] = static_cast<uint8_t>(std::max(0.0f, std::min(255.0f, val)));
    }
}

void ImageProcessor::buildContrastLUT(uint8_t* lut, float factor) {
    for (int32_t i = 0; i < 256; i++) {
        float val = (static_cast<float>(i) - 128.0f) * factor + 128.0f;
        lut[i] = static_cast<uint8_t>(std::max(0.0f, std::min(255.0f, val)));
    }
}

#ifdef __ARM_NEON
// ============================================================
// NEON 加速 NV21 → RGBA 转换 (完整实现)
// ============================================================
#include <arm_neon.h>

void ImageProcessor::nv21ToRGBA_NEON(const uint8_t* nv21Data,
                                      uint8_t* rgbaOutput,
                                      uint32_t width,
                                      uint32_t height) {
    const uint32_t frameSize = width * height;
    const uint8_t* yPlane = nv21Data;
    const uint8_t* uvPlane = nv21Data + frameSize;

    // BT.601 转换常量
    const float32x4_t yScale = vdupq_n_f32(1.164f);
    const float32x4_t rvCoeff = vdupq_n_f32(1.402f);
    const float32x4_t guCoeff = vdupq_n_f32(-0.34414f);
    const float32x4_t gvCoeff = vdupq_n_f32(-0.71414f);
    const float32x4_t buCoeff = vdupq_n_f32(1.772f);
    const float32x4_t c16 = vdupq_n_f32(16.0f);
    const float32x4_t c128 = vdupq_n_f32(128.0f);
    const float32x4_t c0 = vdupq_n_f32(0.0f);
    const float32x4_t c255 = vdupq_n_f32(255.0f);

    // 处理 8 像素对齐的部分
    const uint32_t alignedWidth = width & ~7u;

    for (uint32_t y = 0; y < height; y++) {
        const uint32_t uvRowOffset = frameSize + (y / 2) * width;

        // ---- NEON 8-pixel 主循环 ----
        uint32_t x = 0;
        for (; x < alignedWidth; x += 8) {
            // 1. 加载 8 个 Y 值并转为 float32
            uint8x8_t y8 = vld1_u8(yPlane + y * width + x);
            uint16x8_t y16 = vmovl_u8(y8);
            uint32x4_t y32_low = vmovl_u16(vget_low_u16(y16));
            uint32x4_t y32_high = vmovl_u16(vget_high_u16(y16));
            float32x4_t yf_low = vcvtq_f32_u32(y32_low);
            float32x4_t yf_high = vcvtq_f32_u32(y32_high);

            // Y' = (Y - 16) * 1.164
            yf_low = vmulq_f32(vsubq_f32(yf_low, c16), yScale);
            yf_high = vmulq_f32(vsubq_f32(yf_high, c16), yScale);

            // 2. 加载 4 组 UV 并扩展到 8 像素
            // UV 布局 (NV21): V0,U0,V1,U1,V2,U2,V3,U3 (覆盖 8 个水平像素)
            uint8x8_t uv8 = vld1_u8(uvPlane + uvRowOffset + (x & ~1u));

            // 提取并复制每个 U/V 覆盖 2 个水平像素:
            // V 扩展: 索引 {0,0,2,2,4,4,6,6}
            const uint8x8_t vTblIdx = vcreate_u8(UINT64_C(0x0606040402020000));
            uint8x8_t vExpanded = vtbl1_u8(uv8, vTblIdx);

            // U 扩展: 索引 {1,1,3,3,5,5,7,7}
            const uint8x8_t uTblIdx = vcreate_u8(UINT64_C(0x0707050503030101));
            uint8x8_t uExpanded = vtbl1_u8(uv8, uTblIdx);

            // 3. U/V 转为 float32
            uint16x8_t v16 = vmovl_u8(vExpanded);
            uint16x8_t u16 = vmovl_u8(uExpanded);

            uint32x4_t v32_low = vmovl_u16(vget_low_u16(v16));
            uint32x4_t v32_high = vmovl_u16(vget_high_u16(v16));
            uint32x4_t u32_low = vmovl_u16(vget_low_u16(u16));
            uint32x4_t u32_high = vmovl_u16(vget_high_u16(u16));

            float32x4_t vf_low = vsubq_f32(vcvtq_f32_u32(v32_low), c128);
            float32x4_t vf_high = vsubq_f32(vcvtq_f32_u32(v32_high), c128);
            float32x4_t uf_low = vsubq_f32(vcvtq_f32_u32(u32_low), c128);
            float32x4_t uf_high = vsubq_f32(vcvtq_f32_u32(u32_high), c128);

            // 4. 应用 BT.601 矩阵: R = Y' + 1.402*V, G = Y' - 0.344*U - 0.714*V, B = Y' + 1.772*U
            float32x4_t rf_low = vaddq_f32(yf_low, vmulq_f32(rvCoeff, vf_low));
            float32x4_t rf_high = vaddq_f32(yf_high, vmulq_f32(rvCoeff, vf_high));

            float32x4_t gf_low = vaddq_f32(
                vaddq_f32(yf_low, vmulq_f32(guCoeff, uf_low)),
                vmulq_f32(gvCoeff, vf_low));
            float32x4_t gf_high = vaddq_f32(
                vaddq_f32(yf_high, vmulq_f32(guCoeff, uf_high)),
                vmulq_f32(gvCoeff, vf_high));

            float32x4_t bf_low = vaddq_f32(yf_low, vmulq_f32(buCoeff, uf_low));
            float32x4_t bf_high = vaddq_f32(yf_high, vmulq_f32(buCoeff, uf_high));

            // 5. Clamp 到 [0, 255] 并转为整数
            rf_low = vmaxq_f32(c0, vminq_f32(c255, rf_low));
            rf_high = vmaxq_f32(c0, vminq_f32(c255, rf_high));
            gf_low = vmaxq_f32(c0, vminq_f32(c255, gf_low));
            gf_high = vmaxq_f32(c0, vminq_f32(c255, gf_high));
            bf_low = vmaxq_f32(c0, vminq_f32(c255, bf_low));
            bf_high = vmaxq_f32(c0, vminq_f32(c255, bf_high));

            uint32x4_t r32_low = vcvtq_u32_f32(rf_low);
            uint32x4_t r32_high = vcvtq_u32_f32(rf_high);
            uint32x4_t g32_low = vcvtq_u32_f32(gf_low);
            uint32x4_t g32_high = vcvtq_u32_f32(gf_high);
            uint32x4_t b32_low = vcvtq_u32_f32(bf_low);
            uint32x4_t b32_high = vcvtq_u32_f32(bf_high);
            uint32x4_t a32 = vdupq_n_u32(255);

            // 6. 收缩 uint32 → uint16 → uint8
            uint16x4_t r16_low = vmovn_u32(r32_low);
            uint16x4_t r16_high = vmovn_u32(r32_high);
            uint16x4_t g16_low = vmovn_u32(g32_low);
            uint16x4_t g16_high = vmovn_u32(g32_high);
            uint16x4_t b16_low = vmovn_u32(b32_low);
            uint16x4_t b16_high = vmovn_u32(b32_high);
            uint16x4_t a16 = vmovn_u32(a32);

            uint8x8_t r8 = vmovn_u16(vcombine_u16(r16_low, r16_high));
            uint8x8_t g8 = vmovn_u16(vcombine_u16(g16_low, g16_high));
            uint8x8_t b8 = vmovn_u16(vcombine_u16(b16_low, b16_high));
            uint8x8_t a8 = vmovn_u16(vcombine_u16(a16, a16));

            // 7. 交织为 RGBA 并存储
            uint8x8x4_t rgba = { {r8, g8, b8, a8} };
            vst4_u8(rgbaOutput + (y * width + x) * 4, rgba);
        }

        // ---- 标量尾部 (width 不对齐 8 的剩余像素) ----
        for (; x < width; x++) {
            const uint32_t yIndex = y * width + x;
            const uint32_t uvIndex = (y / 2) * width + (x & ~1u);

            const float Y = static_cast<float>(yPlane[yIndex]) - 16.0f;
            const float U = static_cast<float>(uvPlane[uvIndex]) - 128.0f;
            const float V = static_cast<float>(uvPlane[uvIndex + 1]) - 128.0f;

            float R = Y * 1.164f + V * YUV_TO_RGB_R_V;
            float G = Y * 1.164f + U * YUV_TO_RGB_G_U + V * YUV_TO_RGB_G_V;
            float B = Y * 1.164f + U * YUV_TO_RGB_B_U;

            const uint32_t outIdx = (y * width + x) * 4;
            rgbaOutput[outIdx + 0] = static_cast<uint8_t>(std::max(0.0f, std::min(255.0f, R)));
            rgbaOutput[outIdx + 1] = static_cast<uint8_t>(std::max(0.0f, std::min(255.0f, G)));
            rgbaOutput[outIdx + 2] = static_cast<uint8_t>(std::max(0.0f, std::min(255.0f, B)));
            rgbaOutput[outIdx + 3] = 255;
        }
    }

    OH_LOG_INFO(LOG_APP, "[ImageProcessor] NEON 加速转换完成: %{public}dx%{public}d", width, height);
}
#endif // __ARM_NEON

// ============================================================
// CameraNativeManager 实现
// ============================================================

CameraNativeManager::CameraNativeManager()
    : frameCallback(nullptr), callbackUserData(nullptr) {
    OH_LOG_INFO(LOG_APP, "[CameraNativeManager] 已创建");
}

CameraNativeManager::~CameraNativeManager() {
    unregisterFrameCallback();
    OH_LOG_INFO(LOG_APP, "[CameraNativeManager] 已销毁");
}

bool CameraNativeManager::registerFrameCallback(FrameCallback callback, void* userData) {
    if (!callback) {
        OH_LOG_ERROR(LOG_APP, "[CameraNativeManager] 回调函数为空!");
        return false;
    }
    this->frameCallback = callback;
    this->callbackUserData = userData;
    OH_LOG_INFO(LOG_APP, "[CameraNativeManager] 帧回调已注册");
    return true;
}

void CameraNativeManager::unregisterFrameCallback() {
    this->frameCallback = nullptr;
    this->callbackUserData = nullptr;
    OH_LOG_INFO(LOG_APP, "[CameraNativeManager] 帧回调已取消");
}

bool CameraNativeManager::processFrame(const CameraFrameData* frame) {
    if (!frame || !frame->data) {
        return false;
    }

    // 如果有注册回调，传递帧数据
    if (this->frameCallback) {
        this->frameCallback(frame, this->callbackUserData);
    }

    return true;
}

} // namespace UnifiedCamera
