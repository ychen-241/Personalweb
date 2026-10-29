/**
 * 电路画板 - 本地持久化（JSON 文件存储在应用沙箱 filesDir）
 */
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';

export class BoardStorage {
  private static fileName(): string {
    return 'circuit_board.json';
  }

  /** 保存画板 JSON，成功返回 true */
  static save(context: common.Context, json: string): boolean {
    try {
      const path: string = `${context.filesDir}/${BoardStorage.fileName()}`;
      const file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, json);
      } finally {
        fs.closeSync(file);
      }
      return true;
    } catch (err) {
      return false;
    }
  }

  /** 读取画板 JSON；不存在或失败返回空串 */
  static load(context: common.Context): string {
    try {
      const path: string = `${context.filesDir}/${BoardStorage.fileName()}`;
      if (!fs.accessSync(path)) {
        return '';
      }
      return fs.readTextSync(path);
    } catch (err) {
      return '';
    }
  }
}
