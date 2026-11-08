// 生成状态 → Android 前台服务/通知的桥接逻辑（G10）。
//
// 这里不测 Kotlin，只钉住 Dart 侧的状态迁移协议：什么时候 start / update /
// stop、通知文案从哪来、进度节流、非 Android 平台完全惰性。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/utils/localization_extension.dart';
import 'package:nai_launcher/data/services/generation_foreground_service.dart';
import 'package:nai_launcher/presentation/providers/generation/generation_models.dart';
import 'package:nai_launcher/presentation/wiring/generation_background_sync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];

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

  setUp(() async {
    calls.clear();
    GenerationBackgroundSync.resetForTest();
    GenerationForegroundService.debugForceSupported = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(GenerationForegroundService.channel, (
          call,
        ) async {
          calls.add(call);
          return true;
        });
  });

  tearDown(() {
    GenerationForegroundService.debugForceSupported = false;
    GenerationBackgroundSync.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(GenerationForegroundService.channel, null);
  });

  test('开始生成 → 启动前台服务', () async {
    GenerationBackgroundSync.updateForState(
      state(),
      state(status: GenerationStatus.generating),
    );
    await pumpEventQueue();

    expect(calls, hasLength(1));
    expect(calls.single.method, 'start');
    final args = calls.single.arguments as Map;
    expect(args['title'], currentL10n.generation_backgroundRunningTitle);
    expect(args['text'], currentL10n.generation_backgroundRunningText);
  });

  test('生成中按进度更新通知，2% 以内不刷屏', () async {
    GenerationBackgroundSync.updateForState(
      state(),
      state(status: GenerationStatus.generating, progress: 0.0),
    );
    await pumpEventQueue();
    calls.clear();

    // 1% 变化：忽略。
    GenerationBackgroundSync.updateForState(
      state(status: GenerationStatus.generating, progress: 0.0),
      state(
        status: GenerationStatus.generating,
        progress: 0.01,
        currentImage: 0,
        totalImages: 2,
      ),
    );
    await pumpEventQueue();
    expect(calls, isEmpty);

    // 越过 2%：更新，带上进度。
    GenerationBackgroundSync.updateForState(
      state(status: GenerationStatus.generating, progress: 0.01),
      state(
        status: GenerationStatus.generating,
        progress: 0.5,
        currentImage: 1,
        totalImages: 2,
      ),
    );
    await pumpEventQueue();
    expect(calls.single.method, 'update');
    final args = calls.single.arguments as Map;
    expect(args['progress'], 0.5);
    expect(args['text'], contains('1/2'));
  });

  test('当前张数变化时即使进度没动也更新', () async {
    GenerationBackgroundSync.updateForState(
      state(),
      state(
        status: GenerationStatus.generating,
        progress: 0.5,
        currentImage: 1,
        totalImages: 2,
      ),
    );
    await pumpEventQueue();
    calls.clear();

    GenerationBackgroundSync.updateForState(
      state(
        status: GenerationStatus.generating,
        progress: 0.5,
        currentImage: 1,
      ),
      state(
        status: GenerationStatus.generating,
        progress: 0.5,
        currentImage: 2,
        totalImages: 2,
      ),
    );
    await pumpEventQueue();
    expect(calls.single.method, 'update');
    expect((calls.single.arguments as Map)['text'], contains('2/2'));
  });

  test('生成完成 → 停止服务并发完成通知', () async {
    GenerationBackgroundSync.updateForState(
      state(),
      state(status: GenerationStatus.generating),
    );
    await pumpEventQueue();
    calls.clear();

    GenerationBackgroundSync.updateForState(
      state(status: GenerationStatus.generating),
      state(status: GenerationStatus.completed, totalImages: 2),
    );
    await pumpEventQueue();

    expect(calls.single.method, 'stop');
    final args = calls.single.arguments as Map;
    expect(args['title'], currentL10n.generation_backgroundDoneTitle);
    expect(args['text'], currentL10n.generation_backgroundDoneText(2));
  });

  test('生成失败 / 取消分别停止并给出对应通知', () async {
    GenerationBackgroundSync.updateForState(
      state(),
      state(status: GenerationStatus.generating),
    );
    await pumpEventQueue();
    calls.clear();

    GenerationBackgroundSync.updateForState(
      state(status: GenerationStatus.generating),
      state(status: GenerationStatus.error),
    );
    await pumpEventQueue();
    expect(calls.single.method, 'stop');
    expect(
      (calls.single.arguments as Map)['title'],
      currentL10n.generation_backgroundFailedTitle,
    );

    calls.clear();
    GenerationBackgroundSync.updateForState(
      state(status: GenerationStatus.error),
      state(status: GenerationStatus.cancelled),
    );
    await pumpEventQueue();
    expect(calls.single.method, 'stop');
    expect(
      (calls.single.arguments as Map)['title'],
      currentL10n.generation_backgroundCancelledTitle,
    );
  });

  test('非 Android（桌面/测试宿主）完全惰性', () async {
    GenerationForegroundService.debugForceSupported = false;

    GenerationBackgroundSync.updateForState(
      state(),
      state(status: GenerationStatus.generating),
    );
    GenerationBackgroundSync.updateForState(
      state(status: GenerationStatus.generating),
      state(status: GenerationStatus.completed, totalImages: 1),
    );
    await pumpEventQueue();

    expect(calls, isEmpty);
    expect(GenerationForegroundService.isSupported, isFalse);
  });
}
