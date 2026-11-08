import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/mobile/mobile_breakpoints.dart';
import 'package:nai_launcher/presentation/ui/tools/tools_fixture.dart';

import 'tools_test_harness.dart';

/// 导演工具手机端布局（方案 A，360dp 竖屏）回归测试。
///
/// 桌面三栏布局由既有 tools_director_test.dart 覆盖；这里只验证手机分支：
/// 左栏工具清单与右栏都不内联，改画布优先 + 底部工具条；
/// 进入页面直接展开当前工具参数，底部工具条常驻，面板开着也能原地换工具。
void main() {
  setUp(() => debugForceMobileLayout = true);
  tearDown(() => debugForceMobileLayout = null);

  Future<void> pumpPhone(WidgetTester tester) => pumpToolsDirector(
    tester,
    data: ToolsFixture.removeBg(),
    width: 360,
    height: 780,
  );

  Future<void> closeSide(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('tools-director-mobile-side-close')));
    await tester.pumpAndSettle();
  }

  testWidgets('进入即展开当前工具参数，再点当前工具收起', (tester) async {
    await pumpPhone(tester);

    expect(find.byKey(const Key('tools-director')), findsOneWidget);
    // 桌面的左栏清单与右栏都不内联。
    expect(find.byKey(const Key('tools-director-tools')), findsNothing);
    // 进来就能看到参数面板（不用先点工具）。
    expect(
      find.byKey(const Key('tools-director-mobile-side-panel')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('tools-director-side')), findsOneWidget);
    expect(
      find.byKey(const Key('tools-director-mobile-toolbar')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    // 再点当前工具 = 收起面板，露出画布。
    await tester.tap(
      find.byKey(const Key('tools-mobile-removeBackground')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('tools-director-mobile-side-panel')),
      findsNothing,
    );
    expect(find.byKey(const Key('tools-compare-mobile')), findsOneWidget);
    expect(find.byKey(const Key('tools-input-chip')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 再点一下同一个工具又展开。
    await tester.tap(
      find.byKey(const Key('tools-mobile-removeBackground')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('tools-director-mobile-side-panel')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('面板开着点别的工具，原地切换参数', (tester) async {
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
    // 面板没关，内容切到「上色」。
    expect(find.text('上色'), findsWidgets);
    expect(tester.takeException(), isNull);

    await closeSide(tester);
    expect(
      find.byKey(const Key('tools-director-mobile-side-panel')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('输入胶囊打开输入队列弹层，可关闭', (tester) async {
    await pumpPhone(tester);
    await closeSide(tester);

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
