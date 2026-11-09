import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/utils/localization_extension.dart';
import 'package:nai_launcher/presentation/mobile/mobile_breakpoints.dart';
import 'package:nai_launcher/presentation/ui/refs/refs_contract.dart';
import 'package:nai_launcher/presentation/ui/refs/refs_fixture.dart';
import 'package:nai_launcher/presentation/ui/refs/refs_page.dart';

import '../../../helpers/studio_capture_fonts.dart';
import 'refs_test_harness.dart';

/// 360×780 手机竖屏：手机分支由 `debugForceMobileLayout` 决定，不依赖窗口宽度。
Future<RecordingRefsActions> pumpRefsMobile(
  WidgetTester tester, {
  String locale = 'zh',
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 780);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await loadStudioCaptureFonts();
  final rec = RecordingRefsActions();
  final data = RefsFixture.vibe();
  await tester.pumpWidget(
    refsApp(
      RefsLibraryPage(data: data, actions: rec.actions),
      locale: locale,
    ),
  );
  await precacheRefs(tester, [for (final e in data.entries) ?e.thumb]);
  await tester.pumpAndSettle();
  return rec;
}

void main() {
  setUp(() => debugForceMobileLayout = true);
  tearDown(() => debugForceMobileLayout = null);

  testWidgets('参考库手机端是单列：手机工具栏 + 卡片墙，没有桌面三栏', (tester) async {
    await pumpRefsMobile(tester);

    expect(find.byKey(const Key('refs-toolbar-mobile')), findsOneWidget);
    expect(find.byKey(const Key('refs-filter-row')), findsOneWidget);
    expect(find.byKey(const Key('refs-card-c11')), findsOneWidget);

    // 桌面三栏与 61 高工具栏在手机上不渲染。
    expect(find.byKey(const Key('refs-sidebar')), findsNothing);
    expect(find.byKey(const Key('refs-inspector')), findsNothing);
    expect(find.byKey(const Key('refs-toolbar')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('单击卡片打开整宽大图详情', (tester) async {
    await pumpRefsMobile(tester);

    await tester.tapAt(
      tester.getTopLeft(find.byKey(const Key('refs-card-c11'))) +
          const Offset(20, 20),
    );
    await tester.pumpAndSettle();

    final detail = find.byKey(const Key('refs-detail'));
    expect(detail, findsOneWidget);
    expect(tester.getSize(detail).width, greaterThan(300));
    expect(find.byKey(const Key('refs-detail-stage')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('长按卡片弹出底部菜单（桌面右键的替代）', (tester) async {
    await pumpRefsMobile(tester);
    final l = tester.element(find.byType(RefsMobileToolbar)).l10n;

    await tester.longPressAt(
      tester.getTopLeft(find.byKey(const Key('refs-card-c11'))) +
          const Offset(10, 10),
    );
    await tester.pumpAndSettle();

    expect(find.text(l.refs_addToGeneration), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('左栏入口弹出整宽底部弹层，关闭按钮可用', (tester) async {
    await pumpRefsMobile(tester);

    await tester.tap(find.byKey(const Key('refs-mobile-nav')));
    await tester.pumpAndSettle();

    final nav = find.byKey(const Key('refs-sidebar'));
    expect(nav, findsOneWidget);
    expect(tester.getSize(nav).width, greaterThan(300));
    expect(find.byKey(const Key('refs-nav-close')), findsOneWidget);

    await tester.tap(find.byKey(const Key('refs-nav-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('refs-sidebar')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('排序菜单可切换并回调', (tester) async {
    final rec = await pumpRefsMobile(tester);
    final l = tester.element(find.byType(RefsMobileToolbar)).l10n;

    await tester.tap(find.byKey(const Key('refs-mobile-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.refs_sortName).last);
    await tester.pumpAndSettle();

    expect(rec.filters.last.sort, RefsSort.name);
    expect(tester.takeException(), isNull);
  });

  testWidgets('四种语言 360dp 不溢出', (tester) async {
    for (final locale in ['zh', 'en', 'ja', 'ko']) {
      await pumpRefsMobile(tester, locale: locale);
      expect(tester.takeException(), isNull, reason: locale);
    }
  });
}
