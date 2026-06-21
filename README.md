# UnifiedCamera - 鸿蒙相机应用

[![HarmonyOS](https://img.shields.io/badge/HarmonyOS-NEXT-blue)](https://developer.harmonyos.com/)
[![Language](https://img.shields.io/badge/Lang-ArkTS%20%2B%20C%2B%2B-orange)](#)
[![API](https://img.shields.io/badge/API-12%2B-green)](#)
[![License](https://img.shields.io/badge/License-Apache%202.0-lightgrey)](LICENSE)

基于 **ArkTS + C++** 的高性能鸿蒙相机应用，支持拍照、录像及原生图像处理。

---

## 功能特性

### 核心功能
- 📷 **拍照** — 支持单张拍摄、定时拍照 (3s/5s/10s)、连拍
- 🎥 **录像** — 1080p @ 30fps 视频录制，支持暂停/恢复
- 🔄 **前后摄像头切换** — 一键切换
- ⚡ **闪光灯** — 关闭 / 自动 / 打开 / 手电筒 四种模式
- 🔍 **数码变焦** — 1.0x ~ 10.0x 平滑缩放
- 👆 **点击对焦** — 支持触屏点击对焦和测光

### 原生 C++ 图像处理 (N-API)
| 功能 | 说明 |
|------|------|
| **格式转换** | NV21 → RGBA / NV21 → NV12 |
| **色彩空间** | YUV → RGB (BT.601，支持 NEON 加速) |
| **滤镜** | 灰度 / 复古 / 负片 / 镜像 / 模糊 / 锐化 |
| **图像增强** | 亮度调节 / 对比度调节 |
| **几何变换** | 旋转 (90°/180°/270°) / 水平翻转 / 垂直翻转 |

### 技术亮点
- ARM64 NEON SIMD 指令集加速 YUV→RGB 转换
- LUT (查找表) 优化亮度和对比度处理
- 分离式 3x3 卷积核模糊/锐化算法
- 无额外依赖，纯标准 C++17 实现

---

## 项目结构

```
UnifiedCamera/
├── AppScope/                          # 应用全局配置
│   ├── app.json5                      # 应用清单
│   └── resources/base/element/        # 全局资源
│
├── entry/                             # 主模块 (Entry)
│   ├── hvigorfile.ts                  # 模块构建配置
│   ├── oh-package.json5               # 模块依赖
│   └── src/main/
│       ├── module.json5               # 模块清单 (权限声明)
│       ├── ets/                       # ArkTS 源代码
│       │   ├── entryability/
│       │   │   └── EntryAbility.ets   # 应用入口
│       │   ├── pages/
│       │   │   └── CameraPage.ets     # 相机主页面 (UI)
│       │   ├── camera/
│       │   │   ├── CameraViewModel.ets # 相机业务逻辑
│       │   │   └── CameraConstants.ets # 常量定义
│       │   └── utils/
│       │       ├── GlobalContext.ets   # 全局上下文
│       │       ├── PermissionUtils.ets # 权限管理
│       │       └── FileUtils.ets       # 文件存储
│       │
│       ├── cpp/                       # C++ 原生模块
│       │   ├── CMakeLists.txt         # CMake 构建配置
│       │   ├── napi_init.cpp          # N-API 模块注册
│       │   ├── camera_native.h        # 原生接口头文件
│       │   ├── camera_native.cpp      # 图像处理核心实现
│       │   ├── image_processor.h      # N-API 函数声明
│       │   ├── image_processor.cpp    # N-API 桥接实现
│       │   └── types/libentry/
│       │       └── index.d.ts         # TS 类型声明
│       │
│       └── resources/                 # 资源文件
│           ├── base/element/          # 字符串资源
│           ├── base/profile/          # 页面路由
│           └── rawfile/               # 原始文件
│
├── hvigor/                            # 构建工具配置
├── hvigorfile.ts                      # 项目级构建入口
├── build-profile.json5                # 构建配置
├── oh-package.json5                   # 项目依赖
└── .gitignore
```

---

## 技术栈

| 层级 | 技术 |
|------|------|
| **UI 框架** | ArkUI (声明式) |
| **编程语言** | ArkTS (ETS) + C++17 |
| **原生桥接** | N-API (Node-API) |
| **相机 API** | Camera Kit (@kit.CameraKit) |
| **图像处理** | C++ (NEON SIMD) |
| **构建工具** | Hvigor + CMake |
| **目标 SDK** | API 12 (HarmonyOS NEXT) |

---

## 构建 & 运行

### 前置条件
- [DevEco Studio](https://developer.harmonyos.com/cn/develop/deveco-studio) 5.0+
- HarmonyOS SDK API 12+
- 真机或模拟器 (相机功能需真机)

### 构建步骤

```bash
# 1. 克隆仓库
git clone https://github.com/YOUR_USERNAME/UnifiedCamera.git
cd UnifiedCamera

# 2. 用 DevEco Studio 打开项目
# File → Open → 选择 UnifiedCamera 目录

# 3. 自动签名配置
# File → Project Structure → Signing Configs → 自动签名

# 4. 构建运行
# Run → Run 'entry' 或按快捷键 Ctrl+R
```

### Hvigor 命令行构建

```bash
# Debug 构建
hvigorw assembleHap --mode module -p product=default -p buildMode=debug

# Release 构建
hvigorw assembleHap --mode module -p product=default -p buildMode=release
```

---

## 使用原生模块

ArkTS 层调用 C++ 原生图像处理：

```typescript
import nativeModule from 'libcamera_native.so';

// NV21 → RGBA 转换
const rgbaBuffer: ArrayBuffer = nativeModule.nv21ToRGBA(nv21Data, 1920, 1080);

// 应用灰度滤镜 (原地修改)
nativeModule.applyFilter(rgbaBuffer, 1920, 1080, 1 /* GRAYSCALE */, 1.0);

// 水平镜像
nativeModule.mirrorImage(rgbaBuffer, 1920, 1080, 0 /* 水平 */);

// 获取版本
const version = nativeModule.getProcessorVersion();
console.info(version);
```

---

## 权限说明

| 权限 | 用途 |
|------|------|
| `ohos.permission.CAMERA` | 拍照和录像 |
| `ohos.permission.MICROPHONE` | 录像时采集音频 |
| `ohos.permission.WRITE_MEDIA` | 保存照片/视频到相册 |
| `ohos.permission.READ_MEDIA` | 读取媒体文件预览 |

---

## 许可证

Apache License 2.0

---

## 作者

- **liangbing** — 初始开发

---

*Built with ❤️ for HarmonyOS*
