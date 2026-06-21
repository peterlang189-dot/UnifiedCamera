import { camera } from '@kit.CameraKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CameraConstants } from './CameraConstants';
import { FileUtils } from '../utils/FileUtils';
import { GlobalContext } from '../utils/GlobalContext';

/**
 * 相机ViewModel
 * 封装相机操作的核心逻辑：初始化、预览、拍照、录像、参数控制
 */
export class CameraViewModel {
  private cameraManager: camera.CameraManager | null = null;
  private cameraInput: camera.CameraInput | null = null;
  private captureSession: camera.CaptureSession | null = null;
  private previewOutput: camera.PreviewOutput | null = null;
  private photoOutput: camera.PhotoOutput | null = null;
  private videoOutput: camera.VideoOutput | null = null;

  private currentCameraIndex: number = 0;        // 当前使用的摄像头索引
  private supportedCameras: Array<camera.CameraDevice> = [];
  private currentFlashMode: number = CameraConstants.FLASH_MODE_OFF;
  private currentZoomRatio: number = CameraConstants.ZOOM_MIN;
  private recordingState: number = CameraConstants.RECORDING_STATE_IDLE;
  private isSessionStarted: boolean = false;

  // 回调
  private onPhotoCaptureCallback: ((uri: string) => void) | null = null;
  private onVideoRecordCallback: ((uri: string) => void) | null = null;
  private onErrorCallback: ((error: string) => void) | null = null;

  /**
   * 初始化相机管理器
   */
  public async initCamera(): Promise<void> {
    try {
      this.cameraManager = camera.getCameraManager(GlobalContext.getInstance().getContext() as any);
      this.supportedCameras = this.cameraManager.getSupportedCameras();

      if (this.supportedCameras.length === 0) {
        throw new Error('未检测到可用摄像头');
      }

      console.info(`[CameraVM] 检测到 ${this.supportedCameras.length} 个摄像头`);
      for (const cam of this.supportedCameras) {
        console.info(`[CameraVM] 摄像头: ${cam.cameraId} (${cam.cameraPosition})`);
      }
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[CameraVM] 初始化失败: ${error.message}`);
      this.notifyError(`相机初始化失败: ${error.message}`);
    }
  }

  /**
   * 创建并启动相机会话
   * @param surfaceId 预览 Surface ID (XComponent)
   */
  public async startPreview(surfaceId: string): Promise<void> {
    if (this.isSessionStarted) {
      console.warn('[CameraVM] 会话已启动，先停止');
      await this.stopPreview();
    }

    try {
      // 1. 创建 CaptureSession
      this.captureSession = camera.createCaptureSession(
        GlobalContext.getInstance().getContext() as any
      );

      // 2. 选择摄像头并创建 CameraInput
      const cameraDevice = this.supportedCameras[this.currentCameraIndex];
      if (!cameraDevice) {
        throw new Error('无法获取摄像头设备');
      }
      this.cameraInput = this.cameraManager!.createCameraInput(cameraDevice);
      await this.cameraInput.open();

      // 3. 创建 PreviewOutput
      this.previewOutput = camera.createPreviewOutput({
        width: CameraConstants.PREVIEW_WIDTH,
        height: CameraConstants.PREVIEW_HEIGHT
      });
      await this.previewOutput.setSurfaceId(surfaceId);

      // 4. 创建 PhotoOutput
      this.photoOutput = camera.createPhotoOutput({
        width: CameraConstants.PHOTO_WIDTH,
        height: CameraConstants.PHOTO_HEIGHT
      });

      // 5. 创建 VideoOutput
      this.videoOutput = camera.createVideoOutput({
        width: CameraConstants.VIDEO_WIDTH,
        height: CameraConstants.VIDEO_HEIGHT,
        frameRate: CameraConstants.VIDEO_FRAME_RATE
      });

      // 6. 配置 Session
      this.captureSession.beginConfig();
      this.captureSession.addInput(this.cameraInput);
      this.captureSession.addOutput(this.previewOutput);
      this.captureSession.addOutput(this.photoOutput);
      this.captureSession.addOutput(this.videoOutput);
      await this.captureSession.commitConfig();

      // 7. 启动 Session
      await this.captureSession.start();
      this.isSessionStarted = true;

      // 设置照片回调
      this.setupPhotoCallback();
      // 设置视频回调
      this.setupVideoCallback();

      console.info('[CameraVM] 预览已启动');
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[CameraVM] 启动预览失败: ${error.message}`);
      this.notifyError(`启动预览失败: ${error.message}`);
    }
  }

  /**
   * 配置拍照回调
   */
  private setupPhotoCallback(): void {
    if (!this.photoOutput) return;

    this.photoOutput.on('photoAssetAvailable', async (err: BusinessError, photoAsset: camera.PhotoAsset) => {
      if (err) {
        console.error(`[CameraVM] 拍照回调错误: ${err.message}`);
        this.notifyError(`拍照失败: ${err.message}`);
        return;
      }
      console.info('[CameraVM] 照片已捕获, 开始处理...');

      // 将 PhotoAsset 转为 ArrayBuffer 并保存
      try {
        const imageBuffer = await photoAsset.getRawBuffer();
        const uri = await FileUtils.savePhotoToGallery(imageBuffer);
        if (uri && this.onPhotoCaptureCallback) {
          this.onPhotoCaptureCallback(uri);
        }
      } catch (e) {
        console.error(`[CameraVM] 处理照片失败: ${JSON.stringify(e)}`);
      } finally {
        photoAsset.release();
      }
    });
  }

  /**
   * 配置视频录制回调
   */
  private setupVideoCallback(): void {
    if (!this.videoOutput) return;

    this.videoOutput.on('videoAssetAvailable', async (err: BusinessError, videoAsset: camera.VideoAsset) => {
      if (err) {
        console.error(`[CameraVM] 录像回调错误: ${err.message}`);
        this.notifyError(`录像失败: ${err.message}`);
        return;
      }
      console.info('[CameraVM] 视频已捕获, 开始处理...');

      try {
        const videoUri = videoAsset.uri;
        const savedUri = await FileUtils.saveVideoToGallery(videoUri);
        if (savedUri && this.onVideoRecordCallback) {
          this.onVideoRecordCallback(savedUri);
        }
      } catch (e) {
        console.error(`[CameraVM] 处理视频失败: ${JSON.stringify(e)}`);
      } finally {
        videoAsset.release();
      }
    });
  }

  /**
   * 拍照
   */
  public async takePhoto(): Promise<void> {
    if (!this.photoOutput || !this.isSessionStarted) {
      this.notifyError('相机未就绪，无法拍照');
      return;
    }

    try {
      // 设置闪光灯
      await this.applyFlashMode();

      await this.photoOutput.capture();
      console.info('[CameraVM] 拍照指令已发送');
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[CameraVM] 拍照失败: ${error.message}`);
      this.notifyError(`拍照失败: ${error.message}`);
    }
  }

  /**
   * 开始录像
   */
  public async startRecording(): Promise<void> {
    if (!this.videoOutput || !this.isSessionStarted) {
      this.notifyError('相机未就绪，无法录像');
      return;
    }

    if (this.recordingState === CameraConstants.RECORDING_STATE_RECORDING) {
      console.warn('[CameraVM] 已在录像中');
      return;
    }

    try {
      // 设置闪光灯（手电筒模式）
      if (this.currentFlashMode === CameraConstants.FLASH_MODE_TORCH) {
        await this.captureSession!.setFlashMode(camera.FlashMode.FLASH_MODE_OPEN);
      }

      await this.videoOutput.start();
      this.recordingState = CameraConstants.RECORDING_STATE_RECORDING;
      console.info('[CameraVM] 录像已开始');
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[CameraVM] 开始录像失败: ${error.message}`);
      this.notifyError(`开始录像失败: ${error.message}`);
    }
  }

  /**
   * 停止录像
   */
  public async stopRecording(): Promise<void> {
    if (!this.videoOutput) return;

    if (this.recordingState !== CameraConstants.RECORDING_STATE_RECORDING) {
      console.warn('[CameraVM] 当前未在录像');
      return;
    }

    try {
      await this.videoOutput.stop();
      this.recordingState = CameraConstants.RECORDING_STATE_IDLE;
      console.info('[CameraVM] 录像已停止');
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[CameraVM] 停止录像失败: ${error.message}`);
    }
  }

  /**
   * 停止预览，释放资源
   */
  public async stopPreview(): Promise<void> {
    try {
      // 如果正在录像，先停止
      if (this.recordingState === CameraConstants.RECORDING_STATE_RECORDING) {
        await this.stopRecording();
      }

      if (this.captureSession && this.isSessionStarted) {
        await this.captureSession.stop();
        this.isSessionStarted = false;
      }

      // 释放资源
      this.previewOutput?.release();
      this.photoOutput?.release();
      this.videoOutput?.release();
      this.cameraInput?.close();
      this.captureSession?.release();

      this.previewOutput = null;
      this.photoOutput = null;
      this.videoOutput = null;
      this.cameraInput = null;
      this.captureSession = null;

      console.info('[CameraVM] 预览已停止，资源已释放');
    } catch (err) {
      console.error(`[CameraVM] 停止预览失败: ${JSON.stringify(err)}`);
    }
  }

  /**
   * 切换前后摄像头
   */
  public async switchCamera(): Promise<string> {
    if (this.supportedCameras.length < 2) {
      return '仅有一个摄像头，无法切换';
    }

    // 循环切换摄像头索引
    this.currentCameraIndex = (this.currentCameraIndex + 1) % this.supportedCameras.length;
    const newCamera = this.supportedCameras[this.currentCameraIndex];

    // 必须用新的 surfaceId 重建会话...
    console.info(`[CameraVM] 切换到摄像头: ${newCamera.cameraId} (位置: ${newCamera.cameraPosition})`);

    const positionName = newCamera.cameraPosition === camera.CameraPosition.CAMERA_POSITION_FRONT
      ? '前置' : '后置';

    return `已切换到${positionName}摄像头`;
  }

  /**
   * 设置闪光灯模式
   */
  public async setFlashMode(mode: number): Promise<void> {
    this.currentFlashMode = mode;
    console.info(`[CameraVM] 闪光灯模式: ${mode}`);
    await this.applyFlashMode();
  }

  /**
   * 应用闪光灯设置
   */
  private async applyFlashMode(): Promise<void> {
    if (!this.captureSession) return;

    try {
      switch (this.currentFlashMode) {
        case CameraConstants.FLASH_MODE_OFF:
          await this.captureSession.setFlashMode(camera.FlashMode.FLASH_MODE_CLOSE);
          break;
        case CameraConstants.FLASH_MODE_ON:
          await this.captureSession.setFlashMode(camera.FlashMode.FLASH_MODE_OPEN);
          break;
        case CameraConstants.FLASH_MODE_AUTO:
          await this.captureSession.setFlashMode(camera.FlashMode.FLASH_MODE_AUTO);
          break;
        case CameraConstants.FLASH_MODE_TORCH:
          await this.captureSession.setFlashMode(camera.FlashMode.FLASH_MODE_ALWAYS_OPEN);
          break;
      }
    } catch (err) {
      console.error(`[CameraVM] 设置闪光灯失败: ${JSON.stringify(err)}`);
    }
  }

  /**
   * 设置缩放
   */
  public async setZoom(ratio: number): Promise<void> {
    if (!this.captureSession) return;

    const zoom = Math.max(CameraConstants.ZOOM_MIN, Math.min(ratio, CameraConstants.ZOOM_MAX));
    try {
      await this.captureSession.setZoomRatio(zoom);
      this.currentZoomRatio = zoom;
      console.info(`[CameraVM] 缩放: ${zoom.toFixed(1)}x`);
    } catch (err) {
      console.error(`[CameraVM] 设置缩放失败: ${JSON.stringify(err)}`);
    }
  }

  /**
   * 获取当前缩放值
   */
  public getZoom(): number {
    return this.currentZoomRatio;
  }

  /**
   * 获取当前录制状态
   */
  public getRecordingState(): number {
    return this.recordingState;
  }

  /**
   * 获取支持的摄像头数量
   */
  public getCameraCount(): number {
    return this.supportedCameras.length;
  }

  /**
   * 获取当前摄像头类型
   */
  public getCurrentCameraPosition(): camera.CameraPosition | null {
    if (this.supportedCameras.length === 0) return null;
    return this.supportedCameras[this.currentCameraIndex].cameraPosition;
  }

  // ===== 回调注册 =====

  public setOnPhotoCapture(callback: (uri: string) => void): void {
    this.onPhotoCaptureCallback = callback;
  }

  public setOnVideoRecord(callback: (uri: string) => void): void {
    this.onVideoRecordCallback = callback;
  }

  public setOnError(callback: (error: string) => void): void {
    this.onErrorCallback = callback;
  }

  private notifyError(message: string): void {
    console.error(`[CameraVM] 错误: ${message}`);
    if (this.onErrorCallback) {
      this.onErrorCallback(message);
    }
  }

  /**
   * 释放所有资源
   */
  public async release(): Promise<void> {
    await this.stopPreview();
    this.onPhotoCaptureCallback = null;
    this.onVideoRecordCallback = null;
    this.onErrorCallback = null;
    console.info('[CameraVM] CameraViewModel 已完全释放');
  }
}
