import 'dart:io';

import 'package:flutter/services.dart';

import '../utils/app_logger.dart';

/// 应用启动时读取到的 Android 系统代理（"host:port"），未配置时为 null。
///
/// Flutter 的 dart:io HttpClient 不会自动使用 Android 系统代理，因此启动阶段读取
/// 一次并缓存；同步的代理设置读取（如 Dio 客户端/认证链路）从这里取值。
String? androidSystemProxyAddress;

/// 读取 Android 全局 HTTP 代理（"host:port"）。
///
/// 在创建任何 HttpClient 之前调用，并把结果缓存到 [androidSystemProxyAddress]。
/// 与桌面端"复用系统代理"的行为保持一致：移动网络/Wi-Fi 设置里的代理都会生效。
Future<String?> readAndroidSystemProxy() async {
  if (!Platform.isAndroid) return null;
  try {
    final value = await const MethodChannel(
      'com.nailauncher/platform',
    ).invokeMethod<String>('getSystemProxy');
    return androidSystemProxyAddress = _normalize(value);
  } on MissingPluginException {
    // 桌面端/测试环境没有该通道。
    return null;
  } catch (error) {
    AppLogger.w('Failed to read Android system proxy: $error', 'PROXY');
    return null;
  }
}

String? _normalize(String? value) {
  if (value == null) return null;
  final normalized = value.trim();
  // Android 关闭代理时会存成空串、":0" 或 "null"。
  if (normalized.isEmpty ||
      normalized == ':0' ||
      normalized.toLowerCase() == 'null') {
    return null;
  }
  return normalized;
}
