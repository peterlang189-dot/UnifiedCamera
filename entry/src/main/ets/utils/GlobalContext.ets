/**
 * 全局上下文管理类
 * 用于在应用各页面之间共享对象和数据
 */
export class GlobalContext {
  private static instance: GlobalContext;
  private context: object | null = null;
  private map: Map<string, Object> = new Map();

  private constructor() {}

  public static getInstance(): GlobalContext {
    if (!GlobalContext.instance) {
      GlobalContext.instance = new GlobalContext();
    }
    return GlobalContext.instance;
  }

  public setContext(context: object): void {
    this.context = context;
  }

  public getContext(): object | null {
    return this.context;
  }

  public set(key: string, value: Object): void {
    this.map.set(key, value);
  }

  public get(key: string): Object | undefined {
    return this.map.get(key);
  }

  public remove(key: string): void {
    this.map.delete(key);
  }

  public contains(key: string): boolean {
    return this.map.has(key);
  }
}
