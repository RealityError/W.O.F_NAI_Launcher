import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/mobile/mobile_breakpoints.dart';
import 'package:nai_launcher/presentation/themes/presets/geist_theme.dart';
import 'package:nai_launcher/presentation/ui/statistics/statistics_contract.dart';
import 'package:nai_launcher/presentation/ui/statistics/statistics_fixture.dart';
import 'package:nai_launcher/presentation/ui/statistics/statistics_page.dart';

import '../../../helpers/studio_capture_fonts.dart';
import 'stats_test_harness.dart';

/// 统计页手机端（360dp 竖屏）走查：
/// 顶栏换成 MobilePageScaffold、范围/仅 NAI 变横向滚动筛选条、KPI 折成 2 列、
/// 日历与产量图横向滚动；任何布局断言都算失败。
void main() {
  setUpAll(loadStudioCaptureFonts);

  setUp(() => debugForceMobileLayout = true);
  tearDown(() => debugForceMobileLayout = null);

  Future<void> pumpMobile(
    WidgetTester tester, {
    StatsViewData? data,
    StatsActions? actions,
    double width = 360,
    double height = 800,
    String locale = 'zh',
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: GeistTheme.light,
        locale: Locale(locale),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: StatisticsPage(
            data: data ?? StatsFixture.view(),
            actions: actions ?? StatsActions.none,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('360dp 概览：手机骨架 + 关键卡片，无 overflow', (tester) async {
    await pumpMobile(tester, height: 2400);

    expect(find.byKey(const Key('stats-mobile-page')), findsOneWidget);
    expect(find.byKey(const Key('stats-mobile-refresh')), findsOneWidget);
    expect(find.byKey(const Key('stats-mobile-filters')), findsOneWidget);
    expect(find.byKey(const Key('stats-range')), findsOneWidget);
    expect(find.byKey(const Key('stats-nai-only')), findsOneWidget);
    // 桌面顶栏在手机上不出现（避免标题 + 范围 + 开关挤成一行）。
    expect(find.byKey(const Key('stats-refresh')), findsNothing);

    // 桌面五格 KPI 折成 2 列。
    expect(find.byKey(const Key('stats-kpis')), findsOneWidget);
    expect(find.byKey(const Key('stats-calendar')), findsOneWidget);
    expect(find.byKey(const Key('stats-production')), findsOneWidget);
    expect(find.byKey(const Key('stats-punch')), findsOneWidget);

    // 日历与产量图在手机端横向滚动而不是裁掉日期/柱子。
    expect(find.byKey(const Key('stats-calendar-scroll')), findsOneWidget);
    expect(find.byKey(const Key('stats-production-scroll')), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('360dp 筛选条与刷新可点', (tester) async {
    final record = RecordingStatsActions();
    await pumpMobile(tester, actions: record.actions, height: 2400);

    await tester.tap(find.byKey(const Key('stats-nai-only')));
    await tester.pumpAndSettle();
    expect(record.naiOnly, [true]);

    // 最后一个范围段（今年）在横向滚动条里，先滚到可见再点。默认范围是「全部」，
    // 已选段点的 onTap 为空，所以点今年。
    final l = AppLocalizations.of(
      tester.element(find.byKey(const Key('stats-mobile-page'))),
    )!;
    final thisYear = find.text(l.stats_rangeThisYear);
    expect(thisYear, findsWidgets);
    await tester.scrollUntilVisible(
      thisYear.last,
      80,
      scrollable: find.descendant(
        of: find.byKey(const Key('stats-mobile-filters')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(thisYear.last);
    await tester.pumpAndSettle();
    expect(record.ranges, contains(StatsRange.thisYear));

    await tester.tap(find.byKey(const Key('stats-mobile-refresh')));
    await tester.pumpAndSettle();
    expect(record.refreshes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('360dp 各语言不溢出', (tester) async {
    for (final locale in ['zh', 'en', 'ja', 'ko']) {
      await pumpMobile(tester, locale: locale, height: 2400);
      expect(tester.takeException(), isNull, reason: '$locale 在 360dp 下溢出');
    }
  });

  testWidgets('360dp 加载 / 空 / 错误状态不溢出', (tester) async {
    for (final data in [
      StatsFixture.view(loading: true),
      StatsFixture.view(empty: true),
      StatsFixture.view(error: 'database is locked'),
    ]) {
      await pumpMobile(tester, data: data);
      expect(tester.takeException(), isNull);
    }
  });
}
