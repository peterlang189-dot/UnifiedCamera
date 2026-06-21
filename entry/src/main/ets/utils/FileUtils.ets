import { fileIo as fs } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { CameraConstants } from '../camera/CameraConstants';
import { GlobalContext } from './GlobalContext';

/**
 * 文件管理工具类
 * 负责照片和视频文件的保存
 */
export class FileUtils {
  /**
   * 将 ArrayBuffer 保存为 JPEG 照片到相册
   * @param imageBuffer 图片数据
   * @param fileName 文件名（不含扩展名）
   * @returns 保存后的 URI，失败返回空字符串
   */
  public static async savePhotoToGallery(imageBuffer: ArrayBuffer, fileName?: string): Promise<string> {
    try {
      const context = GlobalContext.getInstance().getContext() as any;
      if (!context) {
        console.error('[FileUtils] Context 未初始化!');
        return '';
      }

      const name = fileName || `IMG_${Date.now()}`;
      const helper = photoAccessHelper.getPhotoAccessHelper(context);

      // 创建照片资源
      const uri = await helper.createAsset(
        photoAccessHelper.PhotoType.IMAGE,
        'jpg'
      );

      // 写入图片数据
      const fd = await fs.open(uri, fs.OpenMode.WRITE_ONLY);
      await fs.write(fd, imageBuffer);
      await fs.close(fd);

      console.info(`[FileUtils] 照片已保存: ${uri}`);
      return uri;
    } catch (err) {
      console.error(`[FileUtils] 保存照片失败: ${JSON.stringify(err)}`);
      return '';
    }
  }

  /**
   * 将视频文件移动到相册
   * @param videoPath 临时视频文件路径
   * @param fileName 文件名
   * @returns 保存后的 URI
   */
  public static async saveVideoToGallery(videoPath: string, fileName?: string): Promise<string> {
    try {
      const context = GlobalContext.getInstance().getContext() as any;
      if (!context) {
        console.error('[FileUtils] Context 未初始化!');
        return '';
      }

      const name = fileName || `VID_${Date.now()}`;
      const helper = photoAccessHelper.getPhotoAccessHelper(context);

      // 创建视频资源
      const uri = await helper.createAsset(
        photoAccessHelper.PhotoType.VIDEO,
        'mp4'
      );

      // 读取临时视频文件并写入到相册
      const srcFd = await fs.open(videoPath, fs.OpenMode.READ_ONLY);
      const stat = await fs.stat(videoPath);
      const buffer = new ArrayBuffer(stat.size);
      await fs.read(srcFd, buffer);
      await fs.close(srcFd);

      const dstFd = await fs.open(uri, fs.OpenMode.WRITE_ONLY);
      await fs.write(dstFd, buffer);
      await fs.close(dstFd);

      // 删除临时文件
      try {
        await fs.unlink(videoPath);
      } catch (e) {
        console.warn(`[FileUtils] 删除临时视频文件失败: ${JSON.stringify(e)}`);
      }

      console.info(`[FileUtils] 视频已保存: ${uri}`);
      return uri;
    } catch (err) {
      console.error(`[FileUtils] 保存视频失败: ${JSON.stringify(err)}`);
      return '';
    }
  }

  /**
   * 获取应用沙箱中的临时文件路径
   * @param extension 扩展名（不含点）
   * @returns 完整路径
   */
  public static async getTempFilePath(extension: string): Promise<string> {
    const context = GlobalContext.getInstance().getContext() as any;
    if (!context) {
      return `temp_${Date.now()}.${extension}`;
    }
    return `${context.filesDir}/temp_${Date.now()}.${extension}`;
  }
}
