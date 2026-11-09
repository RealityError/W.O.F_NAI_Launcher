import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/mobile/mobile_breakpoints.dart';
import 'package:nai_launcher/presentation/ui/online/online_contract.dart';
import 'package:nai_launcher/presentation/ui/online/online_fixture.dart';

import '../../../helpers/studio_capture_fonts.dart';
import 'online_test_harness.dart';

/// 在线画廊手机端（360dp 竖屏）走查：
/// 单列骨架、卡片单击开全屏查看器、长按出上下文菜单、左栏进底部弹层、
/// 多选条整宽不溢出；桌面端存在性断言（在线工具栏 / 左栏 / 检查器）不适用。
void main() {
  setUpAll(loadStudioCaptureFonts);

  setUp(() => debugForceMobileLayout = true);
  tearDown(() => debugForceMobileLayout = null);

  Future<void> pumpMobile(
    WidgetTester tester, {
    OnlineViewData? data,
    RecordingOnlineActions? rec,
    double width = 360,
    double height = 780,
    String locale = 'zh',
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data0 = data ?? OnlineFixture.view();
    await tester.pumpWidget(
      onlineApp(
        data0,
        (rec ?? RecordingOnlineActions()).actions,
        locale: locale,
      ),
    );
    await precacheOnline(tester, data0);
  }

  testWidgets('360dp 单列骨架：手机工具栏，桌面左右栏不出现', (tester) async {
    await pumpMobile(tester);
    expect(find.byKey(const Key('online-toolbar-mobile')), findsOneWidget);
    expect(find.byKey(const Key('online-toolbar')), findsNothing);
    expect(find.byKey(const Key('online-sidebar')), findsNothing);
    expect(find.byKey(const Key('online-inspector')), findsNothing);
    expect(find.byKey(const Key('online-wall')), findsOneWidget);
    expect(find.byKey(const Key('online-mobile-browse')), findsOneWidget);
    expect(find.byKey(const Key('online-mobile-multi')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('360dp 单击卡片直接开全屏查看器，信息面板可开可关', (tester) async {
    final data = OnlineFixture.view();
    await pumpMobile(tester, data: data);
    final key = data.list.items.first.key;
    await tester.tap(find.byKey(Key('online-card-$key')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('online-viewer')), findsOneWidget);
    // 手机上默认只看大图，右侧 380 信息栏不在查看器里。
    expect(find.byKey(const Key('online-viewer-info-sheet')), findsNothing);
    await tester.tap(find.byKey(const Key('online-viewer-info-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('online-viewer-info-sheet')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('online-viewer-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('online-viewer')), findsNothing);
  });

  testWidgets('360dp 长按卡片弹出上下文菜单，下载可点', (tester) async {
    final rec = RecordingOnlineActions();
    final data = OnlineFixture.view();
    await pumpMobile(tester, data: data, rec: rec);
    final key = data.list.items.first.key;
    final card = find.byKey(Key('online-card-$key'));
    expect(card, findsOneWidget);
    // 卡片底部常显操作条会拦截手势，按图片左上角的长按。
    await tester.longPressAt(tester.getTopLeft(card) + const Offset(12, 12));
    await tester.pumpAndSettle();
    final l = AppLocalizations.of(tester.element(find.byType(Scaffold).first))!;
    expect(find.byType(ListTile), findsWidgets);
    final download = find.textContaining(l.online_download).first;
    expect(download, findsOneWidget);
    await tester.tap(download);
    await tester.pumpAndSettle();
    expect(rec.downloads, isNotEmpty);
    expect(rec.downloads.first.$1, [key]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('360dp 左栏进底部弹层', (tester) async {
    await pumpMobile(tester);
    await tester.tap(find.byKey(const Key('online-mobile-browse')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('online-sidebar')), findsOneWidget);
    expect(find.byKey(const Key('online-sidebar-close')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('online-sidebar-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('online-sidebar')), findsNothing);
  });

  testWidgets('360dp 多选条整宽不溢出', (tester) async {
    await pumpMobile(tester);
    await tester.tap(find.byKey(const Key('online-mobile-multi')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('online-selection-bar')), findsOneWidget);
    expect(find.byKey(const Key('online-sel-download')), findsOneWidget);
    expect(find.byKey(const Key('online-sel-copy')), findsOneWidget);
    expect(find.byKey(const Key('online-sel-more')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('online-sel-exit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('online-selection-bar')), findsNothing);
  });

  testWidgets('360dp 各来源 / 模式 / 语言不溢出', (tester) async {
    for (final (source, mode) in [
      (OnlineSource.aiTag, OnlineMode.search),
      (OnlineSource.aiTag, OnlineMode.ranking),
      (OnlineSource.aiTag, OnlineMode.favorites),
      (OnlineSource.danbooru, OnlineMode.search),
      (OnlineSource.danbooru, OnlineMode.ranking),
      (OnlineSource.gelbooru, OnlineMode.favorites),
    ]) {
      for (final locale in ['zh', 'en', 'ja', 'ko']) {
        await pumpMobile(
          tester,
          data: OnlineFixture.view(source: source, mode: mode),
          locale: locale,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '${source.name}/${mode.name} @ $locale',
        );
      }
    }
  });
}
