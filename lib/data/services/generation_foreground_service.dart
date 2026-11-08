import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/utils/app_logger.dart';

/// Android 前台服务桥：生成进行中把进程保活，并在通知栏显示进度。
///
/// 由 `MainActivity.kt` 在 `com.nailauncher/generation` 通道实现。
/// 桌面 / 测试 / 通道缺失时所有调用都是无副作用的 no-op，调用方无需判断平台。
class GenerationForegroundService {
  GenerationForegroundService._();

  static const MethodChannel channel = MethodChannel(
    'com.nailauncher/generation',
  );

  /// 测试里把平台伪装成 Android（宿主测试进程不是 Android）。
  @visibleForTesting
  static bool debugForceSupported = false;

  static bool get isSupported => debugForceSupported || Platform.isAndroid;

  /// 启动前台服务；重复调用只更新通知。
  static Future<bool> start({required String title, required String text}) =>
      _invokeBool('start', {'title': title, 'text': text});

  /// 更新常驻通知文案/进度。[progress] 为 0..1，null 表示不画进度条。
  static Future<bool> update({
    required String title,
    required String text,
    double? progress,
  }) => _invokeBool('update', {
    'title': title,
    'text': text,
    if (progress != null) 'progress': progress.clamp(0.0, 1.0),
  });

  /// 停止前台服务；[title]/[text] 非空时额外发一条完成通知（点按回到应用）。
  static Future<bool> stop({required String title, required String text}) =>
      _invokeBool('stop', {'title': title, 'text': text});

  static Future<bool> _invokeBool(
    String method,
    Map<String, Object?> arguments,
  ) async {
    if (!isSupported) return false;
    try {
      return await channel.invokeMethod<bool>(method, arguments) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      AppLogger.w(
        '$method failed: ${error.code} ${error.message}',
        'GenerationForegroundService',
      );
      return false;
    }
  }
}
