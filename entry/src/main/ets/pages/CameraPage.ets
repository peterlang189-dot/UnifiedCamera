import { promptAction } from '@kit.ArkUI';
import { display } from '@kit.ArkUI';
import { CameraViewModel } from '../camera/CameraViewModel';
import { CameraConstants } from '../camera/CameraConstants';
import { PermissionUtils } from '../utils/PermissionUtils';
import { GlobalContext } from '../utils/GlobalContext';
import { Context } from '@kit.AbilityKit';

/**
 * 闪光灯模式数据
 */
class FlashModeItem {
  mode: number;
  text: string;

  constructor(mode: number, text: string) {
    this.mode = mode;
    this.text = text;
  }
}

/**
 * 相机主页面 — 使用 XComponentController 获取真实 surfaceId
 */
@Entry
@Component
struct CameraPage {
  @State isCameraReady: boolean = false;
  @State isRecording: boolean = false;
  @State recordingTimeText: string = '00:00';
  @State flashModeText: string = '关闭';
  @State zoomValue: number = CameraConstants.ZOOM_MIN;
  @State zoomText: string = '1.0x';
  @State hasMultipleCameras: boolean = false;
  @State timerDuration: number = 0;
  @State showTimerIndicator: boolean = false;
  @State timerCountdown: number = 0;
  @State aspectMode: number = CameraConstants.ASPECT_RATIO_4_3;
  @State previewAspectValue: number = 3 / 4;  // XComponent 宽/高

  // XComponent 控制器 - 获取真实 surface ID
  private xComponentController: XComponentController = new XComponentController();
  private cameraVM: CameraViewModel = new CameraViewModel();
  private surfaceId: string = '';
  private recordingTimerId: number = -1;
  private recordingSeconds: number = 0;
  private timerCountdownId: number = -1;
  private screenWidth: number = 0;
  private screenHeight: number = 0;
  // 启动协调：surface 与 权限/初始化 两者都就绪后才启动预览
  private surfaceReady: boolean = false;
  private permissionsGranted: boolean = false;

  private flashModes: FlashModeItem[] = [
    new FlashModeItem(CameraConstants.FLASH_MODE_OFF, '关闭'),
    new FlashModeItem(CameraConstants.FLASH_MODE_AUTO, '自动'),
    new FlashModeItem(CameraConstants.FLASH_MODE_ON, '打开'),
    new FlashModeItem(CameraConstants.FLASH_MODE_TORCH, '手电'),
  ];
  private currentFlashIndex: number = 0;

  async aboutToAppear(): Promise<void> {
    this.cameraVM.setOnPhotoCapture((uri: string) => {
      promptAction.showToast({ message: '照片已保存' });
    });
    this.cameraVM.setOnError((error: string) => {
      promptAction.showToast({ message: error, duration: 2000 });
    });

    // 获取屏幕尺寸用于计算全屏预览比例
    const displayInfo: display.Display = display.getDefaultDisplaySync();
    this.screenWidth = displayInfo.width;
    this.screenHeight = displayInfo.height;

    // 同步初始化 CameraManager（不依赖权限），避免与 XComponent.onLoad 时序竞态
    const context: Context | null = GlobalContext.getInstance().getContext() as Context | null;
    if (context) {
      this.cameraVM.initCamera(context);
      this.hasMultipleCameras = this.cameraVM.getCameraCount() > 1;
    }

    // 请求权限
    const hasPermission: boolean = await PermissionUtils.checkAllPermissions();
    if (!hasPermission) {
      const granted: boolean = await PermissionUtils.requestAllPermissions();
      if (!granted) {
        promptAction.showToast({ message: '需要相机和麦克风权限' });
        return;
      }
    }
    this.permissionsGranted = true;
    this.tryStartPreview();
  }

  /**
   * 协调启动：surface 与 权限/初始化 都就绪后才启动预览
   * 避免时序竞态导致 "CameraManager 未初始化"
   */
  private tryStartPreview(): void {
    if (this.isCameraReady) return;
    if (!this.surfaceReady) return;
    if (!this.permissionsGranted) return;
    if (!this.surfaceId) return;

    this.cameraVM.startPreview(this.surfaceId).then(() => {
      this.isCameraReady = true;
      console.info('[CameraPage] 相机就绪');
    }).catch((err: Error) => {
      console.error(`[CameraPage] 启动失败: ${err.message}`);
    });
  }

  async aboutToDisappear(): Promise<void> {
    this.clearRecordingTimer();
    this.clearTimerCountdown();
    await this.cameraVM.release();
  }

  // ===== 操作 =====

  private async onTakePhoto(): Promise<void> {
    if (!this.isCameraReady || this.isRecording) return;
    if (this.timerDuration > 0) {
      this.showTimerIndicator = true;
      this.timerCountdown = this.timerDuration;
      this.timerCountdownId = setInterval(() => {
        this.timerCountdown--;
        if (this.timerCountdown <= 0) {
          this.clearTimerCountdown();
          this.showTimerIndicator = false;
          this.cameraVM.takePhoto();
        }
      }, 1000);
      return;
    }
    await this.cameraVM.takePhoto();
  }

  private async onToggleRecording(): Promise<void> {
    if (!this.isCameraReady) return;
    if (this.isRecording) {
      this.isRecording = false;
      this.clearRecordingTimer();
      await this.cameraVM.stopRecording();
    } else {
      this.isRecording = true;
      this.recordingSeconds = 0;
      this.recordingTimeText = '00:00';
      this.startRecordingTimer();
      await this.cameraVM.startRecording();
    }
  }

  private async onSwitchCamera(): Promise<void> {
    if (!this.isCameraReady || this.isRecording) return;
    this.isCameraReady = false;
    const msg: string = await this.cameraVM.switchCamera(this.surfaceId);
    promptAction.showToast({ message: msg });
    this.isCameraReady = true;
  }

  private async onFlashModeChange(): Promise<void> {
    this.currentFlashIndex = (this.currentFlashIndex + 1) % this.flashModes.length;
    const item: FlashModeItem = this.flashModes[this.currentFlashIndex];
    this.flashModeText = item.text;
    await this.cameraVM.setFlashMode(item.mode);
  }

  private async onZoomChange(value: number): Promise<void> {
    this.zoomValue = value;
    this.zoomText = `${value.toFixed(1)}x`;
    await this.cameraVM.setZoom(value);
  }

  private onTimerToggle(): void {
    const durations: number[] = CameraConstants.TIMER_DURATIONS;
    const currentIdx: number = durations.indexOf(this.timerDuration);
    const nextIdx: number = (currentIdx + 1) % durations.length;
    this.timerDuration = durations[nextIdx];
    const msg: string = this.timerDuration === 0 ? '定时拍照: 关闭' : `定时拍照: ${this.timerDuration}s`;
    promptAction.showToast({ message: msg });
  }

  /**
   * 切换画幅比例 (全屏 / 4:3 / 1:1)
   * 更新预览显示比例并重建相机会话使用匹配的 Profile
   */
  private async onAspectRatioChange(ratio: number): Promise<void> {
    if (ratio === this.aspectMode) return;
    this.aspectMode = ratio;

    // 计算预览显示比例 (宽/高)
    if (ratio === CameraConstants.ASPECT_RATIO_FULL) {
      this.previewAspectValue = this.screenWidth / this.screenHeight;
    } else if (ratio === CameraConstants.ASPECT_RATIO_4_3) {
      this.previewAspectValue = 3 / 4;
    } else {
      this.previewAspectValue = 1.0;
    }

    promptAction.showToast({ message: `画幅: ${CameraConstants.ASPECT_RATIO_LABELS[ratio]}` });

    // 重建相机会话
    if (this.surfaceId) {
      this.isCameraReady = false;
      await this.cameraVM.setAspectRatio(ratio, this.surfaceId);
      this.isCameraReady = true;
    }
  }

  // ===== 计时器 =====
  private startRecordingTimer(): void {
    this.recordingTimerId = setInterval(() => {
      this.recordingSeconds++;
      const min: string = Math.floor(this.recordingSeconds / 60).toString().padStart(2, '0');
      const sec: string = (this.recordingSeconds % 60).toString().padStart(2, '0');
      this.recordingTimeText = `${min}:${sec}`;
    }, 1000);
  }
  private clearRecordingTimer(): void { if (this.recordingTimerId !== -1) { clearInterval(this.recordingTimerId); this.recordingTimerId = -1; } }
  private clearTimerCountdown(): void { if (this.timerCountdownId !== -1) { clearInterval(this.timerCountdownId); this.timerCountdownId = -1; } }

  // ===== UI =====
  build() {
    Stack() {
      // 相机预览 — 使用 XComponentController，宽高比跟随所选画幅
      XComponent({
        id: 'cameraPreview',
        type: XComponentType.SURFACE,
        controller: this.xComponentController,
        libraryname: 'camera'
      })
        .width('100%')
        .aspectRatio(this.previewAspectValue)
        .backgroundColor(Color.Black)
        .onLoad(() => {
          // 获取真实的 native surface ID
          this.surfaceId = this.xComponentController.getXComponentSurfaceId();
          this.surfaceReady = true;
          console.info(`[CameraPage] XComponent loaded, surfaceId: ${this.surfaceId}`);
          // 协调启动预览（权限/初始化就绪后才会真正启动）
          this.tryStartPreview();
        })
        .onDestroy(() => {
          console.info('[CameraPage] XComponent destroyed');
        })

      // 顶部工具栏
      Column() {
        Row() {
          Button(this.flashModeText)
            .fontSize(12).fontColor(Color.White)
            .width(44).height(32).borderRadius(16)
            .backgroundColor('rgba(0,0,0,0.4)')
            .onClick(() => this.onFlashModeChange())

          Blank()

          if (this.isRecording) {
            Row() {
              Circle({ width: 7, height: 7 }).fill(Color.Red)
              Text(this.recordingTimeText).fontSize(16).fontColor(Color.White).margin({ left: 4 })
            }
            .padding({ left: 10, right: 10, top: 3, bottom: 3 })
            .borderRadius(10).backgroundColor('rgba(255,0,0,0.4)')
          }

          Blank()

          Button(this.timerDuration === 0 ? '定时' : `${this.timerDuration}s`)
            .fontSize(12)
            .fontColor(this.timerDuration > 0 ? '#FFD700' : Color.White)
            .width(44).height(32).borderRadius(16)
            .backgroundColor('rgba(0,0,0,0.4)')
            .onClick(() => this.onTimerToggle())

          Blank()

          Button('切换')
            .fontSize(12).fontColor(Color.White)
            .width(44).height(32).borderRadius(16)
            .backgroundColor('rgba(0,0,0,0.4)')
            .visibility(this.hasMultipleCameras ? Visibility.Visible : Visibility.Hidden)
            .onClick(() => this.onSwitchCamera())
        }
        .width('100%').padding({ left: 12, right: 12 })
      }
      .position({ x: 0, y: 0 }).width('100%').padding({ top: 40 })

      // 画幅选择器 (全屏 / 4:3 / 1:1)
      Row({ space: 6 }) {
        ForEach(CameraConstants.ASPECT_RATIO_LABELS, (label: string, idx: number) => {
          Text(label)
            .fontSize(12)
            .fontColor(this.aspectMode === idx ? Color.Black : Color.White)
            .fontWeight(this.aspectMode === idx ? FontWeight.Bold : FontWeight.Normal)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .borderRadius(12)
            .backgroundColor(this.aspectMode === idx ? '#FFD700' : 'rgba(0,0,0,0.4)')
            .onClick(() => this.onAspectRatioChange(idx))
        }, (label: string, idx: number) => `${label}-${idx}`)
      }
      .position({ x: '50%', y: 90 })
      .translate({ x: '-50%' })

      // 定时倒计时
      if (this.showTimerIndicator) {
        Column() {
          Text(`${this.timerCountdown}`).fontSize(80).fontColor(Color.White).fontWeight(FontWeight.Bold)
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        .backgroundColor('rgba(0,0,0,0.3)')
      }

      // 底部控制栏
      Column() {
        Row() {
          Text('W').fontSize(10).fontColor(Color.White).opacity(0.5)
          Slider({
            value: this.zoomValue,
            min: CameraConstants.ZOOM_MIN,
            max: CameraConstants.ZOOM_MAX,
            step: CameraConstants.ZOOM_STEP,
            style: SliderStyle.OutSet,
          })
            .width('70%').blockColor(Color.White)
            .trackColor('rgba(255,255,255,0.3)').selectedColor(Color.White)
            .onChange((value: number) => this.onZoomChange(value))
          Text('T').fontSize(10).fontColor(Color.White).opacity(0.5)
        }
        .width('90%').justifyContent(FlexAlign.Center).margin({ bottom: 8 })

        Row() {
          Button() {
            Column().width(44).height(44).borderRadius(4)
              .border({ width: 1, color: 'rgba(255,255,255,0.5)' })
              .backgroundColor('rgba(255,255,255,0.15)')
          }.width(48).height(48).backgroundColor(Color.Transparent)

          Blank()

          Button() {
            if (this.isRecording) {
              Rect().width(22).height(22).fill(Color.Red).borderRadius(3)
            } else {
              Circle().width(64).height(64).fill(Color.White)
            }
          }
          .width(this.isRecording ? 66 : 76).height(this.isRecording ? 66 : 76)
          .borderRadius(this.isRecording ? 10 : 38)
          .backgroundColor(this.isRecording ? '#FF4444' : Color.Transparent)
          .border({ width: 3, color: Color.White, radius: 38 })
          .onClick(() => {
            if (this.isRecording) { this.onToggleRecording(); }
            else { this.onTakePhoto(); }
          })
          .gesture(
            LongPressGesture({ repeat: false, duration: 500 })
              .onAction(() => { if (!this.isRecording) this.onToggleRecording(); })
              .onActionEnd(() => { if (this.isRecording) this.onToggleRecording(); })
          )

          Blank()
          Row().width(48).height(48)
        }
        .width('100%').justifyContent(FlexAlign.SpaceAround).alignItems(VerticalAlign.Center)

        Text(this.isRecording ? '录像中...' : '点击拍照 | 长按录像')
          .fontSize(11).fontColor(Color.White).opacity(0.4)
          .margin({ top: 10, bottom: 6 })
      }
      .position({ x: 0, y: '100%' }).translate({ x: 0, y: -210 }).width('100%')

      // 加载提示
      if (!this.isCameraReady) {
        Column() {
          LoadingProgress().width(36).height(36).color(Color.White)
          Text('启动相机...').fontSize(14).fontColor(Color.White).margin({ top: 12 })
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        .backgroundColor(Color.Black)
      }
    }
    .width('100%').height('100%').backgroundColor(Color.Black)
  }
}
