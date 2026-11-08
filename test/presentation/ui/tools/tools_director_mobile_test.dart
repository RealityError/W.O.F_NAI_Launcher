import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/mobile/mobile_breakpoints.dart';
import 'package:nai_launcher/presentation/ui/tools/tools_fixture.dart';

import 'tools_test_harness.dart';

/// 导演工具手机端布局（方案 A，360dp 竖屏）回归测试。
///
/// 桌面三栏布局由既有 tools_director_test.dart 覆盖；这里只验证手机分支：
/// 左栏工具清单与右栏都不内联，改画布优先 + 底部工具条，
/// 参数面板与输入队列是页面内底部弹层。
void main() {
  setUp(() => debugForceMobileLayout = true);
  tearDown(() => debugForceMobileLayout = null);

  Future<void> pumpPhone(WidgetTester tester) => pumpToolsDirector(
    tester,
    data: ToolsFixture.removeBg(),
    width: 360,
    height: 780,
  );

  testWidgets('360dp 导演工具不溢出，左右栏都不内联', (tester) async {
    await pumpPhone(tester);

    expect(find.byKey(const Key('tools-director')), findsOneWidget);
    // 桌面左右栏都不应在手机布局里内联。
    expect(find.byKey(const Key('tools-director-side')), findsNothing);
    expect(find.byKey(const Key('tools-director-tools')), findsNothing);
    // 底部工具条与画布对比方式胶囊在。
    expect(
      find.byKey(const Key('tools-director-mobile-toolbar')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('tools-compare-mobile')), findsOneWidget);
    expect(find.byKey(const Key('tools-input-chip')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点底部工具弹出参数面板，可关闭', (tester) async {
    await pumpPhone(tester);

    await tester.tap(
      find.byKey(const Key('tools-mobile-colorize')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('tools-director-mobile-side-panel')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('tools-director-side')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('tools-director-mobile-side-close')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('tools-director-mobile-side-panel')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('输入胶囊打开输入队列弹层，可关闭', (tester) async {
    await pumpPhone(tester);

    await tester.tap(find.byKey(const Key('tools-input-chip')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('tools-director-mobile-queue-sheet')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('tools-director-queue')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const Key('tools-director-mobile-queue-close')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('tools-director-mobile-queue-sheet')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('参数面板里的「结果」打开结果弹层', (tester) async {
    await pumpPhone(tester);

    await tester.tap(
      find.byKey(const Key('tools-mobile-colorize')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tools-director-mobile-results')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('tools-director-mobile-results-panel')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('tools-dt-results')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const Key('tools-director-mobile-results-close')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('tools-director-mobile-results-panel')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
