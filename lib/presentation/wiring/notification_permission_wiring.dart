import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/notification_permission_service.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/localization_extension.dart';

/// 应用根 `ScaffoldMessenger` 的 key。
///
/// `lib/app.dart` 的 `MaterialApp.router` 把它传给 `scaffoldMessengerKey`；
/// 没有 BuildContext 的接线层（本文件）用它弹「去设置」引导 SnackBar。
final GlobalKey<ScaffoldMessengerState> appScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>(debugLabel: 'appScaffoldMessenger');

/// Android 13+ 通知权限接线。
///
/// 由 `GenerationBackgroundSync` 在检测到「生成开始」（同时也是启动后台
/// 前台服务的时机）时调用 [onGenerationStarted]，因此：
///  - 冷启动 / 单纯浏览不会弹权限框，只有真正发起生成才申请；
///  - 用户拒绝后不再重复申请，只在首次拒绝后弹一次带「去设置」按钮的
///    SnackBar；该按钮跳本应用的通知设置页；
///  - 桌面 / 测试宿主 `isSupported` 为 false，本类完全惰性。
class NotificationPermissionWiring {
  NotificationPermissionWiring._();

  /// 同一次生成里重复触发（或状态抖动）时只跑一轮权限检查。
  static bool _checking = false;

  /// 生成开始时调用；重复调用会被合并。
  static void onGenerationStarted(WidgetRef ref) {
    if (_checking) return;
    final service = ref.read(notificationPermissionServiceProvider);
    if (!service.isSupported) return;
    _checking = true;
    unawaited(_ensure(ref, service));
  }

  /// 跳本应用的通知设置页；「去设置」按钮与后续入口共用。
  static Future<bool> openNotificationSettings(WidgetRef ref) => ref
      .read(notificationPermissionServiceProvider)
      .openNotificationSettings();

  static Future<void> _ensure(
    WidgetRef ref,
    NotificationPermissionService service,
  ) async {
    try {
      final outcome = await service.ensureForBackgroundGeneration();
      if (!outcome.showSettingsGuidance) return;
      _showSettingsGuidance(ref);
    } catch (error) {
      AppLogger.w(
        'Failed to prepare notification permission: $error',
        'NotificationPermission',
      );
    } finally {
      _checking = false;
    }
  }

  static void _showSettingsGuidance(WidgetRef ref) {
    final messenger = appScaffoldMessengerKey.currentState;
    if (messenger == null) return;
    final l10n = currentL10n;
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.generation_notificationPermissionDenied),
        action: SnackBarAction(
          label: l10n.generation_notificationGoToSettings,
          onPressed: () => unawaited(openNotificationSettings(ref)),
        ),
        duration: const Duration(seconds: 8),
      ),
    );
  }

  @visibleForTesting
  static void resetForTest() {
    _checking = false;
  }
}
