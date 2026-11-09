// 通知权限接线：只在「开始生成」时检查，桌面/测试宿主完全惰性。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/services/notification_permission_service.dart';
import 'package:nai_launcher/core/utils/localization_extension.dart';
import 'package:nai_launcher/data/services/generation_foreground_service.dart';
import 'package:nai_launcher/presentation/providers/generation/generation_models.dart';
import 'package:nai_launcher/presentation/wiring/generation_background_sync.dart';
import 'package:nai_launcher/presentation/wiring/notification_permission_wiring.dart';

/// 记录调用次数、不碰平台通道的替身。
class _FakeNotificationPermissionService extends NotificationPermissionService {
  _FakeNotificationPermissionService({
    bool supported = true,
    this.outcome = NotificationPermissionOutcome.available,
  }) : super(isSupported: () => supported);

  final NotificationPermissionOutcome outcome;
  int ensureCalls = 0;
  int settingsCalls = 0;

  @override
  Future<NotificationPermissionOutcome> ensureForBackgroundGeneration() async {
    ensureCalls++;
    return outcome;
  }

  @override
  Future<bool> openNotificationSettings() async {
    settingsCalls++;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  ImageGenerationState state({
    GenerationStatus status = GenerationStatus.idle,
    double progress = 0,
    int currentImage = 0,
    int totalImages = 0,
  }) => ImageGenerationState(
    status: status,
    progress: progress,
    currentImage: currentImage,
    totalImages: totalImages,
  );

  setUp(() {
    GenerationBackgroundSync.resetForTest();
    NotificationPermissionWiring.resetForTest();
    GenerationForegroundService.debugForceSupported = true;
    messenger.setMockMethodCallHandler(
      GenerationForegroundService.channel,
      (call) async => true,
    );
  });

  tearDown(() {
    GenerationForegroundService.debugForceSupported = false;
    GenerationBackgroundSync.resetForTest();
    NotificationPermissionWiring.resetForTest();
    messenger.setMockMethodCallHandler(
      GenerationForegroundService.channel,
      null,
    );
  });

  testWidgets('开始生成 → 触发通知权限检查（不冷启动申请）', (tester) async {
    final fake = _FakeNotificationPermissionService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationPermissionServiceProvider.overrideWithValue(fake),
        ],
        child: const _AttachProbe(),
      ),
    );
    expect(tester.takeException(), isNull);
    // 仅仅挂载 / 冷启动不申请。
    expect(fake.ensureCalls, 0);

    GenerationBackgroundSync.updateForState(
      state(),
      state(status: GenerationStatus.generating),
    );
    await tester.pump();

    expect(fake.ensureCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('非 Android 平台不触发权限检查', (tester) async {
    GenerationForegroundService.debugForceSupported = false;
    final fake = _FakeNotificationPermissionService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationPermissionServiceProvider.overrideWithValue(fake),
        ],
        child: const _AttachProbe(),
      ),
    );

    GenerationBackgroundSync.updateForState(
      state(),
      state(status: GenerationStatus.generating),
    );
    await tester.pump();

    expect(fake.ensureCalls, 0);
  });

  testWidgets('平台不支持时 onGenerationStarted 直接短路', (tester) async {
    final fake = _FakeNotificationPermissionService(supported: false);
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationPermissionServiceProvider.overrideWithValue(fake),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, child) {
              captured = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    NotificationPermissionWiring.onGenerationStarted(captured);
    await tester.pump();

    expect(fake.ensureCalls, 0);
  });

  testWidgets('需要展示「去设置」引导但页面上下文不可用时也不抛异常', (tester) async {
    final fake = _FakeNotificationPermissionService(
      outcome: const NotificationPermissionOutcome(
        granted: false,
        showSettingsGuidance: true,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationPermissionServiceProvider.overrideWithValue(fake),
        ],
        child: const _AttachProbe(),
      ),
    );

    GenerationBackgroundSync.updateForState(
      state(),
      state(status: GenerationStatus.generating),
    );
    await tester.pump();

    expect(fake.ensureCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('拒绝时展示一次「去设置」SnackBar，按钮跳原生设置页', (tester) async {
    final fake = _FakeNotificationPermissionService(
      outcome: const NotificationPermissionOutcome(
        granted: false,
        showSettingsGuidance: true,
      ),
    );
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationPermissionServiceProvider.overrideWithValue(fake),
        ],
        child: MaterialApp(
          scaffoldMessengerKey: appScaffoldMessengerKey,
          home: Consumer(
            builder: (context, ref, child) {
              captured = ref;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      ),
    );

    NotificationPermissionWiring.onGenerationStarted(captured);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text(currentL10n.generation_notificationPermissionDenied),
      findsOneWidget,
    );
    await tester.tap(
      find.text(currentL10n.generation_notificationGoToSettings),
    );
    await tester.pump();
    expect(fake.settingsCalls, 1);
  });
}

/// 在 initState 里调用 [GenerationBackgroundSync.attach] 的最小探针。
class _AttachProbe extends ConsumerStatefulWidget {
  const _AttachProbe();

  @override
  ConsumerState<_AttachProbe> createState() => _AttachProbeState();
}

class _AttachProbeState extends ConsumerState<_AttachProbe> {
  @override
  void initState() {
    super.initState();
    GenerationBackgroundSync.attach(ref);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
