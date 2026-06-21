import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { GlobalContext } from './GlobalContext';

/**
 * 文件管理工具类 — SDK 26 兼容版
 */
export class FileUtils {
  /**
   * 保存媒体文件到相册
   * @param sourceUri 源文件 URI
   * @param type 类型 'photo' | 'video'
   * @returns 保存后的 URI
   */
  public static async saveMediaToGallery(sourceUri: string, type: string): Promise<string> {
    try {
      const context = GlobalContext.getInstance().getContext() as Context;
      if (!context) {
        console.error('[FileUtils] Context 未初始化!');
        return '';
      }

      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const uri = await helper.createAsset(
        type === 'video' ? photoAccessHelper.PhotoType.VIDEO : photoAccessHelper.PhotoType.IMAGE,
        type === 'video' ? 'mp4' : 'jpg'
      );

      // 复制文件内容
      const srcFile = fileIo.openSync(sourceUri, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(sourceUri);
      const buffer = new ArrayBuffer(stat.size);
      fileIo.readSync(srcFile.fd, buffer);
      fileIo.closeSync(srcFile);

      const dstFile = fileIo.openSync(uri, fileIo.OpenMode.WRITE_ONLY);
      fileIo.writeSync(dstFile.fd, buffer);
      fileIo.closeSync(dstFile);

      console.info(`[FileUtils] ${type} 已保存: ${uri}`);
      return uri;
    } catch (err) {
      console.error(`[FileUtils] 保存${type}失败: ${JSON.stringify(err)}`);
      return '';
    }
  }

  /**
   * 保存 ArrayBuffer 为照片
   */
  public static async savePhotoBuffer(imageBuffer: ArrayBuffer, fileName?: string): Promise<string> {
    try {
      const context = GlobalContext.getInstance().getContext() as Context;
      if (!context) return '';

      const name = fileName || `IMG_${Date.now()}`;
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const uri = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, 'jpg');

      const dstFile = fileIo.openSync(uri, fileIo.OpenMode.WRITE_ONLY);
      fileIo.writeSync(dstFile.fd, imageBuffer);
      fileIo.closeSync(dstFile);

      console.info(`[FileUtils] 照片已保存: ${uri}`);
      return uri;
    } catch (err) {
      console.error(`[FileUtils] 保存照片失败: ${JSON.stringify(err)}`);
      return '';
    }
  }
}
