import { camera } from '@kit.CameraKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CameraConstants } from './CameraConstants';
import { FileUtils } from '../utils/FileUtils';

/**
 * 相机ViewModel — 支持画幅切换 (4:3 / 1:1 / 全屏)
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

  // 缓存设备支持的 Profile
  private cachedPreviewProfiles: Array<camera.Profile> = [];
  private cachedPhotoProfiles: Array<camera.Profile> = [];

  private onPhotoCaptureCallback: ((uri: string) => void) | null = null;
  private onVideoRecordCallback: ((uri: string) => void) | null = null;
  private onErrorCallback: ((error: string) => void) | null = null;

  public initCamera(context: Context): void {
    try {
      this.cameraManager = camera.getCameraManager(context);
      this.supportedCameras = this.cameraManager.getSupportedCameras();
      if (this.supportedCameras.length === 0) throw new Error('无可用摄像头');
      console.info(`[CameraVM] ${this.supportedCameras.length}个摄像头`);
    } catch (err) {
      const error = err as BusinessError;
      this.notifyError(`相机初始化失败: ${error.message}`);
    }
  }

  /**
   * 从 Profile 列表中选择最接近目标比例的 Profile
   * 优先选择比例最接近的，比例相同时选择分辨率最高的
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
      // 比例更接近，或比例相同但分辨率更高
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

      // 6. 拍照回调
      this.photoOutput.on('photoAssetAvailable', (err: BusinessError, pa: photoAccessHelper.PhotoAsset) => {
        if (err) { console.error(`[CameraVM] photo err: ${err.message}`); return; }
        FileUtils.saveMediaToGallery(pa.uri, 'photo').then((uri: string) => {
          if (uri && this.onPhotoCaptureCallback) this.onPhotoCaptureCallback(uri);
        }).catch((e: Error) => console.error(`[CameraVM] save err: ${e.message}`));
      });

      console.info(`[CameraVM] 预览已启动 (画幅=${CameraConstants.ASPECT_RATIO_LABELS[this.currentAspectRatio]})`);
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[CameraVM] 启动预览失败: ${error.message}`);
      this.notifyError(`启动预览失败: ${error.message}`);
    }
  }

  /**
   * 切换画幅比例 — 重建会话使用匹配的 Profile
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

  public async startRecording(): Promise<void> {
    if (!this.captureSession || !this.isSessionStarted || this.isRecording) return;
    this.notifyError('录像功能暂不可用');
  }

  public async stopRecording(): Promise<void> {
    if (!this.isRecording) return;
    this.isRecording = false;
  }

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

  private notifyError(msg: string): void { if (this.onErrorCallback) this.onErrorCallback(msg); }

  public async release(): Promise<void> {
    await this.stopPreview();
    this.onPhotoCaptureCallback = null;
    this.onVideoRecordCallback = null;
    this.onErrorCallback = null;
  }
}
