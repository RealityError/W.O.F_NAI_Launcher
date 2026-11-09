import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/mobile/mobile_breakpoints.dart';
import 'package:nai_launcher/presentation/ui/gen/gen_fixture.dart';

import '../../../helpers/studio_capture_fonts.dart';
import 'gen_test_harness.dart';

/// G5：生成页手机端 360×640（最小验收尺寸）走查。
///
/// 覆盖主页面、提示词全屏编辑浮层、最近生成浮层、参数抽屉；每个交互后都要求
/// `takeException()` 为空，即没有 RenderFlex overflow / 布局断言。
void main() {
  setUpAll(loadStudioCaptureFonts);
  setUp(() => debugForceMobileLayout = true);
  tearDown(() => debugForceMobileLayout = null);

  Future<void> pumpSmall(WidgetTester tester) async {
    await pumpGen(
      tester,
      data: GenFixture.view(),
      window: 360 + genRail,
      height: 640,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('360×640 主页面无 overflow', (tester) async {
    await pumpSmall(tester);

    expect(find.byKey(const Key('gen-header')), findsOneWidget);
    // 顶栏在 360dp 下保持单行（4 + 50 + 4 + 1px 边线）。
    expect(
      tester.getSize(find.byKey(const Key('gen-header'))).height,
      59,
      reason: '360×640 手机顶栏应单行 59dp',
    );
    expect(find.byKey(const Key('gen-params')), findsOneWidget);
    expect(find.byKey(const Key('gen-generate-bar')), findsOneWidget);
    expect(find.byKey(const Key('gen-params-toggle')), findsOneWidget);
    // 手机画布底部只留一条动作条：显示设置与图片动作同一行，信息条收进弹层。
    expect(find.byKey(const Key('gen-bar-info')), findsNothing);
    expect(find.byKey(const Key('gen-bar-mobile')), findsOneWidget);
    final display = tester.getRect(find.byKey(const Key('gen-display')));
    final pin = tester.getRect(find.byKey(const Key('gen-pin')));
    expect(
      (display.top - pin.top).abs(),
      lessThan(1),
      reason: '手机端显示设置和图片动作应在同一条工具条里',
    );
    // 画布图片高度不再被两条浮条上下夹住：360×640 下应明显超过旧版 ~300dp。
    final tile = tester.getSize(find.byKey(const Key('gen-tile-i1')));
    expect(
      tile.height,
      greaterThan(320),
      reason: '360×640 下画布图片高度 ${tile.height} 太小',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('360×640 提示词编辑浮层 -> 工具菜单 -> 全屏编辑器', (tester) async {
    await pumpSmall(tester);

    await tester.tap(find.byKey(const Key('gen-mobile-editor')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gen-mobile-editor-panel')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 工具菜单在手机端是底部面板，内容超高时内部滚动。
    await tester.tap(find.byKey(const Key('gen-tool-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gen-fullscreen')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 全屏编辑器在 360dp 宽 / 640dp 高下必须放得下。
    await tester.ensureVisible(find.byKey(const Key('gen-fullscreen')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gen-fullscreen')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gen-fullscreen-editor')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('gen-fullscreen-editor'))).width,
      lessThanOrEqualTo(360),
    );
    // 640 高下头部分段行仍是 48 高命中区，正 / 负向可切换。
    expect(
      tester.getSize(find.byKey(const Key('gen-fullscreen-tabs'))).height,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(find.byKey(const Key('gen-fullscreen-tab-negative')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gen-fullscreen-tab-positive')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('gen-fullscreen-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gen-fullscreen-editor')), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('gen-mobile-overlay-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gen-mobile-editor-panel')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('360×640 最近生成浮层与长按菜单无 overflow', (tester) async {
    await pumpSmall(tester);

    await tester.tap(find.byKey(const Key('gen-mobile-history')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gen-mobile-history-panel')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 长按一条历史记录：手机端弹底部操作面板。
    final batch = find.byKey(const Key('gen-batch-tile-b1'));
    expect(batch, findsOneWidget);
    await tester.longPress(batch);
    await tester.pumpAndSettle();
    final l = AppLocalizations.of(
      tester.element(find.byKey(const Key('gen-mobile-history-panel'))),
    )!;
    expect(find.text(l.gen_copyImage), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 点面板外收起长按菜单，再关掉浮层。
    await tester.tapAt(const Offset(180, 60));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gen-mobile-overlay-close')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('360×640 参数抽屉滚动无 overflow', (tester) async {
    await pumpSmall(tester);

    await tester.tap(find.byKey(const Key('gen-params-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gen-params-drawer')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 抽屉内容比 360×640 高：内部滚动到底不报 overflow。
    final scrollable = find.descendant(
      of: find.byKey(const Key('gen-params-drawer')),
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsWidgets);
    await tester.drag(scrollable.first, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('gen-params-close')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
