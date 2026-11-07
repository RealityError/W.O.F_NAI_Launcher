import 'dart:io';

import 'package:flutter/foundation.dart';

/// Windows 与 macOS 是当前受支持的桌面平台。
///
/// 保持窄口径：Android 移植不能继承桌面插件的假设，所有桌面专属能力都必须
/// 经下面的 capability getter 判断，而不是散落的 `Platform.isWindows` 判断。
bool get isSupportedDesktop => Platform.isWindows || Platform.isMacOS;

bool get usesMacOSConventions => defaultTargetPlatform == TargetPlatform.macOS;

// ───────────────────────────── 移动端 ─────────────────────────────

/// 当前是否为 Android（本仓库新增的移植目标）。
bool get isAndroidPlatform => !kIsWeb && Platform.isAndroid;

/// 当前是否为 iOS。iOS 暂未移植，但同样没有桌面插件/外部进程能力。
bool get isIOSPlatform => !kIsWeb && Platform.isIOS;

/// Android / iOS：没有 window_manager、tray_manager、screen_retriever、
/// desktop_multi_window、注册表、PowerShell 或可执行工具链。
bool get isMobilePlatform => isAndroidPlatform || isIOSPlatform;

// ───────────────────────────── 桌面能力 ─────────────────────────────

/// 原生窗口几何/标题栏/托盘：window_manager、screen_retriever、tray_manager
/// 只在桌面端有实现。
bool get supportsDesktopWindowChrome => isSupportedDesktop;

/// 系统托盘。桌面端启动时注册、退出时销毁。
bool get supportsTray => isSupportedDesktop;

/// 多窗口（桌面端 `desktop_multi_window` 悬浮资源窗口）。
bool get supportsMultiWindow => isSupportedDesktop;

/// 启动外部进程：`.exe` 工具、Python/uv、Node、PowerShell、nvidia-smi、
/// macOS `open`/`ditto`。移动端调用只会得到 `ProcessException`。
///
/// 口径包含 Linux，避免改变未移植桌面环境的既有行为。
bool get supportsExternalProcesses => !isMobilePlatform;

/// 应用内更新下载与安装（Windows PS1 更新脚本 / macOS 核验后在 Finder 显示）。
bool get supportsInAppUpdateInstall => isSupportedDesktop;

/// 列出/安装系统字体（`com.nailauncher/system_fonts` 原生通道）。
bool get supportsSystemFonts => isSupportedDesktop;

/// 读取系统代理：Windows 注册表、macOS `scutil`。
bool get supportsSystemProxy => isSupportedDesktop;

/// 通过 Windows 注册表读取系统代理（`win32_registry`）。
bool get supportsWindowsProxy => Platform.isWindows;

/// GPU 探测（`nvidia-smi`）。移动端不探测，避免无意义的进程启动异常。
bool get supportsGpuProbe => supportsExternalProcesses;

/// RAG 本地 Python 运行时（uv + PyTorch）。
bool get supportsLocalRagRuntime => isSupportedDesktop;

/// 基于随包可执行文件的本地/高级放大（realesrgan / SeedVR2 / RTX Video）。
bool get supportsLocalUpscale => isSupportedDesktop;

/// NAI Agent 的随包 Node 运行时与宿主脚本。
bool get supportsNaiAgentRuntime => isSupportedDesktop;

/// Krita 桥接（本地 WebSocket 服务 + 桌面插件端）。
bool get supportsKritaBridge => isSupportedDesktop;

/// 桌面原生标题栏命中区（Windows runner `com.nailauncher/titlebar`）。
bool get supportsNativeTitleBarRegion => Platform.isWindows;

/// Windows 窗口材质（DWM 背景，`com.nailauncher/window_material`）。
bool get supportsWindowBackdropMaterial => Platform.isWindows;

/// window_manager 窗口事件（隐藏/最小化），仅 Windows runner 使用。
bool get supportsWindowManagerEvents => Platform.isWindows;
