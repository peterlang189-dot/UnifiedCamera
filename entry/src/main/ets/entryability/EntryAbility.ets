import { UIAbility, Want, AbilityConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { GlobalContext } from '../utils/GlobalContext';

/**
 * 应用入口 Ability
 * 负责初始化全局上下文和设置主窗口
 */
export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    console.info('[EntryAbility] onCreate');
    // 初始化全局上下文，用于跨页面共享数据
    GlobalContext.getInstance().setContext(this.context);
  }

  onDestroy(): void {
    console.info('[EntryAbility] onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    console.info('[EntryAbility] onWindowStageCreate');

    // 设置主窗口内容为 CameraPage
    windowStage.loadContent('pages/CameraPage', (err) => {
      if (err.code) {
        console.error(`[EntryAbility] 加载页面失败: ${JSON.stringify(err)}`);
        return;
      }
      console.info('[EntryAbility] 页面加载成功');
    });

    // 配置窗口属性：全屏、保持常亮、隐藏状态栏
    windowStage.getMainWindow().then((mainWindow: window.Window) => {
      mainWindow.setWindowLayoutFullScreen(true);
      mainWindow.setWindowKeepScreenOn(true);
    }).catch((err: Error) => {
      console.error(`[EntryAbility] 窗口配置失败: ${JSON.stringify(err)}`);
    });
  }

  onWindowStageDestroy(): void {
    console.info('[EntryAbility] onWindowStageDestroy');
  }

  onForeground(): void {
    console.info('[EntryAbility] onForeground');
  }

  onBackground(): void {
    console.info('[EntryAbility] onBackground');
  }
}
