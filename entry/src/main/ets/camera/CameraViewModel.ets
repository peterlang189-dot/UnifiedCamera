import { camera } from '@kit.CameraKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CameraConstants } from './CameraConstants';
import { FileUtils } from '../utils/FileUtils';

/**
 * 相机ViewModel — 极简版本
 * 使用 createCaptureSession() + 无参 createPreviewOutput(surfaceId)
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

  public async startPreview(surfaceId: string): Promise<void> {
    if (this.isSessionStarted) await this.stopPreview();

    try {
      if (!this.cameraManager) throw new Error('CameraManager 未初始化');
      const cameraDevice = this.supportedCameras[this.currentCameraIndex];

      // 1. CameraInput
      this.cameraInput = this.cameraManager.createCameraInput(cameraDevice);
      await this.cameraInput.open();

      // 2. 获取设备支持的 Profile
      const outputCap: camera.CameraOutputCapability =
        this.cameraManager.getSupportedOutputCapability(cameraDevice, camera.SceneMode.NORMAL_PHOTO);
      const previewProfiles: Array<camera.Profile> = outputCap.previewProfiles;
      const photoProfiles: Array<camera.Profile> = outputCap.photoProfiles;
      console.info(`[CameraVM] Preview:${previewProfiles.length} Photo:${photoProfiles.length}`);

      if (!previewProfiles || previewProfiles.length === 0) {
        throw new Error('设备不支持预览');
      }

      // 3. 创建 Session 和 Output（带 Profile）
      this.captureSession = this.cameraManager.createCaptureSession();
      this.previewOutput = this.cameraManager.createPreviewOutput(previewProfiles[0], surfaceId);
      this.photoOutput = photoProfiles.length > 0 ?
        this.cameraManager.createPhotoOutput(photoProfiles[0]) :
        this.cameraManager.createPhotoOutput();

      // 4. 配置
      this.captureSession.beginConfig();
      this.captureSession.addInput(this.cameraInput);
      this.captureSession.addOutput(this.previewOutput);
      this.captureSession.addOutput(this.photoOutput);
      await this.captureSession.commitConfig();
      await this.captureSession.start();
      this.isSessionStarted = true;

      // 4. 拍照回调
      this.photoOutput.on('photoAssetAvailable', (err: BusinessError, pa: photoAccessHelper.PhotoAsset) => {
        if (err) { console.error(`[CameraVM] photo err: ${err.message}`); return; }
        FileUtils.saveMediaToGallery(pa.uri, 'photo').then((uri: string) => {
          if (uri && this.onPhotoCaptureCallback) this.onPhotoCaptureCallback(uri);
        }).catch((e: Error) => console.error(`[CameraVM] save err: ${e.message}`));
      });

      console.info('[CameraVM] 预览已启动');
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[CameraVM] 启动预览失败: ${error.message}`);
      this.notifyError(`启动预览失败: ${error.message}`);
    }
  }

  public async takePhoto(): Promise<void> {
    if (!this.photoOutput || !this.isSessionStarted) { this.notifyError('相机未就绪'); return; }
    try { await this.photoOutput.capture(); }
    catch (err) { const e = err as BusinessError; this.notifyError(`拍照失败: ${e.message}`); }
  }

  public async startRecording(): Promise<void> {
    if (!this.captureSession || !this.isSessionStarted || this.isRecording) return;
    // 简单录像：创建 VideoOutput 并添加到现有 session
    try { this.notifyError('录像功能暂不可用'); }
    catch (err) { const e = err as BusinessError; this.notifyError(e.message); }
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
