import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/mobile/mobile_breakpoints.dart';
import 'package:nai_launcher/presentation/ui/tools/tools_fixture.dart';

import 'tools_test_harness.dart';

/// 导演工具手机端布局（360dp 竖屏）回归测试。
///
/// 桌面三栏布局由既有 tools_director_test.dart 覆盖；这里只验证手机分支：
/// 不内联 320 宽的右栏（避免溢出），右栏改为页面内浮层且可开可关。
void main() {
  setUp(() => debugForceMobileLayout = true);
  tearDown(() => debugForceMobileLayout = null);

  Future<void> pumpPhone(WidgetTester tester) => pumpToolsDirector(
    tester,
    data: ToolsFixture.removeBg(),
    width: 360,
    height: 780,
  );

  testWidgets('360dp 导演工具不溢出，右栏不内联渲染', (tester) async {
    await pumpPhone(tester);

    expect(find.byKey(const Key('tools-director')), findsOneWidget);
    expect(find.byKey(const Key('tools-director-side')), findsNothing);
    expect(find.byKey(const Key('tools-director-mobile-side')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('右栏浮层可打开、可关闭', (tester) async {
    await pumpPhone(tester);

    await tester.tap(find.byKey(const Key('tools-director-mobile-side')));
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
}
