import { abilityAccessCtrl, Permissions, Context } from '@kit.AbilityKit';
import { bundleManager } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { GlobalContext } from './GlobalContext';

/**
 * 权限管理工具类 — SDK 26 兼容版
 */
export class PermissionUtils {
  static readonly REQUIRED_PERMISSIONS: Array<Permissions> = [
    'ohos.permission.CAMERA',
    'ohos.permission.MICROPHONE',
    'ohos.permission.WRITE_IMAGEVIDEO',
    'ohos.permission.READ_IMAGEVIDEO'
  ];

  /**
   * 获取应用 Token ID
   */
  private static async getTokenID(): Promise<number> {
    try {
      const info: bundleManager.BundleInfo = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT
      );
      return info.appInfo.accessTokenId;
    } catch (err) {
      console.error(`[PermissionUtils] 获取TokenID失败: ${JSON.stringify(err)}`);
      return 0;
    }
  }

  /**
   * 检查所有必需权限
   */
  public static async checkAllPermissions(): Promise<boolean> {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    const tokenID: number = await PermissionUtils.getTokenID();

    if (tokenID === 0) {
      console.error('[PermissionUtils] TokenID 无效');
      return false;
    }

    for (const permission of PermissionUtils.REQUIRED_PERMISSIONS) {
      try {
        const grantStatus: abilityAccessCtrl.GrantStatus =
          await atManager.checkAccessToken(tokenID, permission);
        if (grantStatus !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
          console.warn(`[PermissionUtils] 权限未授予: ${permission}`);
          return false;
        }
      } catch (err) {
        console.error(`[PermissionUtils] 检查权限失败: ${permission}`);
        return false;
      }
    }
    console.info('[PermissionUtils] 所有权限已授权');
    return true;
  }

  /**
   * 请求所有必需权限
   */
  public static async requestAllPermissions(): Promise<boolean> {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    const context = GlobalContext.getInstance().getContext() as Context | null;

    if (!context) {
      console.error('[PermissionUtils] Context 未初始化!');
      return false;
    }

    try {
      const result = await atManager.requestPermissionsFromUser(context, PermissionUtils.REQUIRED_PERMISSIONS);

      const allGranted: boolean = result.authResults.every(
        (status: number) => status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
      );
      if (allGranted) {
        console.info('[PermissionUtils] 用户已授予所有权限');
        return true;
      }
      console.warn('[PermissionUtils] 部分权限被拒绝');
      return false;
    } catch (err) {
      const error = err as BusinessError;
      console.error(`[PermissionUtils] 请求权限失败: ${error.message}`);
    }
    return false;
  }
}
