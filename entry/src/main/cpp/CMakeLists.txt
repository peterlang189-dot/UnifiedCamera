# CMake 构建配置 - 鸿蒙相机原生模块
cmake_minimum_required(VERSION 3.5.0)
project(UnifiedCameraNative)

# 设置 C++17 标准
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# N-API 头文件路径
include_directories(
    ${NATIVERENDER_ROOT_PATH}
    ${NATIVERENDER_ROOT_PATH}/include
)

# 源文件列表
add_library(camera_native SHARED
    napi_init.cpp
    camera_native.cpp
    image_processor.cpp
)

# 链接 N-API 和系统库
target_link_libraries(camera_native PUBLIC
    libace_napi.z.so
    libhilog_ndk.z.so
    libimage_packer.so
    libpixelmap.so
    libnative_buffer.so
    libnative_image.so
    libnative_media_core.so
    libnative_window.so
    libcamera_ndk.z.so
    libimage_source.so
)
