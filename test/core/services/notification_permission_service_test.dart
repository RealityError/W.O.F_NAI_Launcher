// Android 13+ 通知权限的 Dart 侧协议（`com.nailauncher/notifications`）。
//
// 这里不测 Kotlin，只钉住 Dart 侧申请策略：
//  - 已授权 / 平台不支持时不弹权限框；
//  - 未授权时只申请一次，拒绝后不再重复申请；
//  - 拒绝后只给一次「去设置」引导；
//  - API < 33 由原生直接放行，Dart 侧不会误判为拒绝。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/services/notification_permission_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(NotificationPermissionService.channelName);

  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall call) handler;

  NotificationPermissionService buildService({
    bool supported = true,
    Future<SharedPreferences> Function()? preferences,
  }) => NotificationPermissionService(
    channel: channel,
    isSupported: () => supported,
    preferences: preferences,
  );

  List<String> methods() => [for (final call in calls) call.method];

  bool requestWasCalled() =>
      calls.any((call) => call.method == 'requestNotifications');

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    calls = <MethodCall>[];
    handler = (call) async {
      throw MissingPluginException('No implementation for ${call.method}');
    };
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('非 Android 平台：直接视为可用且不调用原生通道', () async {
    final service = buildService(supported: false);

    final outcome = await service.ensureForBackgroundGeneration();

    expect(outcome.granted, isTrue);
    expect(outcome.showSettingsGuidance, isFalse);
    expect(await service.areNotificationsEnabled(), isTrue);
    expect(await service.requestNotifications(), isTrue);
    expect(await service.openNotificationSettings(), isFalse);
    expect(calls, isEmpty);
  });

  test('已授权：不弹出权限框', () async {
    handler = (call) async {
      if (call.method == 'areNotificationsEnabled') return true;
      throw MissingPluginException(call.method);
    };

    final outcome = await buildService().ensureForBackgroundGeneration();

    expect(outcome.granted, isTrue);
    expect(outcome.showSettingsGuidance, isFalse);
    expect(methods(), <String>['areNotificationsEnabled']);
    expect(requestWasCalled(), isFalse);
  });

  test('未授权 → 申请 → 用户允许：直接可用', () async {
    var enabled = false;
    handler = (call) async => switch (call.method) {
      'areNotificationsEnabled' => enabled,
      'requestNotifications' => enabled = true,
      _ => throw MissingPluginException(call.method),
    };

    final service = buildService();
    final outcome = await service.ensureForBackgroundGeneration();

    expect(outcome.granted, isTrue);
    expect(outcome.showSettingsGuidance, isFalse);
    expect(methods(), <String>[
      'areNotificationsEnabled',
      'requestNotifications',
    ]);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getBool(NotificationPermissionService.requestedPreferenceKey),
      isTrue,
    );
  });

  test('API < 33（无运行时权限）：原生直接放行，不展示权限框', () async {
    // Android 13 以下 requestNotifications 不弹框、直接返回 true（原生分支），
    // 这里复现该返回，验证 Dart 侧不会把它当成拒绝。
    handler = (call) async => switch (call.method) {
      'areNotificationsEnabled' => false,
      'requestNotifications' => true,
      _ => throw MissingPluginException(call.method),
    };

    final outcome = await buildService().ensureForBackgroundGeneration();

    expect(outcome.granted, isTrue);
    expect(outcome.showSettingsGuidance, isFalse);
  });

  test('未授权 → 申请 → 用户拒绝：给一次「去设置」引导，且不再重复申请', () async {
    handler = (call) async => switch (call.method) {
      'areNotificationsEnabled' => false,
      'requestNotifications' => false,
      _ => throw MissingPluginException(call.method),
    };
    final service = buildService();

    final first = await service.ensureForBackgroundGeneration();
    expect(first.granted, isFalse);
    expect(first.showSettingsGuidance, isTrue);
    // 申请后再查一次系统状态（部分设备授权有延迟），仍拒绝才给引导。
    expect(methods(), <String>[
      'areNotificationsEnabled',
      'requestNotifications',
      'areNotificationsEnabled',
    ]);

    calls.clear();
    final second = await service.ensureForBackgroundGeneration();
    expect(second.granted, isFalse);
    expect(second.showSettingsGuidance, isFalse);
    // 拒绝过就只查询状态，不再弹系统权限框。
    expect(methods(), <String>['areNotificationsEnabled']);
  });

  test('拒绝状态跨服务实例生效（落盘后重启也不再申请）', () async {
    handler = (call) async => switch (call.method) {
      'areNotificationsEnabled' => false,
      'requestNotifications' => false,
      _ => throw MissingPluginException(call.method),
    };
    await buildService().ensureForBackgroundGeneration();
    calls.clear();

    final reopened = buildService();
    final outcome = await reopened.ensureForBackgroundGeneration();

    expect(outcome.granted, isFalse);
    expect(outcome.showSettingsGuidance, isFalse);
    expect(methods(), <String>['areNotificationsEnabled']);
  });

  test('落盘失败时本次会话内仍不会重复申请', () async {
    handler = (call) async => switch (call.method) {
      'areNotificationsEnabled' => false,
      'requestNotifications' => false,
      _ => throw MissingPluginException(call.method),
    };
    final service = buildService(
      preferences: () async => throw StateError('preferences unavailable'),
    );

    final first = await service.ensureForBackgroundGeneration();
    expect(first.showSettingsGuidance, isTrue);

    calls.clear();
    final second = await service.ensureForBackgroundGeneration();
    expect(second.showSettingsGuidance, isFalse);
    expect(methods(), <String>['areNotificationsEnabled']);
  });

  test('申请回调返回拒绝但系统随后已允许：按已授权处理', () async {
    var enabledQueries = 0;
    handler = (call) async {
      if (call.method == 'areNotificationsEnabled') {
        enabledQueries++;
        return enabledQueries > 1;
      }
      if (call.method == 'requestNotifications') return false;
      throw MissingPluginException(call.method);
    };

    final outcome = await buildService().ensureForBackgroundGeneration();

    expect(outcome.granted, isTrue);
    expect(outcome.showSettingsGuidance, isFalse);
  });

  test('原生申请抛出 PlatformException：按未授权处理并只引导一次', () async {
    handler = (call) async {
      if (call.method == 'areNotificationsEnabled') return false;
      if (call.method == 'requestNotifications') {
        throw PlatformException(code: 'request_failed');
      }
      throw MissingPluginException(call.method);
    };

    final outcome = await buildService().ensureForBackgroundGeneration();

    expect(outcome.granted, isFalse);
    expect(outcome.showSettingsGuidance, isTrue);
  });

  test('通道缺失（旧包 / 测试宿主）：按可用处理，不误报权限问题', () async {
    // 默认 handler 对每个方法都抛 MissingPluginException。
    final service = buildService();

    expect(await service.areNotificationsEnabled(), isTrue);
    final outcome = await service.ensureForBackgroundGeneration();
    expect(outcome.granted, isTrue);
    expect(outcome.showSettingsGuidance, isFalse);
    expect(await service.openNotificationSettings(), isFalse);
  });

  test('openNotificationSettings 调用原生跳转并返回结果', () async {
    handler = (call) async {
      if (call.method == 'openNotificationSettings') return true;
      throw MissingPluginException(call.method);
    };

    expect(await buildService().openNotificationSettings(), isTrue);
    expect(methods(), <String>['openNotificationSettings']);
  });

  test('openNotificationSettings 原生跳转失败返回 false', () async {
    handler = (call) async {
      if (call.method == 'openNotificationSettings') {
        throw PlatformException(code: 'no_settings_activity');
      }
      throw MissingPluginException(call.method);
    };

    expect(await buildService().openNotificationSettings(), isFalse);
  });
}
