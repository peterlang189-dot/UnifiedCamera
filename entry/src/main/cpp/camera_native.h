/**
 * camera_native.h - 原生相机图像处理模块
 *
 * 提供 N-API 接口，供 ArkTS 层调用进行：
 * - NV21/NV12 格式转换
 * - YUV → RGB 色彩空间转换
 * - 图像滤镜 (灰度、镜像、亮度调节)
 * - 视频帧预处理
 */

#ifndef CAMERA_NATIVE_H
#define CAMERA_NATIVE_H

#include <napi/native_api.h>
#include <cstdint>
#include <vector>
#include <string>

namespace UnifiedCamera {

/**
 * 图像数据类型枚举
 */
enum class ImageFormat {
    NV21 = 0,       // YUV420SP (NV21)
    NV12 = 1,       // YUV420SP (NV12)
    YUV420P = 2,    // YUV420 planar
    RGBA8888 = 3,   // 32-bit RGBA
    BGRA8888 = 4,   // 32-bit BGRA
    JPEG = 5        // JPEG 编码
};

/**
 * 图像滤镜类型
 */
enum class FilterType {
    NONE = 0,           // 无滤镜
    GRAYSCALE = 1,      // 灰度
    SEPIA = 2,          // 复古
    MIRROR = 3,         // 水平镜像
    NEGATIVE = 4,       // 负片
    BRIGHTNESS = 5,     // 亮度调节
    CONTRAST = 6,       // 对比度调节
    BLUR = 7,           // 高斯模糊
    SHARPEN = 8         // 锐化
};

/**
 * 图像尺寸结构体
 */
struct ImageSize {
    uint32_t width;
    uint32_t height;
};

/**
 * 图像处理参数
 */
struct ImageParams {
    uint32_t width;
    uint32_t height;
    ImageFormat format;
    FilterType filter;
    float filterStrength;     // 滤镜强度 0.0 - 1.0
    int32_t rotation;         // 旋转角度 0, 90, 180, 270
    bool flipHorizontal;
    bool flipVertical;
    int32_t jpegQuality;      // JPEG 质量 1-100
};

/**
 * 图像处理器类
 *
 * 封装高性能图像处理算法，使用 NEON SIMD 指令集加速 (ARM64)
 */
class ImageProcessor {
public:
    ImageProcessor();
    ~ImageProcessor();

    /**
     * NV21 → RGBA 色彩空间转换
     * @param nv21Data 输入的 NV21 数据
     * @param rgbaOutput 输出的 RGBA 数据缓冲区 (需预分配 width*height*4)
     * @param width 图像宽度
     * @param height 图像高度
     * @param rotation 输出旋转角度
     * @param flipHorizontal 是否水平翻转
     */
    static void nv21ToRGBA(const uint8_t* nv21Data,
                           uint8_t* rgbaOutput,
                           uint32_t width,
                           uint32_t height,
                           int32_t rotation = 0,
                           bool flipHorizontal = false);

    /**
     * NV21 → NV12 转换 (交换 UV 分量)
     * @param nv21Data 输入
     * @param nv12Output 输出
     * @param width 宽度
     * @param height 高度
     */
    static void nv21ToNV12(const uint8_t* nv21Data,
                           uint8_t* nv12Output,
                           uint32_t width,
                           uint32_t height);

    /**
     * RGBA → JPEG 编码
     * @param rgbaData 输入的 RGBA 数据
     * @param width 宽度
     * @param height 高度
     * @param quality JPEG 质量 (1-100)
     * @param jpegOutput 输出的 JPEG 数据
     * @param jpegSize 输出的 JPEG 大小
     * @return 成功返回 true
     */
    static bool rgbaToJPEG(const uint8_t* rgbaData,
                           uint32_t width,
                           uint32_t height,
                           int32_t quality,
                           uint8_t* jpegOutput,
                           size_t* jpegSize);

    /**
     * 应用图像滤镜 (统一入口)
     * @param rgbaData 输入/输出的 RGBA 数据 (原地修改)
     * @param width 宽度
     * @param height 高度
     * @param filter 滤镜类型
     * @param strength 强度 0.0-1.0
     */
    static void applyFilter(uint8_t* rgbaData,
                            uint32_t width,
                            uint32_t height,
                            FilterType filter,
                            float strength = 1.0f);

    /**
     * 调整亮度
     * @param rgbaData 输入/输出
     * @param pixelCount 像素总数
     * @param factor 亮度因子 (-1.0 ~ 1.0)
     */
    static void adjustBrightness(uint8_t* rgbaData,
                                 uint32_t pixelCount,
                                 float factor);

    /**
     * 调整对比度
     * @param rgbaData 输入/输出
     * @param pixelCount 像素总数
     * @param factor 对比度因子 (0.0 ~ 2.0, 1.0=原始)
     */
    static void adjustContrast(uint8_t* rgbaData,
                               uint32_t pixelCount,
                               float factor);

    /**
     * 水平翻转图像
     * @param rgbaData 输入/输出
     * @param width 宽度
     * @param height 高度
     */
    static void mirrorHorizontal(uint8_t* rgbaData,
                                 uint32_t width,
                                 uint32_t height);

    /**
     * 垂直翻转图像
     * @param rgbaData 输入/输出
     * @param width 宽度
     * @param height 高度
     */
    static void mirrorVertical(uint8_t* rgbaData,
                               uint32_t width,
                               uint32_t height);

    /**
     * 旋转图像 90/180/270 度
     * @param src 源数据
     * @param dst 目标缓冲区
     * @param width 宽度
     * @param height 高度
     * @param rotation 旋转角度 (90, 180, 270)
     */
    static void rotateImage(const uint8_t* src,
                            uint8_t* dst,
                            uint32_t width,
                            uint32_t height,
                            int32_t rotation);

private:
    // YUV→RGB 转换矩阵系数 (BT.601)
    static constexpr float YUV_TO_RGB_R_V = 1.402f;
    static constexpr float YUV_TO_RGB_G_U = -0.34414f;
    static constexpr float YUV_TO_RGB_G_V = -0.71414f;
    static constexpr float YUV_TO_RGB_B_U = 1.772f;

    // 亮度对比度查找表生成
    static void buildBrightnessLUT(uint8_t* lut, float factor);
    static void buildContrastLUT(uint8_t* lut, float factor);

    // 独立滤镜方法（从 applyFilter 拆分，降低圈复杂度）
    static void applyGrayscale(uint8_t* rgbaData, uint32_t pixelCount);
    static void applySepia(uint8_t* rgbaData, uint32_t pixelCount);
    static void applyNegative(uint8_t* rgbaData, uint32_t pixelCount);
    static void applyBlur(uint8_t* rgbaData, uint32_t width, uint32_t height);
    static void applySharpen(uint8_t* rgbaData, uint32_t width, uint32_t height);

    // 滤镜分发函数指针类型：func(rgbaData, width_or_pixelCount, height_or_unused)
    using FilterFunc = void (*)(uint8_t*, uint32_t, uint32_t);
    static FilterFunc getFilterFunc(FilterType filter);

#ifdef __ARM_NEON
    // NEON SIMD 加速路径
    static void nv21ToRGBA_NEON(const uint8_t* nv21Data,
                                 uint8_t* rgbaOutput,
                                 uint32_t width,
                                 uint32_t height);
#endif
};

/**
 * 相机帧回调数据
 */
struct CameraFrameData {
    uint8_t* data;          // 帧数据指针
    uint32_t size;          // 数据大小
    ImageFormat format;     // 数据格式
    uint32_t width;         // 宽度
    uint32_t height;        // 高度
    int64_t timestamp;      // 时间戳 (纳秒)
    int32_t rotation;       // 旋转角度
};

/**
 * 帧回调函数类型定义
 */
using FrameCallback = void (*)(const CameraFrameData* frame, void* userData);

/**
 * 相机原生管理器
 *
 * 提供底层相机帧数据获取和处理能力
 */
class CameraNativeManager {
public:
    CameraNativeManager();
    ~CameraNativeManager();

    /**
     * 注册帧数据回调
     */
    bool registerFrameCallback(FrameCallback callback, void* userData);

    /**
     * 取消帧数据回调
     */
    void unregisterFrameCallback();

    /**
     * 处理单帧数据
     */
    bool processFrame(const CameraFrameData* frame);

private:
    ImageProcessor processor;
    FrameCallback frameCallback;
    void* callbackUserData;
};

} // namespace UnifiedCamera

#endif // CAMERA_NATIVE_H
