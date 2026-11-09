import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_logger.dart';
import '../utils/desktop_platform.dart';

/// 一次「为后台生成准备通知权限」的结果。
@immutable
class NotificationPermissionOutcome {
  const NotificationPermissionOutcome({
    required this.granted,
    this.showSettingsGuidance = false,
  });

  /// 通知是否可用：已授权、刚授权，或平台不需要运行时权限。
  final bool granted;

  /// 是否要给用户一次「去设置」引导，只在首次被拒后为 true。
  final bool showSettingsGuidance;

  /// 通知可用（含桌面 / API < 33 等不需要运行时权限的情况）。
  static const NotificationPermissionOutcome available =
      NotificationPermissionOutcome(granted: true);
}

/// `com.nailauncher/notifications` MethodChannel 的 Dart 封装。
///
/// Android 13+ 的 `POST_NOTIFICATIONS` 是运行时权限，没有授权时后台生成的
/// 进度/完成通知不可见。本服务只在「用户真正开始一次生成」时被调用（见
/// `NotificationPermissionWiring`），不在冷启动时申请：
///  - 系统已允许：直接可用，不弹任何弹窗；
///  - 从未申请过：弹一次系统权限框，并把「已申请」落盘；
///  - 用户拒绝过：不再重复弹框，只提供一次「去设置」引导。
///
/// 桌面 / 测试宿主没有原生通道，所有调用都短路为「可用」，不会改变桌面行为。
class NotificationPermissionService {
  NotificationPermissionService({
    MethodChannel channel = const MethodChannel(channelName),
    Future<SharedPreferences> Function()? preferences,
    bool Function()? isSupported,
  }) : _channel = channel,
       _preferences = preferences ?? SharedPreferences.getInstance,
       _isSupported = isSupported ?? (() => isAndroidPlatform);

  /// 原生通道名（与 `NotificationPermissionHelper.CHANNEL` 保持一致）。
  static const String channelName = 'com.nailauncher/notifications';

  /// 是否已经弹过系统权限框；落盘后拒绝也不会再次申请。
  static const String requestedPreferenceKey =
      'notification_permission_requested';

  /// 是否已经展示过「去设置」引导；只引导一次，避免每次生成都打扰。
  static const String guidancePreferenceKey =
      'notification_permission_guidance_shown';

  final MethodChannel _channel;
  final Future<SharedPreferences> Function() _preferences;
  final bool Function() _isSupported;

  bool _requestedThisSession = false;
  bool _guidanceShownThisSession = false;

  /// 当前平台是否有通知运行时权限这回事（Android 之外一律不处理）。
  bool get isSupported => _isSupported();

  /// 系统当前是否允许本应用发通知；平台不支持时视为可用。
  Future<bool> areNotificationsEnabled() async {
    if (!isSupported) return true;
    try {
      return await _channel.invokeMethod<bool>('areNotificationsEnabled') ??
          true;
    } on MissingPluginException {
      // 旧包或测试宿主没有该通道：按可用处理，不误报权限问题。
      return true;
    } on PlatformException catch (error) {
      AppLogger.w(
        'areNotificationsEnabled failed: ${error.code} ${error.message}',
        'NotificationPermission',
      );
      return true;
    }
  }

  /// 申请通知权限。API 33+ 会弹系统权限框；API < 33 原生直接返回 true。
  Future<bool> requestNotifications() async {
    if (!isSupported) return true;
    try {
      return await _channel.invokeMethod<bool>('requestNotifications') ?? false;
    } on MissingPluginException {
      return true;
    } on PlatformException catch (error) {
      AppLogger.w(
        'requestNotifications failed: ${error.code} ${error.message}',
        'NotificationPermission',
      );
      return false;
    }
  }

  /// 跳本应用的通知设置页；平台不支持或跳转失败返回 false。
  Future<bool> openNotificationSettings() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('openNotificationSettings') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      AppLogger.w(
        'openNotificationSettings failed: ${error.code} ${error.message}',
        'NotificationPermission',
      );
      return false;
    }
  }

  /// 生成刚开始时的权限准备。调用方据此决定是否展示「去设置」引导。
  Future<NotificationPermissionOutcome> ensureForBackgroundGeneration() async {
    if (!isSupported) return NotificationPermissionOutcome.available;
    if (await areNotificationsEnabled()) {
      return NotificationPermissionOutcome.available;
    }
    final preferences = await _loadPreferences();
    if (!_alreadyRequested(preferences)) {
      _requestedThisSession = true;
      await _writeFlag(preferences, requestedPreferenceKey);
      if (await requestNotifications()) {
        return NotificationPermissionOutcome.available;
      }
      // 个别设备授权后系统状态刷新有延迟，再查一次再判定失败。
      if (await areNotificationsEnabled()) {
        return NotificationPermissionOutcome.available;
      }
    }
    if (_guidanceShown(preferences)) {
      return const NotificationPermissionOutcome(granted: false);
    }
    _guidanceShownThisSession = true;
    await _writeFlag(preferences, guidancePreferenceKey);
    return const NotificationPermissionOutcome(
      granted: false,
      showSettingsGuidance: true,
    );
  }

  bool _alreadyRequested(SharedPreferences? preferences) =>
      _requestedThisSession ||
      (preferences?.getBool(requestedPreferenceKey) ?? false);

  bool _guidanceShown(SharedPreferences? preferences) =>
      _guidanceShownThisSession ||
      (preferences?.getBool(guidancePreferenceKey) ?? false);

  Future<SharedPreferences?> _loadPreferences() async {
    try {
      return await _preferences();
    } catch (error) {
      // 落盘失败时退化为「本次会话内不再重复申请」。
      AppLogger.w(
        'Failed to load notification permission preferences: $error',
        'NotificationPermission',
      );
      return null;
    }
  }

  Future<void> _writeFlag(SharedPreferences? preferences, String key) async {
    if (preferences == null) return;
    try {
      await preferences.setBool(key, true);
    } catch (error) {
      AppLogger.w('Failed to persist $key: $error', 'NotificationPermission');
    }
  }
}

/// 通知权限服务。桌面 / 测试宿主上 `isSupported` 为 false，所有调用短路。
final notificationPermissionServiceProvider =
    Provider<NotificationPermissionService>(
      (ref) => NotificationPermissionService(),
    );
