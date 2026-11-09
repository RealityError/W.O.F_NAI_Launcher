import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/mobile/mobile_breakpoints.dart';
import 'package:nai_launcher/presentation/ui/explore/explore_contract.dart';
import 'package:nai_launcher/presentation/ui/explore/explore_fixture.dart';
import 'package:nai_launcher/presentation/ui/explore/explore_page.dart';

import '../../../helpers/studio_capture_fonts.dart';
import 'explore_test_harness.dart';

/// 360×780 手机竖屏：手机分支由 `debugForceMobileLayout` 决定，不依赖窗口宽度。
Future<RecordingExploreActions> pumpExploreMobile(
  WidgetTester tester, {
  String locale = 'zh',
  ExploreViewData? data,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 780);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await loadStudioCaptureFonts();
  final rec = RecordingExploreActions();
  final view = data ?? ExploreFixture.view();
  await tester.pumpWidget(
    exploreApp(
      StyleExplorePage(
        data: view,
        actions: rec.actions,
        // 编辑列内容由接线方注入；这里只测页面骨架，用占位编辑器避免把编辑器内部布局算进来。
        editor: (context, parts) => Container(
          key: const Key('explore-editor-stub'),
          padding: const EdgeInsets.all(12),
          child: const Align(
            alignment: Alignment.topLeft,
            child: Text('editor'),
          ),
        ),
      ),
      locale: locale,
    ),
  );
  await precacheExplore(tester, [
    for (final c in view.run?.candidates ?? const <ExploreCandidate>[]) ...[
      ?c.thumb,
      ?c.image,
    ],
  ]);
  await tester.pumpAndSettle();
  return rec;
}

void main() {
  setUp(() => debugForceMobileLayout = true);
  tearDown(() => debugForceMobileLayout = null);

  testWidgets('画风探索手机端是单列：编辑 / 结果切换 + 全宽编辑列', (tester) async {
    await pumpExploreMobile(tester);

    expect(find.byKey(const Key('explore-mobile-switch')), findsOneWidget);
    expect(find.byKey(const Key('explore-mobile-editor')), findsOneWidget);
    expect(find.byKey(const Key('explore-mobile-stage')), findsOneWidget);
    // 默认看编辑列；桌面舞台列 / 检查器 / 拖动条不渲染。
    expect(find.byKey(const Key('explore-editor')), findsOneWidget);
    expect(find.byKey(const Key('explore-header')), findsNothing);
    expect(find.byKey(const Key('explore-editor-resize')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切到结果后舞台单列显示，工具栏不溢出', (tester) async {
    await pumpExploreMobile(tester);

    await tester.tap(find.byKey(const Key('explore-mobile-stage')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('explore-header')), findsOneWidget);
    expect(find.byKey(const Key('explore-editor')), findsNothing);
    expect(find.byKey(const Key('explore-tab-candidates')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('检查器在手机上整宽覆盖舞台，可关闭', (tester) async {
    await pumpExploreMobile(tester);

    await tester.tap(find.byKey(const Key('explore-mobile-stage')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('explore-inspector-toggle')));
    await tester.pumpAndSettle();

    final panel = find.byKey(const Key('explore-inspector-mobile'));
    expect(panel, findsOneWidget);
    expect(tester.getSize(panel).width, greaterThan(300));
    expect(find.byKey(const Key('explore-drawer-close')), findsOneWidget);

    await tester.tap(find.byKey(const Key('explore-drawer-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('explore-inspector-mobile')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('四种语言 360dp 编辑列与结果页都不溢出', (tester) async {
    for (final locale in ['zh', 'en', 'ja', 'ko']) {
      await pumpExploreMobile(tester, locale: locale);
      expect(tester.takeException(), isNull, reason: '$locale editor');

      await tester.tap(find.byKey(const Key('explore-mobile-stage')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$locale stage');
    }
  });
}
