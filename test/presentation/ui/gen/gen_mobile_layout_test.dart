import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/mobile/mobile_breakpoints.dart';
import 'package:nai_launcher/presentation/ui/gen/gen_canvas.dart';
import 'package:nai_launcher/presentation/ui/gen/gen_contract.dart';
import 'package:nai_launcher/presentation/ui/gen/gen_fixture.dart';
import 'package:nai_launcher/presentation/ui/gen/gen_page.dart';

import 'gen_test_harness.dart';

/// 生成页手机布局（360dp 竖屏）回归测试。
///
/// 覆盖：画布/参数条/生成条存在、提示词编辑器浮层可开可关、历史浮层可开可关、
/// 全程无 overflow 或异常。桌面三栏布局由既有 gen_*_test.dart 覆盖，不受影响。
void main() {
  setUp(() => debugForceMobileLayout = true);
  tearDown(() => debugForceMobileLayout = null);

  Future<void> pumpMobile(
    WidgetTester tester, {
    bool cameraLocked = false,
  }) async {
    // pumpGen 内部按“窗口宽 − genRail”计算页面宽度；手机端没有左侧主导航，
    // 加上 genRail 让页面实际宽度等于 360dp。
    await pumpGen(
      tester,
      data: GenFixture.view(),
      window: 360 + genRail,
      height: 780,
      cameraLocked: cameraLocked,
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'mobile generation layout renders canvas, params and generate bar',
    (tester) async {
      await pumpMobile(tester);

      expect(find.byType(GenerationPage), findsOneWidget);
      expect(find.byKey(const Key('gen-canvas-host')), findsNothing);
      expect(find.byKey(const Key('gen-params')), findsOneWidget);
      expect(find.byKey(const Key('gen-generate-bar')), findsOneWidget);
      // 编辑 / 最近生成入口在底部生成条两侧，不占顶栏，顶栏保持单行。
      for (final key in ['gen-mobile-editor', 'gen-mobile-history']) {
        expect(find.byKey(Key(key)), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('gen-header')),
            matching: find.byKey(Key(key)),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('gen-generate-bar')),
            matching: find.byKey(Key(key)),
          ),
          findsOneWidget,
        );
      }
      // 手机布局不渲染桌面左栏三栏结构。
      expect(find.byKey(const Key('gen-left')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('prompt editor overlay opens and closes', (tester) async {
    await pumpMobile(tester);

    await tester.tap(find.byKey(const Key('gen-mobile-editor')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gen-mobile-editor-panel')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('gen-mobile-overlay-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gen-mobile-editor-panel')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history overlay opens and closes', (tester) async {
    await pumpMobile(tester);

    await tester.tap(find.byKey(const Key('gen-mobile-history')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gen-mobile-history-panel')), findsOneWidget);
    // 手机端改称「最近生成」，并说明与图库的分工。
    expect(
      tester
          .widget<Text>(find.byKey(const Key('gen-mobile-overlay-title')))
          .data,
      '最近生成',
    );
    expect(
      find.byKey(const Key('gen-mobile-overlay-subtitle')),
      findsOneWidget,
    );
    // 浮层自带标题，栏内不再重复渲染桌面用的收起按钮。
    expect(find.byKey(const Key('gen-collapse-history')), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('gen-mobile-overlay-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gen-mobile-history-panel')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('locked canvas camera offers an unlock action', (tester) async {
    await pumpMobile(tester, cameraLocked: true);
    expect(find.byKey(const Key('gen-mobile-unlock-camera')), findsOneWidget);

    await tester.tap(find.byKey(const Key('gen-mobile-unlock-camera')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gen-mobile-unlock-camera')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unlocked camera shows no unlock action', (tester) async {
    await pumpMobile(tester);
    expect(find.byKey(const Key('gen-mobile-unlock-camera')), findsNothing);
  });

  testWidgets('canvas tile long press asks the wiring for the mobile menu', (
    tester,
  ) async {
    final mobileCalls = <String>[];
    final desktopCalls = <String>[];
    await pumpGen(
      tester,
      data: GenFixture.view(),
      window: 360 + genRail,
      height: 780,
      wrap: (page) => GenCanvasMenuScope(
        onOpen: (_, id, _) => desktopCalls.add(id),
        onOpenMobile: (_, id) => mobileCalls.add(id),
        child: page,
      ),
    );
    await tester.pumpAndSettle();
    final tile = find.byKey(const Key('gen-tile-i1'));
    expect(tile, findsOneWidget);
    await tester.longPress(tile);
    await tester.pumpAndSettle();
    // 手机没有右键：长按走底部菜单入口，不再走桌面右键回调。
    expect(mobileCalls, ['i1']);
    expect(desktopCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history batch long press opens the mobile action sheet', (
    tester,
  ) async {
    await pumpMobile(tester);
    await tester.tap(find.byKey(const Key('gen-mobile-history')));
    await tester.pumpAndSettle();
    final l = AppLocalizations.of(tester.element(find.byType(GenerationPage)))!;

    final tile = find.byKey(const Key('gen-batch-tile-b1'));
    expect(tile, findsOneWidget);
    await tester.longPress(tile);
    await tester.pumpAndSettle();

    // 与桌面右键同源的常用动作；桌面文件管理项（打开文件夹）不出现。
    expect(find.text(l.gen_copyImage), findsOneWidget);
    expect(find.text(l.gen_sendImg2Img), findsOneWidget);
    expect(find.text(l.gen_removeImage), findsOneWidget);
    expect(find.text(l.gen_reveal), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor overlay exposes the mobile resource library menu', (
    tester,
  ) async {
    final recorder = GenRecorder();
    await pumpGen(
      tester,
      data: GenFixture.view(),
      actions: recorder.actions,
      window: 360 + genRail,
      height: 780,
    );
    await tester.pumpAndSettle();
    // 库入口只在编辑浮层里出现，不在底栏占位。
    expect(find.byKey(const Key('gen-mobile-libraries')), findsNothing);

    await tester.tap(find.byKey(const Key('gen-mobile-editor')));
    await tester.pumpAndSettle();
    final l = AppLocalizations.of(tester.element(find.byType(GenerationPage)))!;
    await tester.tap(find.byKey(const Key('gen-mobile-libraries')));
    await tester.pumpAndSettle();

    // 四类资源都有手机入口；块库 / 风格库 / 精准参考库走全屏库页，
    // 图库直接跳现有图库页（同一回调里决定）。
    for (final label in [
      l.blocks_title,
      l.refs_vibeTitle,
      l.refs_preciseTitle,
      l.localGallery_title,
    ]) {
      expect(find.widgetWithText(ListTile, label), findsOneWidget);
    }
    await tester.tap(find.widgetWithText(ListTile, l.blocks_title));
    await tester.pumpAndSettle();
    expect(
      recorder.calls,
      contains('onOpenResourceWindow(FloatingResourceKind.blocks)'),
    );

    await tester.tap(find.byKey(const Key('gen-mobile-libraries')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, l.localGallery_title));
    await tester.pumpAndSettle();
    expect(
      recorder.calls,
      contains('onOpenResourceWindow(FloatingResourceKind.gallery)'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile layout never renders the desktop bridge indicator', (
    tester,
  ) async {
    final base = GenFixture.view();
    await pumpGen(
      tester,
      data: base.copyWith(
        prompt: const GenPromptData(
          bridge: GenBridge(phase: GenBridgePhase.idle, label: 'Krita 桥接'),
        ),
      ),
      window: 360 + genRail,
      height: 780,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gen-mobile-editor')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gen-bridge')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
