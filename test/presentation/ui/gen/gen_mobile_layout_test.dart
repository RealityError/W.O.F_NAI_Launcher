import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/mobile/mobile_breakpoints.dart';
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

  Future<void> pumpMobile(WidgetTester tester) async {
    // pumpGen 内部按“窗口宽 − genRail”计算页面宽度；手机端没有左侧主导航，
    // 加上 genRail 让页面实际宽度等于 360dp。
    await pumpGen(
      tester,
      data: GenFixture.view(),
      window: 360 + genRail,
      height: 780,
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'mobile generation layout renders canvas, params and generate bar',
    (tester) async {
      await pumpMobile(tester);

      expect(find.byType(GenerationPage), findsOneWidget);
      expect(find.byKey(const Key('gen-canvas-host')), findsNothing);
      expect(find.byKey(const Key('gen-mobile-editor')), findsOneWidget);
      expect(find.byKey(const Key('gen-mobile-history')), findsOneWidget);
      expect(find.byKey(const Key('gen-params')), findsOneWidget);
      expect(find.byKey(const Key('gen-generate-bar')), findsOneWidget);
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
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('gen-mobile-overlay-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gen-mobile-history-panel')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
