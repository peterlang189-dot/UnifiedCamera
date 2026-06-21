/**
 * 相机相关常量定义
 */
export class CameraConstants {
  // 视频分辨率
  static readonly VIDEO_WIDTH: number = 1920;
  static readonly VIDEO_HEIGHT: number = 1080;
  static readonly VIDEO_FRAME_RATE: number = 30;

  // 照片分辨率
  static readonly PHOTO_WIDTH: number = 3840;
  static readonly PHOTO_HEIGHT: number = 2160;

  // 预览分辨率
  static readonly PREVIEW_WIDTH: number = 1920;
  static readonly PREVIEW_HEIGHT: number = 1080;

  // 视频编码参数
  static readonly VIDEO_BITRATE: number = 10_000_000;  // 10 Mbps
  static readonly VIDEO_CODEC: string = 'video/hevc';

  // 照片质量
  static readonly PHOTO_QUALITY: number = 95;

  // 定时拍照延迟（秒）
  static readonly TIMER_DURATIONS: number[] = [0, 3, 5, 10];

  // 闪光灯模式
  static readonly FLASH_MODE_OFF: number = 0;
  static readonly FLASH_MODE_ON: number = 1;
  static readonly FLASH_MODE_AUTO: number = 2;
  static readonly FLASH_MODE_TORCH: number = 3;

  // 缩放范围
  static readonly ZOOM_MIN: number = 1.0;
  static readonly ZOOM_MAX: number = 10.0;
  static readonly ZOOM_STEP: number = 0.5;

  // 对焦模式
  static readonly FOCUS_MODE_AUTO: number = 0;
  static readonly FOCUS_MODE_CONTINUOUS: number = 1;
  static readonly FOCUS_MODE_MANUAL: number = 2;

  // 媒体保存路径
  static readonly MEDIA_SAVE_DIR: string = 'UnifiedCamera';

  // 录制状态
  static readonly RECORDING_STATE_IDLE: number = 0;
  static readonly RECORDING_STATE_RECORDING: number = 1;
  static readonly RECORDING_STATE_PAUSED: number = 2;

  // XComponent ID
  static readonly PREVIEW_SURFACE_ID: string = 'cameraPreviewSurface';
}
