import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/mobile/mobile_breakpoints.dart';
import 'package:nai_launcher/presentation/ui/gen/translation_adjust_window.dart';

import '../../../helpers/studio_capture_fonts.dart';
import 'gen_test_harness.dart';

/// G5：追加翻译调整浮窗在 360×640 手机竖屏下的走查。
///
/// 浮窗是页面浮层（`TranslationAdjustmentOverlay` 插进 root Overlay），这里直接
/// 把它放进同样尺寸的 Stack 里，检查尺寸夹取与无 RenderFlex overflow。
void main() {
  setUpAll(loadStudioCaptureFonts);
  setUp(() => debugForceMobileLayout = true);
  tearDown(() => debugForceMobileLayout = null);

  TranslationAdjustView fixture({bool busy = false, String? error}) =>
      TranslationAdjustView(
        blockCount: 12,
        entries: const [
          TranslationAdjustUser('把这一块拆成颜色和长度两个块，保持原文不变。'),
          TranslationAdjustThinking('先读取当前块与版本，再保持原文不变进行细分。'),
          TranslationAdjustReply(
            '已完成 `main/\ue000` 的拆分：银色长发 → 银色 / 长发。\n'
            '如果需要重译，可以继续选中相邻块。',
          ),
          TranslationAdjustSteps([
            TranslationAdjustStep(
              id: 's1',
              op: 'split_block',
              status: TranslationAdjustStepStatus.done,
              subject: '银色长发 → 2 块',
            ),
            TranslationAdjustStep(
              id: 's2',
              op: 'retranslate',
              status: TranslationAdjustStepStatus.running,
              subject: '银色 / 长发',
            ),
          ]),
        ],
        selected: 2,
        modelLabel: 'Fixture · translation-model',
        busy: busy,
        canUndo: true,
        error: error,
      );

  Future<void> pumpWindow(
    WidgetTester tester, {
    required TranslationAdjustView view,
    TranslationAdjustActions? actions,
    Size size = const Size(360, 640),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      genApp(
        Stack(
          children: [
            TranslationAdjustWindow(
              anchor: const Rect.fromLTWH(20, 30, 300, 30),
              view: view,
              actions:
                  actions ??
                  TranslationAdjustActions(
                    onSend: (_) {},
                    onStop: () {},
                    onUndo: () {},
                    onClose: () {},
                    onClearSelected: () {},
                    quickText: (kind) => '${kind.name} template',
                    onOpenLink: (_) {},
                  ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('360×640 浮窗夹进屏幕且无 overflow', (tester) async {
    await pumpWindow(tester, view: fixture());

    final window = tester.getRect(
      find.byKey(const Key('translation-adjustment-window')),
    );
    expect(window.width, 344); // min(392, 360 - 16)
    expect(window.height, 600); // min(600, 640 - 16)
    expect(window.left, greaterThanOrEqualTo(8));
    expect(window.top, greaterThanOrEqualTo(8));
    expect(window.right, lessThanOrEqualTo(352));
    expect(window.bottom, lessThanOrEqualTo(632));
    expect(
      find.byKey(const Key('translation-adjustment-input')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('translation-adjustment-send')),
      findsOneWidget,
    );
    // 手机端小按钮同样补到 48dp 命中区（视觉仍是 26-30dp）。
    for (final key in [
      'translation-adjustment-collapse',
      'translation-adjustment-close',
      'translation-adjustment-send',
      'translation-adjustment-quick-split',
      'translation-adjustment-quick-retranslate',
      'translation-adjustment-quick-merge',
      'translation-adjustment-refs-clear',
      'translation-adjustment-undo',
    ]) {
      final size = tester.getSize(find.byKey(Key(key)));
      expect(
        size.width,
        greaterThanOrEqualTo(48),
        reason: '$key 命中区宽度 ${size.width} < 48dp',
      );
      expect(
        size.height,
        greaterThanOrEqualTo(48),
        reason: '$key 命中区高度 ${size.height} < 48dp',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('360×640 快捷动作填入输入框且不挤出窗口', (tester) async {
    await pumpWindow(tester, view: fixture());

    await tester.tap(
      find.byKey(const Key('translation-adjustment-quick-split')),
    );
    await tester.pumpAndSettle();
    final input = find.byKey(const Key('translation-adjustment-input'));
    expect(tester.widget<TextField>(input).controller!.text, 'split template');
    expect(tester.takeException(), isNull);

    // 收起后只剩 49+2 的标题条，展开恢复。
    await tester.tap(find.byKey(const Key('translation-adjustment-collapse')));
    await tester.pumpAndSettle();
    expect(
      tester
          .getSize(find.byKey(const Key('translation-adjustment-window')))
          .height,
      51,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('translation-adjustment-collapse')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('360×640 生成中 / 出错状态无 overflow', (tester) async {
    final data = fixture(busy: true, error: 'fixture error: 连接被重置');
    await pumpWindow(tester, view: data);
    expect(
      find.byKey(const Key('translation-adjustment-error')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('translation-adjustment-stop-glyph')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('桌面浮窗小按钮保持原尺寸（不回归）', (tester) async {
    debugForceMobileLayout = null;
    await pumpWindow(tester, view: fixture(), size: const Size(1000, 720));

    expect(
      tester.getSize(find.byKey(const Key('translation-adjustment-collapse'))),
      const Size(28, 28),
    );
    expect(
      tester.getSize(find.byKey(const Key('translation-adjustment-close'))),
      const Size(28, 28),
    );
    expect(
      tester.getSize(find.byKey(const Key('translation-adjustment-send'))),
      const Size(30, 30),
    );
    expect(
      tester
          .getSize(find.byKey(const Key('translation-adjustment-quick-split')))
          .height,
      26,
    );
    // 引用清除 × 和撤销行桌面仍是原来的小热区（手机端才补到 48）。
    for (final key in [
      'translation-adjustment-refs-clear',
      'translation-adjustment-undo',
    ]) {
      final size = tester.getSize(find.byKey(Key(key)));
      expect(size.width, lessThan(48), reason: '$key 桌面宽度 ${size.width}');
      expect(size.height, lessThan(48), reason: '$key 桌面高度 ${size.height}');
    }
    expect(tester.takeException(), isNull);
  });
}
