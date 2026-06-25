/**
 * camera_native 原生模块的 TypeScript 类型声明
 *
 * import nativeModule from 'libcamera_native.so';
 */

/**
 * 滤镜类型枚举
 */
export enum FilterType {
  NONE = 0,
  GRAYSCALE = 1,
  SEPIA = 2,
  MIRROR = 3,
  NEGATIVE = 4,
  BRIGHTNESS = 5,
  CONTRAST = 6,
  BLUR = 7,
  SHARPEN = 8
}

/**
 * 原生图像处理模块接口
 */
export interface CameraNativeModule {
  /**
   * NV21 → RGBA 色彩空间转换
   * @param nv21Buffer 输入的 NV21 格式数据
   * @param width 图像宽度
   * @param height 图像高度
   * @returns RGBA 格式的 ArrayBuffer
   */
  nv21ToRGBA(nv21Buffer: ArrayBuffer, width: number, height: number): ArrayBuffer;

  /**
   * NV21 → NV12 格式转换 (交换 UV 分量)
   * @param nv21Buffer 输入的 NV21 格式数据
   * @param width 图像宽度
   * @param height 图像高度
   * @returns NV12 格式的 ArrayBuffer
   */
  nv21ToNV12(nv21Buffer: ArrayBuffer, width: number, height: number): ArrayBuffer;

  /**
   * 对 RGBA 图像应用滤镜 (原地修改)
   * @param rgbaBuffer RGBA 图像数据
   * @param width 宽度
   * @param height 高度
   * @param filterType 滤镜类型
   * @param strength 滤镜强度 (0.0-1.0)
   */
  applyFilter(rgbaBuffer: ArrayBuffer, width: number, height: number, filterType: number, strength?: number): void;

  /**
   * 调整图像亮度 (原地修改)
   * @param rgbaBuffer RGBA 数据
   * @param pixelCount 像素总数 (width * height)
   * @param factor 亮度因子 (-1.0 ~ 1.0)
   */
  adjustBrightness(rgbaBuffer: ArrayBuffer, pixelCount: number, factor: number): void;

  /**
   * 调整图像对比度 (原地修改)
   * @param rgbaBuffer RGBA 数据
   * @param pixelCount 像素总数 (width * height)
   * @param factor 对比度因子 (0.0 ~ 2.0, 1.0=原始)
   */
  adjustContrast(rgbaBuffer: ArrayBuffer, pixelCount: number, factor: number): void;

  /**
   * 翻转图像
   * @param rgbaBuffer RGBA 数据
   * @param width 宽度
   * @param height 高度
   * @param direction 0=水平翻转, 1=垂直翻转
   */
  mirrorImage(rgbaBuffer: ArrayBuffer, width: number, height: number, direction: number): void;

  /**
   * 旋转图像
   * @param rgbaBuffer RGBA 数据
   * @param width 宽度
   * @param height 高度
   * @param angle 旋转角度 (0, 90, 180, 270)
   * @returns 旋转后的 RGBA 数据
   */
  rotateImage(rgbaBuffer: ArrayBuffer, width: number, height: number, angle: number): ArrayBuffer;

  /**
   * 获取图像处理器版本信息
   * @returns 版本字符串
   */
  getProcessorVersion(): string;
}
