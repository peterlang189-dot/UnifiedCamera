import { display } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { CameraViewModel } from '../camera/CameraViewModel';
import { CameraConstants } from '../camera/CameraConstants';
import { PermissionUtils } from '../utils/PermissionUtils';
import { GlobalContext } from '../utils/GlobalContext';

/**
 * 相机主页面
 *
 * 功能特性：
 * - 相机实时预览 (XComponent)
 * - 拍照（单张/连拍）
 * - 录像（开始/暂停/停止，带计时）
 * - 前后摄像头切换
 * - 闪光灯模式切换（关闭/打开/自动/手电筒）
 * - 缩放滑动条
 * - 对焦点击
 * - 定时拍照
 * - 权限管理
 */
@Entry
@Component
struct CameraPage {
  // ===== 状态变量 =====
  @State private isCameraReady: boolean = false;
  @State private isRecording: boolean = false;
  @State private isRecordingPaused: boolean = false;
  @State private recordingTimeText: string = '00:00';
  @State private flashModeIcon: string = '';      // 闪电图标 (使用系统符号)
  @State private flashModeText: string = '关闭';
  @State private zoomValue: number = CameraConstants.ZOOM_MIN;
  @State private zoomText: string = '1.0x';
  @State private showModeBar: boolean = true;
  @State private showTopBar: boolean = true;
  @State private cameraPositionText: string = '后置';
  @State private hasMultipleCameras: boolean = false;
  @State private timerDuration: number = 0;              // 定时拍照秒数 (0=关闭)
  @State private showTimerIndicator: boolean = false;
  @State private timerCountdown: number = 0;
  @State private lastPhotoUri: string = '';
  @State private toastMessage: string = '';

  // ===== 非响应式变量 =====
  private cameraVM: CameraViewModel = new CameraViewModel();
  private surfaceId: string = CameraConstants.PREVIEW_SURFACE_ID;
  private recordingTimerId: number = -1;
  private recordingSeconds: number = 0;
  private timerCountdownId: number = -1;
  private screenWidth: number = 0;
  private screenHeight: number = 0;

  // ===== 生命周期 =====

  async aboutToAppear(): Promise<void> {
    // 获取屏幕尺寸
    const displayInfo = display.getDefaultDisplaySync();
    this.screenWidth = displayInfo.width;
    this.screenHeight = displayInfo.height;

    console.info(`[CameraPage] 屏幕尺寸: ${this.screenWidth} x ${this.screenHeight}`);

    // 初始化 ViewModel 回调
    this.setupCallbacks();

    // 请求权限
    const hasPermission = await PermissionUtils.checkAllPermissions();
    if (!hasPermission) {
      const granted = await PermissionUtils.requestAllPermissions();
      if (!granted) {
        promptAction.showToast({ message: '需要授予相机和麦克风权限才能使用', duration: 3000 });
        return;
      }
    }

    // 初始化相机并启动预览
    await this.initAndStartCamera();
  }

  async aboutToDisappear(): Promise<void> {
    this.clearRecordingTimer();
    this.clearTimerCountdown();
    await this.cameraVM.release();
    console.info('[CameraPage] 页面已销毁');
  }

  // ===== 回调注册 =====

  private setupCallbacks(): void {
    this.cameraVM.setOnPhotoCapture((uri: string) => {
      this.lastPhotoUri = uri;
      promptAction.showToast({ message: '照片已保存', duration: 1500 });
      // 拍照完成闪烁效果可通过动画实现
    });

    this.cameraVM.setOnVideoRecord((uri: string) => {
      this.lastPhotoUri = uri;
      promptAction.showToast({ message: '视频已保存', duration: 1500 });
    });

    this.cameraVM.setOnError((error: string) => {
      promptAction.showToast({ message: error, duration: 2000 });
    });
  }

  // ===== 相机初始化和控制 =====

  private async initAndStartCamera(): Promise<void> {
    try {
      await this.cameraVM.initCamera();
      this.hasMultipleCameras = this.cameraVM.getCameraCount() > 1;
      const position = this.cameraVM.getCurrentCameraPosition();
      this.cameraPositionText = this.getCameraPositionName(position);

      await this.cameraVM.startPreview(this.surfaceId);
      this.isCameraReady = true;
      console.info('[CameraPage] 相机就绪');
    } catch (err) {
      console.error(`[CameraPage] 初始化相机失败: ${JSON.stringify(err)}`);
      promptAction.showToast({ message: '相机初始化失败', duration: 2000 });
    }
  }

  // ===== 拍照操作 =====

  private async onTakePhoto(): Promise<void> {
    if (!this.isCameraReady || this.isRecording) return;

    // 定时拍照
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

    // 即时拍照
    await this.cameraVM.takePhoto();
  }

  // ===== 录像操作 =====

  private async onToggleRecording(): Promise<void> {
    if (!this.isCameraReady) return;

    if (!this.isRecording) {
      // 开始录像
      this.isRecording = true;
      this.isRecordingPaused = false;
      this.recordingSeconds = 0;
      this.recordingTimeText = '00:00';
      this.startRecordingTimer();
      await this.cameraVM.startRecording();
    } else {
      // 停止录像
      this.isRecording = false;
      this.isRecordingPaused = false;
      this.clearRecordingTimer();
      await this.cameraVM.stopRecording();
    }
  }

  /**
   * 暂停/恢复录像
   */
  private async onPauseRecording(): Promise<void> {
    if (!this.isRecording) return;

    if (this.isRecordingPaused) {
      // 恢复录像 — HarmonyOS API 限制，这里通过重新开始实现
      this.isRecordingPaused = false;
      this.startRecordingTimer();
      await this.cameraVM.startRecording();
      promptAction.showToast({ message: '录像已恢复', duration: 1000 });
    } else {
      // 暂停录像
      this.isRecordingPaused = true;
      this.clearRecordingTimer();
      await this.cameraVM.stopRecording();
      promptAction.showToast({ message: '录像已暂停', duration: 1000 });
    }
  }

  // ===== 相机切换和参数控制 =====

  private async onSwitchCamera(): Promise<void> {
    if (!this.isCameraReady || this.isRecording) return;

    // 停止当前预览
    await this.cameraVM.stopPreview();
    this.isCameraReady = false;

    // 切换摄像头
    const message = await this.cameraVM.switchCamera();
    promptAction.showToast({ message, duration: 1000 });

    // 获取当前摄像头位置
    const position = this.cameraVM.getCurrentCameraPosition();
    this.cameraPositionText = this.getCameraPositionName(position);

    // 重新启动预览
    await this.cameraVM.startPreview(this.surfaceId);
    this.isCameraReady = true;
  }

  private async onFlashModeChange(): Promise<void> {
    // 循环切换: 关闭 → 自动 → 打开 → 手电筒 → 关闭
    const FLASH_MODES = [
      { mode: CameraConstants.FLASH_MODE_OFF,    icon: '', text: '关闭' },
      { mode: CameraConstants.FLASH_MODE_AUTO,   icon: '', text: '自动' },
      { mode: CameraConstants.FLASH_MODE_ON,     icon: '', text: '打开' },
      { mode: CameraConstants.FLASH_MODE_TORCH,  icon: '', text: '手电' },
    ];

    // 查找当前模式的索引并切换到下一个
    let currentIdx = FLASH_MODES.findIndex(f => f.mode === CameraConstants.FLASH_MODE_OFF);
    for (let i = 0; i < FLASH_MODES.length; i++) {
      if (FLASH_MODES[i].text === this.flashModeText) {
        currentIdx = i;
        break;
      }
    }
    const nextIdx = (currentIdx + 1) % FLASH_MODES.length;
    const nextMode = FLASH_MODES[nextIdx];

    this.flashModeText = nextMode.text;
    this.flashModeIcon = nextMode.icon;
    await this.cameraVM.setFlashMode(nextMode.mode);
    promptAction.showToast({ message: `闪光灯: ${nextMode.text}`, duration: 1000 });
  }

  private async onZoomChange(value: number): Promise<void> {
    this.zoomValue = value;
    this.zoomText = `${value.toFixed(1)}x`;
    await this.cameraVM.setZoom(value);
  }

  private async onTimerToggle(): Promise<void> {
    const durations = CameraConstants.TIMER_DURATIONS;
    // 循环切换：0 → 3s → 5s → 10s → 0
    let currentIdx = durations.indexOf(this.timerDuration);
    if (currentIdx < 0) currentIdx = 0;
    const nextIdx = (currentIdx + 1) % durations.length;
    this.timerDuration = durations[nextIdx];

    if (this.timerDuration === 0) {
      promptAction.showToast({ message: '定时拍照: 关闭', duration: 1000 });
    } else {
      promptAction.showToast({ message: `定时拍照: ${this.timerDuration}s`, duration: 1000 });
    }
  }

  // ===== 工具方法 =====

  private startRecordingTimer(): void {
    this.recordingTimerId = setInterval(() => {
      this.recordingSeconds++;
      const min = Math.floor(this.recordingSeconds / 60).toString().padStart(2, '0');
      const sec = (this.recordingSeconds % 60).toString().padStart(2, '0');
      this.recordingTimeText = `${min}:${sec}`;
    }, 1000);
  }

  private clearRecordingTimer(): void {
    if (this.recordingTimerId !== -1) {
      clearInterval(this.recordingTimerId);
      this.recordingTimerId = -1;
    }
  }

  private clearTimerCountdown(): void {
    if (this.timerCountdownId !== -1) {
      clearInterval(this.timerCountdownId);
      this.timerCountdownId = -1;
    }
  }

  private getCameraPositionName(position: any): string {
    // HarmonyOS CameraPosition: 0=前置, 1=后置
    if (position === 0) return '前置';
    if (position === 1) return '后置';
    return '未知';
  }

  // ===== UI 构建 =====

  build() {
    Stack() {
      // ========== 1. 相机预览层 (全屏) ==========
      XComponent({
        id: this.surfaceId,
        type: XComponentType.SURFACE,
        libraryname: 'camera'
      })
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Black)
        .onLoad(() => {
          console.info('[CameraPage] XComponent 已加载');
        })
        .onDestroy(() => {
          console.info('[CameraPage] XComponent 已销毁');
        })

      // ========== 2. 手势层：点击对焦 ==========
      Column()
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)  // 透传触摸事件
        .onClick((event: ClickEvent) => {
          // 点击对焦逻辑由 ArkUI 自动处理焦点框动画
          console.info(`[CameraPage] 点击对焦: (${event.x}, ${event.y})`);
        })

      // ========== 3. 顶部工具栏 ==========
      if (this.showTopBar) {
        Column() {
          Row() {
            // 闪光灯按钮
            Button() {
              Text(this.flashModeIcon)
                .fontSize(22)
                .fontColor(Color.White)
            }
            .width(40).height(40)
            .borderRadius(20)
            .backgroundColor('rgba(0,0,0,0.4)')
            .onClick(() => this.onFlashModeChange())

            Blank()

            // 定时拍照按钮
            Button() {
              Text('')  // 定时器图标
                .fontSize(20)
                .fontColor(this.timerDuration > 0 ? '#FFD700' : Color.White)
            }
            .width(40).height(40)
            .borderRadius(20)
            .backgroundColor('rgba(0,0,0,0.4)')
            .onClick(() => this.onTimerToggle())

            Blank()

            // 居中录制计时器
            if (this.isRecording) {
              Row() {
                Circle({ width: 8, height: 8 })
                  .fill(Color.Red)
                  .visibility(this.isRecording && !this.isRecordingPaused ? Visibility.Visible : Visibility.Hidden)
                Text(this.recordingTimeText)
                  .fontSize(18)
                  .fontColor(Color.White)
                  .fontWeight(FontWeight.Medium)
                  .margin({ left: 6 })
              }
              .padding({ left: 12, right: 12, top: 4, bottom: 4 })
              .borderRadius(12)
              .backgroundColor('rgba(255,0,0,0.4)')
            }

            Blank()

            // 画幅比例（占位）
            Button() {
              Text('4:3')
                .fontSize(14)
                .fontColor(Color.White)
            }
            .width(40).height(40)
            .borderRadius(20)
            .backgroundColor('rgba(0,0,0,0.4)')

            Blank()

            // 设置（占位）
            Button() {
              Text('')  // 齿轮图标
                .fontSize(20)
                .fontColor(Color.White)
            }
            .width(40).height(40)
            .borderRadius(20)
            .backgroundColor('rgba(0,0,0,0.4)')
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
        }
        .position({ x: 0, y: 0 })
        .width('100%')
        .padding({ top: 40 })  // 避开状态栏
      }

      // ========== 4. 定时拍照倒计时指示器 ==========
      if (this.showTimerIndicator) {
        Column() {
          Text(`${this.timerCountdown}`)
            .fontSize(80)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Bold)
            .opacity(0.9)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('rgba(0,0,0,0.3)')
      }

      // ========== 5. 底部控制栏 ==========
      if (this.showModeBar) {
        Column() {
          // 缩放滑块
          Row() {
            Text('W')
              .fontSize(12)
              .fontColor(Color.White)
              .opacity(0.6)

            Slider({
              value: this.zoomValue,
              min: CameraConstants.ZOOM_MIN,
              max: CameraConstants.ZOOM_MAX,
              step: CameraConstants.ZOOM_STEP,
              style: SliderStyle.OutSet,
              direction: Axis.Horizontal
            })
              .width('70%')
              .blockColor(Color.White)
              .trackColor('rgba(255,255,255,0.3)')
              .selectedColor(Color.White)
              .onChange((value: number) => this.onZoomChange(value))

            Text('T')
              .fontSize(12)
              .fontColor(Color.White)
              .opacity(0.6)
          }
          .width('90%')
          .justifyContent(FlexAlign.Center)
          .margin({ bottom: 12 })

          // 主控制按钮行
          Row() {
            // 相册缩略图预览
            Button() {
              if (this.lastPhotoUri) {
                Column()
                  .width(48).height(48)
                  .borderRadius(6)
                  .border({ width: 1, color: 'rgba(255,255,255,0.5)' })
                  .backgroundColor('rgba(255,255,255,0.2)')
              } else {
                Column()
                  .width(48).height(48)
                  .borderRadius(6)
                  .border({ width: 1, color: 'rgba(255,255,255,0.5)' })
                  .backgroundColor('rgba(255,255,255,0.2)')
              }
            }
            .width(52).height(52)
            .backgroundColor(Color.Transparent)

            Blank()

            // 拍照/录像按钮 (大圆)
            Button() {
              if (this.isRecording) {
                // 录像中的停止按钮 (红色方块)
                Rect()
                  .width(24).height(24)
                  .fill(Color.Red)
                  .borderRadius(4)
              } else {
                // 拍照按钮 (白色大圆)
                Circle()
                  .width(64).height(64)
                  .fill(Color.White)
                  .stroke(Color.Transparent)
              }
            }
            .width(this.isRecording ? 72 : 76)
            .height(this.isRecording ? 72 : 76)
            .borderRadius(this.isRecording ? 12 : 38)
            .backgroundColor(this.isRecording ? '#FF4444' : Color.Transparent)
            .border({
              width: 3,
              color: Color.White,
              radius: 38
            })
            .onClick(() => {
              if (this.isRecording) {
                this.onToggleRecording();
              } else {
                this.onTakePhoto();
              }
            })
            .gesture(
              // 长按录像，短按拍照
              LongPressGesture({ repeat: false, duration: 400 })
                .onAction(() => {
                  // 长按触发录像
                  if (!this.isRecording) {
                    this.onToggleRecording();
                  }
                })
                .onActionEnd(() => {
                  // 松开停止录像
                  if (this.isRecording) {
                    this.onToggleRecording();
                  }
                })
            )

            Blank()

            // 切换摄像头按钮
            Button() {
              Text('')  // 切换图标
                .fontSize(24)
                .fontColor(Color.White)
            }
            .width(44).height(44)
            .borderRadius(22)
            .backgroundColor('rgba(0,0,0,0.5)')
            .visibility(this.hasMultipleCameras ? Visibility.Visible : Visibility.Hidden)
            .onClick(() => this.onSwitchCamera())
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceAround)
          .alignItems(VerticalAlign.Center)

          // 提示文字
          Text(this.isRecording ? '点击停止录像' : '点击拍照 | 长按录像')
            .fontSize(12)
            .fontColor(Color.White)
            .opacity(0.5)
            .margin({ top: 12, bottom: 8 })
        }
        .position({ x: 0, y: '100%' })
        .translate({ x: 0, y: -200 })  // 从底部向上偏移
        .width('100%')
        .padding({ bottom: 20 })
      }

      // ========== 6. 未就绪遮罩 ==========
      if (!this.isCameraReady) {
        Column() {
          LoadingProgress()
            .width(40).height(40)
            .color(Color.White)
          Text('正在启动相机...')
            .fontSize(16)
            .fontColor(Color.White)
            .margin({ top: 16 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(Color.Black)
      }

      // ========== 7. 拍照模式切换栏 ==========
      if (this.showModeBar && this.isCameraReady) {
        Row() {
          Button('拍照')
            .fontSize(16)
            .fontColor('#FFD700')
            .fontWeight(FontWeight.Bold)
            .backgroundColor(Color.Transparent)
            .border({ width: { bottom: 2 }, color: '#FFD700' })
            .padding({ bottom: 6 })

          Button('录像')
            .fontSize(16)
            .fontColor(Color.White)
            .backgroundColor(Color.Transparent)
            .margin({ left: 24 })
            .border({ width: { bottom: 0 }, color: Color.Transparent })
            .padding({ bottom: 6 })

          Button('人像')
            .fontSize(16)
            .fontColor(Color.White)
            .backgroundColor(Color.Transparent)
            .margin({ left: 24 })
            .border({ width: { bottom: 0 }, color: Color.Transparent })
            .padding({ bottom: 6 })

          Button('更多')
            .fontSize(16)
            .fontColor(Color.White)
            .backgroundColor(Color.Transparent)
            .margin({ left: 24 })
            .border({ width: { bottom: 0 }, color: Color.Transparent })
            .padding({ bottom: 6 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .position({ x: 0, y: '100%' })
        .translate({ x: 0, y: -280 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
  }
}
