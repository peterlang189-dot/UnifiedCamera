import { camera } from '@kit.CameraKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { media } from '@kit.MediaKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CameraConstants } from './CameraConstants';
import { FileUtils } from '../utils/FileUtils';
import { GlobalContext } from '../utils/GlobalContext';
import nativeModule from 'libcamera_native.so';

/**
 * 相机ViewModel — 支持拍照、录像、画幅切换及原生 C++ 图像处理
 */
export class CameraViewModel {
  private cameraManager: camera.CameraManager | null = null;
  private cameraInput: camera.CameraInput | null = null;
  private captureSession: camera.CaptureSession | null = null;
  private previewOutput: camera.PreviewOutput | null = null;
  private photoOutput: camera.PhotoOutput | null = null;
  private videoOutput: camera.VideoOutput | null = null;

  private currentCameraIndex: number = 0;
  private supportedCameras: Array<camera.CameraDevice> = [];
  private currentZoomRatio: number = CameraConstants.ZOOM_MIN;
  private isRecording: boolean = false;
  private isSessionStarted: boolean = false;
  private currentAspectRatio: number = CameraConstants.ASPECT_RATIO_4_3;

  // 视频录制相关
  private avRecorder: media.AVRecorder | null = null;
  private videoOutputFileFd: number = -1;
  private videoOutputFilePath: string = '';

  // 缓存设备支持的 Profile
  private cachedPreviewProfiles: Array<camera.Profile> = [];
  private cachedPhotoProfiles: Array<camera.Profile> = [];
  private cachedVideoProfiles: Array<camera.Profile> = [];

  // 可选滤镜处理 (由外部设置)
  private postProcessFilter: number = 0;    // FilterType.NONE = 无后处理
  private postProcessStrength: number = 0.5;

  private onPhotoCaptureCallback: ((uri: string) => void) | null = null;
  private onVideoRecordCallback: ((uri: string) => void) | null = null;
  private onErrorCallback: ((error: string) => void) | null = null;

  public initCamera(context: Context): void {
    try {
      this.cameraManager = camera.getCameraManager(context);
      this.supportedCameras = this.cameraManager.getSupportedCameras();
      if (this.supportedCameras.length === 0) throw new Error('无可用摄像头');
      console.info(`[CameraVM] ${this.supportedCameras.length}个摄像头`);

      // 输出版本信息确认原生模块已加载
      try {
        const version = nativeModule.getProcessorVersion();
        console.info(`[CameraVM] 原生模块已加载: ${version}`);
      } catch (e) {
        console.warn(`[CameraVM] 原生模块不可用: ${JSON.stringify(e)}`);
      }
    } catch (err) {
      const error = err as BusinessError;
      this.notifyError(`相机初始化失败: ${error.message}`);
    }
  }

  /**
   * 设置拍照后处理滤镜 (0=NONE 不处理)
   */
  public setPostProcessFilter(filter: number, strength: number = 0.5): void {
    this.postProcessFilter = filter;
    this.postProcessStrength = strength;
  }

  /**
   * 从 Profile 列表中选择最接近目标比例的 Profile
   */
  private selectProfile(profiles: Array<camera.Profile>, aspectRatio: number): camera.Profile | null {
    if (!profiles || profiles.length === 0) return null;
    const target: number = CameraConstants.ASPECT_RATIO_VALUES[aspectRatio];
    let best: camera.Profile = profiles[0];
    let bestDiff: number = Number.MAX_VALUE;
    for (const p of profiles) {
      if (p.size.height === 0) continue;
      const r: number = p.size.width / p.size.height;
      const diff: number = Math.abs(r - target);
      if (diff < bestDiff - 0.01 ||
          (Math.abs(diff - bestDiff) < 0.01 && p.size.width * p.size.height > best.size.width * best.size.height)) {
        bestDiff = diff;
        best = p;
      }
    }
    console.info(`[CameraVM] 选择Profile: ${best.size.width}x${best.size.height} (目标比例=${target.toFixed(3)})`);
    return best;
  }

  public async startPreview(surfaceId: string): Promise<void> {
    if (this.isSessionStarted) await this.stopPreview();

    try {
      if (!this.cameraManager) throw new Error('CameraManager 未初始化');
      const cameraDevice = this.supportedCameras[this.currentCameraIndex];

      // 1. CameraInput
      this.cameraInput = this.cameraManager.createCameraInput(cameraDevice);
      await this.cameraInput.open();

      // 2. 获取设备支持的 Profile 并缓存
      const outputCap: camera.CameraOutputCapability =
        this.cameraManager.getSupportedOutputCapability(cameraDevice, camera.SceneMode.NORMAL_PHOTO);
      this.cachedPreviewProfiles = outputCap.previewProfiles;
      this.cachedPhotoProfiles = outputCap.photoProfiles;
      console.info(`[CameraVM] Preview:${this.cachedPreviewProfiles.length} Photo:${this.cachedPhotoProfiles.length}`);

      if (!this.cachedPreviewProfiles || this.cachedPreviewProfiles.length === 0) {
        throw new Error('设备不支持预览');
      }

      // 也缓存视频 Profile (用于后续录像)
      try {
        const videoCap: camera.CameraOutputCapability =
          this.cameraManager.getSupportedOutputCapability(cameraDevice, camera.SceneMode.NORMAL_VIDEO);
        this.cachedVideoProfiles = videoCap.previewProfiles || [];
      } catch (e) {
        this.cachedVideoProfiles = [];
      }

      // 3. 按当前画幅选择 Profile
      const previewProfile: camera.Profile | null = this.selectProfile(this.cachedPreviewProfiles, this.currentAspectRatio);
      const photoProfile: camera.Profile | null = this.selectProfile(this.cachedPhotoProfiles, this.currentAspectRatio);
      if (!previewProfile) throw new Error('无匹配预览Profile');

      // 4. 创建 Session 和 Output
      this.captureSession = this.cameraManager.createCaptureSession();
      this.previewOutput = this.cameraManager.createPreviewOutput(previewProfile, surfaceId);
      this.photoOutput = photoProfile ?
        this.cameraManager.createPhotoOutput(photoProfile) :
        this.cameraManager.createPhotoOutput();

      // 5. 配置并启动
      this.captureSession.beginConfig();
      this.captureSession.addInput(this.cameraInput);
      this.captureSession.addOutput(this.previewOutput);
      this.captureSession.addOutput(this.photoOutput);
      await this.captureSession.commitConfig();
      await this.captureSession.start();
      this.isSessionStarted = true;

      // 6. 拍照回调 (含可选 C++ 后处理)
      this.photoOutput.on('photoAssetAvailable', (err: BusinessError, pa: photoAccessHelper.PhotoAsset) => {
        if (err) { console.error(`[CameraVM] photo err: ${err.message}`); return; }
        this.handlePhotoCapture(pa.uri);
      });

      console.info(`[CameraVM] 预览已启动 (画幅=${CameraConstants.ASPECT_RATIO_LABELS[this.currentAspectRatio]})`);
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[CameraVM] 启动预览失败: ${error.message}`);
      this.notifyError(`启动预览失败: ${error.message}`);
    }
  }

  /**
   * 处理拍照回调 — 可选 C++ 原生图像后处理
   */
  private async handlePhotoCapture(photoUri: string): Promise<void> {
    try {
      // 先保存原始照片到相册
      const savedUri: string = await FileUtils.saveMediaToGallery(photoUri, 'photo');

      // 如果设置了后处理滤镜，应用 C++ 原生处理
      if (this.postProcessFilter > 0 && savedUri) {
        await this.applyNativeFilterToPhoto(savedUri);
      }

      if (savedUri && this.onPhotoCaptureCallback) {
        this.onPhotoCaptureCallback(savedUri);
      }
    } catch (e) {
      console.error(`[CameraVM] 照片处理失败: ${JSON.stringify(e)}`);
      // 即使后处理失败，仍通知原始照片已保存
      if (this.onPhotoCaptureCallback) {
        this.onPhotoCaptureCallback(photoUri);
      }
    }
  }

  /**
   * 使用 C++ 原生模块对已保存照片应用滤镜
   */
  private async applyNativeFilterToPhoto(photoUri: string): Promise<void> {
    try {
      // 1. 读取 JPEG 文件
      const srcFile = fileIo.openSync(photoUri, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(photoUri);
      const jpegBuffer = new ArrayBuffer(stat.size);
      fileIo.readSync(srcFile.fd, jpegBuffer);
      fileIo.closeSync(srcFile);

      // 2. 解码为 PixelMap 获取 RGBA 原始数据
      const imageSource = image.createImageSource(jpegBuffer);
      const pixelMap = await imageSource.createPixelMap();
      const width = pixelMap.getImageInfoSync().size.width;
      const height = pixelMap.getImageInfoSync().size.height;
      const pixelBytes = pixelMap.getPixelBytesNumber();
      const rgbaBuffer = new ArrayBuffer(pixelBytes);
      await pixelMap.readPixelsToBuffer(rgbaBuffer);

      // 3. 调用 C++ 原生滤镜处理 (原地修改)
      nativeModule.applyFilter(rgbaBuffer, width, height, this.postProcessFilter, this.postProcessStrength);
      console.info(`[CameraVM] C++ 滤镜已应用: filter=${this.postProcessFilter}, ${width}x${height}`);

      // 4. 写回 PixelMap 并重新编码为 JPEG
      await pixelMap.writeBufferToPixels(rgbaBuffer);
      const imagePacker = image.createImagePacker();
      const packOpts: image.PackingOption = {
        format: 'image/jpeg',
        quality: CameraConstants.PHOTO_QUALITY
      };
      const processedBuffer = await imagePacker.packing(pixelMap, packOpts);

      // 5. 保存处理后的照片
      const processedUri = await FileUtils.savePhotoBuffer(processedBuffer, `IMG_FILTERED_${Date.now()}`);
      console.info(`[CameraVM] 处理后照片已保存: ${processedUri}`);

      // 6. 释放资源
      pixelMap.release();
      imageSource.release();
      imagePacker.release();
    } catch (e) {
      console.error(`[CameraVM] 原生滤镜处理失败: ${JSON.stringify(e)}`);
    }
  }

  /**
   * 切换画幅比例
   */
  public async setAspectRatio(ratio: number, surfaceId: string): Promise<void> {
    if (ratio === this.currentAspectRatio && this.isSessionStarted) return;
    this.currentAspectRatio = ratio;
    if (this.isSessionStarted) {
      await this.stopPreview();
      await this.startPreview(surfaceId);
    }
  }

  public getAspectRatio(): number { return this.currentAspectRatio; }

  public async takePhoto(): Promise<void> {
    if (!this.photoOutput || !this.isSessionStarted) { this.notifyError('相机未就绪'); return; }
    try { await this.photoOutput.capture(); }
    catch (err) { const e = err as BusinessError; this.notifyError(`拍照失败: ${e.message}`); }
  }

  // ============================================================
  // 视频录制 (使用 AVRecorder + VideoOutput)
  // ============================================================

  public async startRecording(): Promise<void> {
    if (!this.captureSession || !this.isSessionStarted || this.isRecording) return;
    if (!this.cameraManager) { this.notifyError('CameraManager 未初始化'); return; }

    try {
      // 1. 创建视频输出文件
      const context = this.getContext();
      if (!context) { this.notifyError('Context 不可用'); return; }
      this.videoOutputFilePath = `${context.cacheDir}/VID_${Date.now()}.mp4`;
      const videoFile = fileIo.openSync(this.videoOutputFilePath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      this.videoOutputFileFd = videoFile.fd;

      // 2. 创建并配置 AVRecorder
      this.avRecorder = await media.createAVRecorder();

      const avConfig: media.AVRecorderConfig = {
        audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
        videoSourceType: media.VideoSourceType.VIDEO_SOURCE_TYPE_SURFACE_YUV,
        profile: media.AVRecorderProfile.AV_RECORDER_PROFILE_1080P_30,
        url: `fd://${this.videoOutputFileFd}`,
        videoConfig: {
          videoBitrate: CameraConstants.VIDEO_BITRATE,
          videoFrameWidth: CameraConstants.VIDEO_WIDTH,
          videoFrameHeight: CameraConstants.VIDEO_HEIGHT,
          videoFrameRate: CameraConstants.VIDEO_FRAME_RATE
        }
      };

      await this.avRecorder.prepare(avConfig);
      const recorderSurfaceId: string = await this.avRecorder.getInputSurface();
      console.info(`[CameraVM] AVRecorder 已准备, surfaceId=${recorderSurfaceId}`);

      // 3. 选择视频 Profile
      const cameraDevice = this.supportedCameras[this.currentCameraIndex];
      let videoProfile: camera.Profile | null = null;
      if (this.cachedVideoProfiles.length > 0) {
        videoProfile = this.selectProfile(this.cachedVideoProfiles, this.currentAspectRatio);
      }
      // 降级: 使用预览 Profile
      if (!videoProfile && this.cachedPreviewProfiles.length > 0) {
        videoProfile = this.cachedPreviewProfiles[0];
      }
      if (!videoProfile) throw new Error('无可用视频Profile');

      // 4. 创建 VideoOutput 并添加到会话
      this.videoOutput = this.cameraManager.createVideoOutput(videoProfile, recorderSurfaceId);

      // 5. 重建会话以包含 VideoOutput
      this.captureSession.beginConfig();
      if (this.cameraInput) this.captureSession.addInput(this.cameraInput);
      if (this.previewOutput) this.captureSession.addOutput(this.previewOutput);
      if (this.photoOutput) this.captureSession.addOutput(this.photoOutput);
      this.captureSession.addOutput(this.videoOutput);
      await this.captureSession.commitConfig();

      // 6. 开始录制
      await this.avRecorder.start();
      this.isRecording = true;
      console.info(`[CameraVM] 录像已开始 → ${this.videoOutputFilePath}`);
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[CameraVM] 启动录像失败: ${error.message}`);
      this.cleanupVideoResources();
      this.notifyError(`录像启动失败: ${error.message}`);
    }
  }

  public async stopRecording(): Promise<void> {
    if (!this.isRecording) return;

    try {
      // 1. 停止 AVRecorder
      if (this.avRecorder) {
        await this.avRecorder.stop();
        await this.avRecorder.release();
        this.avRecorder = null;
      }
      this.isRecording = false;
      console.info('[CameraVM] 录像已停止');

      // 2. 保存视频到相册
      if (this.videoOutputFilePath) {
        const savedUri = await FileUtils.saveMediaToGallery(this.videoOutputFilePath, 'video');
        if (savedUri && this.onVideoRecordCallback) {
          this.onVideoRecordCallback(savedUri);
        }
      }

      // 3. 从会话中移除 VideoOutput
      if (this.captureSession && this.videoOutput) {
        try {
          this.captureSession.beginConfig();
          this.captureSession.removeOutput(this.videoOutput);
          await this.captureSession.commitConfig();
        } catch (e) {
          console.warn(`[CameraVM] 移除VideoOutput失败: ${JSON.stringify(e)}`);
        }
      }

      // 4. 释放 VideoOutput
      if (this.videoOutput) {
        this.videoOutput.release();
        this.videoOutput = null;
      }

      this.cleanupVideoResources();
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[CameraVM] 停止录像失败: ${error.message}`);
    }
  }

  private cleanupVideoResources(): void {
    if (this.videoOutputFileFd >= 0) {
      try { fileIo.closeSync({ fd: this.videoOutputFileFd } as any); } catch (e) { /* ignore */ }
      this.videoOutputFileFd = -1;
    }
    if (this.avRecorder) {
      try { this.avRecorder.release(); } catch (e) { /* ignore */ }
      this.avRecorder = null;
    }
  }

  // ============================================================

  public async stopPreview(): Promise<void> {
    try {
      if (this.isRecording) await this.stopRecording();
      if (this.captureSession && this.isSessionStarted) {
        await this.captureSession.stop();
        this.isSessionStarted = false;
      }
      this.previewOutput?.release();
      this.photoOutput?.release();
      this.videoOutput?.release();
      this.captureSession?.release();
      this.cameraInput?.close();
      this.previewOutput = null;
      this.photoOutput = null;
      this.videoOutput = null;
      this.captureSession = null;
      this.cameraInput = null;
    } catch (err) { /* ignore */ }
  }

  public async switchCamera(surfaceId: string): Promise<string> {
    if (this.supportedCameras.length < 2) return '仅一个摄像头';
    await this.stopPreview();
    this.currentCameraIndex = (this.currentCameraIndex + 1) % this.supportedCameras.length;
    await this.startPreview(surfaceId);
    return '已切换摄像头';
  }

  public async setFlashMode(mode: number): Promise<void> {
    if (!this.captureSession) return;
    try {
      let fm = camera.FlashMode.FLASH_MODE_CLOSE;
      if (mode === CameraConstants.FLASH_MODE_ON) fm = camera.FlashMode.FLASH_MODE_OPEN;
      else if (mode === CameraConstants.FLASH_MODE_AUTO) fm = camera.FlashMode.FLASH_MODE_AUTO;
      this.captureSession.setFlashMode(fm);
    } catch (err) { /* ignore */ }
  }

  public async setZoom(ratio: number): Promise<void> {
    if (!this.captureSession || !this.isSessionStarted) return;
    const zoom = Math.max(CameraConstants.ZOOM_MIN, Math.min(ratio, CameraConstants.ZOOM_MAX));
    try { await this.captureSession.setZoomRatio(zoom); this.currentZoomRatio = zoom; }
    catch (err) { /* ignore */ }
  }

  public getZoom(): number { return this.currentZoomRatio; }
  public getRecordingState(): boolean { return this.isRecording; }
  public getCameraCount(): number { return this.supportedCameras.length; }

  public getCurrentCameraPosition(): camera.CameraPosition | null {
    if (this.supportedCameras.length === 0) return null;
    return this.supportedCameras[this.currentCameraIndex].cameraPosition;
  }

  public setOnPhotoCapture(c: (uri: string) => void): void { this.onPhotoCaptureCallback = c; }
  public setOnVideoRecord(c: (uri: string) => void): void { this.onVideoRecordCallback = c; }
  public setOnError(c: (error: string) => void): void { this.onErrorCallback = c; }

  private getContext(): Context | null {
    return GlobalContext.getInstance().getContext() as Context | null;
  }

  private notifyError(msg: string): void { if (this.onErrorCallback) this.onErrorCallback(msg); }

  public async release(): Promise<void> {
    await this.stopPreview();
    this.onPhotoCaptureCallback = null;
    this.onVideoRecordCallback = null;
    this.onErrorCallback = null;
  }
}
