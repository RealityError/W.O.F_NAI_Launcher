import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/mobile/mobile_breakpoints.dart';
import 'package:nai_launcher/presentation/ui/tools/tools_fixture.dart';

import 'tools_test_harness.dart';

/// 导演工具手机端布局（方案 A，360dp 竖屏）回归测试。
///
/// 桌面三栏布局由既有 tools_director_test.dart 覆盖；这里只验证手机分支：
/// 左栏工具清单与右栏都不内联，画布优先 + 常驻运行条 + 底部工具条；
/// 选工具只切换、不弹层，运行按钮就在页面上；弹层只留给「选项」和队列 / 结果。
void main() {
  setUp(() => debugForceMobileLayout = true);
  tearDown(() => debugForceMobileLayout = null);

  Future<void> pumpPhone(WidgetTester tester) => pumpToolsDirector(
    tester,
    data: ToolsFixture.removeBg(),
    width: 360,
    height: 780,
  );

  testWidgets('进入即有运行按钮和工具介绍，选工具不用先进弹层', (tester) async {
    await pumpPhone(tester);

    expect(find.byKey(const Key('tools-director')), findsOneWidget);
    // 桌面的左栏清单与右栏都不内联。
    expect(find.byKey(const Key('tools-director-tools')), findsNothing);
    // 画布 + 常驻运行条 + 底部工具条同页：不用点工具才能“进去”。
    expect(
      find.byKey(const Key('tools-director-mobile-toolbar')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('tools-director-runbar')), findsOneWidget);
    expect(find.byKey(const Key('tools-mobile-run')), findsOneWidget);
    expect(find.text('运行背景移除'), findsOneWidget);
    expect(find.textContaining('抠出人物'), findsOneWidget);
    // 背景移除没有可调选项：不给「选项」入口。
    expect(find.byKey(const Key('tools-mobile-options')), findsNothing);
    expect(
      find.byKey(const Key('tools-director-mobile-side-panel')),
      findsNothing,
    );
    expect(find.byKey(const Key('tools-compare-mobile')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点工具只切换：不弹层；有选项的工具才给「选项」入口', (tester) async {
    final r = ToolsRecorder();
    await pumpToolsDirector(
      tester,
      data: ToolsFixture.emotion(),
      r: r,
      width: 360,
      height: 780,
    );

    // 表情修复有可调选项 → 运行条上给「选项」入口，按钮写「运行表情修复」。
    expect(find.text('运行表情修复'), findsOneWidget);
    expect(find.byKey(const Key('tools-mobile-options')), findsOneWidget);
    expect(
      find.byKey(const Key('tools-director-mobile-side-panel')),
      findsNothing,
    );

    // 「选项」才打开参数弹层，用来调表情 / 强度 / 提示词。
    await tester.tap(find.byKey(const Key('tools-mobile-options')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('tools-director-mobile-side-panel')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('tools-director-side')), findsOneWidget);

    await tester.tap(find.byKey(const Key('tools-director-mobile-side-close')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('tools-director-mobile-side-panel')),
      findsNothing,
    );

    // 底部工具条只上报切换，不打开面板。
    await tester.tap(
      find.byKey(const Key('tools-mobile-colorize')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(r.called('onTool(colorize)'), isTrue);
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

  testWidgets('运行条上的「结果」打开结果弹层', (tester) async {
    await pumpPhone(tester);

    await tester.tap(find.byKey(const Key('tools-mobile-results')));
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
