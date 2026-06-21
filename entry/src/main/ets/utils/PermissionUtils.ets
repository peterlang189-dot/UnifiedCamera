import { abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { GlobalContext } from './GlobalContext';

/**
 * 权限管理工具类
 * 负责检查和请求相机、麦克风、媒体读写权限
 */
export class PermissionUtils {
  // 所需权限列表
  static readonly REQUIRED_PERMISSIONS: Array<Permissions> = [
    'ohos.permission.CAMERA',
    'ohos.permission.MICROPHONE',
    'ohos.permission.WRITE_MEDIA',
    'ohos.permission.READ_MEDIA'
  ];

  /**
   * 检查所有必需权限是否已授权
   * @returns Promise<boolean> 全部授权返回 true
   */
  public static async checkAllPermissions(): Promise<boolean> {
    const atManager = abilityAccessCtrl.createAtManager();
    const context = GlobalContext.getInstance().getContext();

    if (!context) {
      console.error('[PermissionUtils] Context 未初始化!');
      return false;
    }

    for (const permission of PermissionUtils.REQUIRED_PERMISSIONS) {
      try {
        const grantStatus = await atManager.checkAccessToken(
          context as any,
          permission
        );
        if (grantStatus !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
          console.warn(`[PermissionUtils] 权限未授予: ${permission}`);
          return false;
        }
      } catch (err) {
        console.error(`[PermissionUtils] 检查权限失败: ${permission}, err: ${JSON.stringify(err)}`);
        return false;
      }
    }
    console.info('[PermissionUtils] 所有权限已授权');
    return true;
  }

  /**
   * 请求所有必需权限
   * @returns Promise<boolean> 全部授权返回 true
   */
  public static async requestAllPermissions(): Promise<boolean> {
    const atManager = abilityAccessCtrl.createAtManager();
    const context = GlobalContext.getInstance().getContext();

    if (!context) {
      console.error('[PermissionUtils] Context 未初始化!');
      return false;
    }

    try {
      const result = await atManager.requestPermissionsFromUser(
        context as any,
        PermissionUtils.REQUIRED_PERMISSIONS
      );

      // 检查所有权限是否已被授予
      if (result.authResults) {
        const allGranted = result.authResults.every(
          (status: number) => status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
        );
        if (allGranted) {
          console.info('[PermissionUtils] 用户已授予所有权限');
          return true;
        } else {
          console.warn('[PermissionUtils] 部分权限被拒绝');
          return false;
        }
      }
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[PermissionUtils] 请求权限失败: ${error.message}`);
    }
    return false;
  }

  /**
   * 检查单个权限
   * @param permission 权限名
   * @returns Promise<boolean>
   */
  public static async checkPermission(permission: Permissions): Promise<boolean> {
    const atManager = abilityAccessCtrl.createAtManager();
    const context = GlobalContext.getInstance().getContext();
    if (!context) return false;

    try {
      const grantStatus = await atManager.checkAccessToken(context as any, permission);
      return grantStatus === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (err) {
      console.error(`[PermissionUtils] 检查权限失败: ${permission}`);
      return false;
    }
  }
}
