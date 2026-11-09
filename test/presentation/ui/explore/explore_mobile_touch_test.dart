import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/mobile/mobile_breakpoints.dart';
import 'package:nai_launcher/presentation/ui/explore/explore_contract.dart';
import 'package:nai_launcher/presentation/ui/explore/explore_fixture.dart';
import 'package:nai_launcher/presentation/ui/explore/explore_page.dart';

import '../../../helpers/studio_capture_fonts.dart';
import 'explore_test_harness.dart';

/// 手机端风格探索的触控收尾回归：关键图标命中区 ≥48dp、360dp 不溢出、桌面不变。
void main() {
  Future<void> pumpMobile(
    WidgetTester tester, {
    Size size = const Size(360, 780),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loadStudioCaptureFonts();
    final view = ExploreFixture.view();
    await tester.pumpWidget(
      exploreApp(
        StyleExplorePage(
          data: view,
          actions: ExploreActions.none,
          editor: (context, parts) => Container(
            key: const Key('explore-editor-stub'),
            child: const Align(
              alignment: Alignment.topLeft,
              child: Text('editor'),
            ),
          ),
        ),
      ),
    );
    await precacheExplore(tester, [
      for (final c in view.run?.candidates ?? const <ExploreCandidate>[]) ...[
        ?c.thumb,
        ?c.image,
      ],
    ]);
    await tester.pumpAndSettle();
  }

  void expectMinTouchTarget(WidgetTester tester, String key) {
    final size = tester.getSize(find.byKey(Key(key)));
    expect(
      size.width,
      greaterThanOrEqualTo(48),
      reason: '$key 命中宽度应 ≥48dp，实际 ${size.width}',
    );
    expect(
      size.height,
      greaterThanOrEqualTo(48),
      reason: '$key 命中高度应 ≥48dp，实际 ${size.height}',
    );
  }

  void expectNoException(WidgetTester tester, String where) {
    final exception = tester.takeException();
    expect(exception, isNull, reason: '$where 出现异常：$exception');
  }

  setUp(() => debugForceMobileLayout = true);
  tearDown(() => debugForceMobileLayout = null);

  testWidgets('360dp 舞台工具栏图标命中区 ≥48dp 且不溢出', (tester) async {
    for (final size in const [Size(360, 640), Size(360, 780)]) {
      await pumpMobile(tester, size: size);
      await tester.tap(find.byKey(const Key('explore-mobile-stage')));
      await tester.pumpAndSettle();
      // 同一 tester 重 pump 会复用页面 State：先退出上一轮留下的多选状态。
      if (find.byKey(const Key('explore-select-done')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const Key('explore-select-done')));
        await tester.pumpAndSettle();
      }
      expectNoException(tester, '${size.height}:舞台');

      expectMinTouchTarget(tester, 'explore-run-button');
      expectMinTouchTarget(tester, 'explore-inspector-toggle');
      expectMinTouchTarget(tester, 'explore-sort');
      expectMinTouchTarget(tester, 'explore-tab-candidates');
      expectMinTouchTarget(tester, 'explore-tab-evolution');
      expectMinTouchTarget(tester, 'explore-filter-all');
      expectMinTouchTarget(tester, 'explore-pick-r3');
      expectMinTouchTarget(tester, 'explore-heart-c27');
      expectMinTouchTarget(tester, 'explore-card-c27');
      expectNoException(tester, '${size.height}:舞台尺寸断言后');

      // 进入多选：勾选圈同样 ≥48dp，卡片仍可点。
      await tester.tap(find.byKey(const Key('explore-select')));
      await tester.pumpAndSettle();
      expectMinTouchTarget(tester, 'explore-check-c27');
      expectNoException(tester, '${size.height}:多选');
    }
  });

  testWidgets('360dp 多选浮条整宽横向滚动、可关闭且不溢出', (tester) async {
    await pumpMobile(tester, size: const Size(360, 640));
    await tester.tap(find.byKey(const Key('explore-mobile-stage')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('explore-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('explore-check-c27')));
    await tester.pumpAndSettle();
    expectNoException(tester, '多选浮条出现');

    final bar = find.byKey(const Key('explore-selection-bar'));
    expect(bar, findsOneWidget);
    final barRect = tester.getRect(bar);
    expect(barRect.left, greaterThanOrEqualTo(0));
    expect(barRect.height, greaterThanOrEqualTo(48));

    // 浮条内的按钮命中区都 ≥48dp（横向滚动时会有一部分在屏幕外）。
    for (final key in const [
      'explore-sel-fav',
      'explore-sel-group',
      'explore-sel-block',
      'explore-sel-delete',
      'explore-sel-close',
    ]) {
      expectMinTouchTarget(tester, key);
    }

    // 滚到最右后点关闭：浮条消失、多选退出。
    await tester.ensureVisible(find.byKey(const Key('explore-sel-close')));
    await tester.pumpAndSettle();
    expectNoException(tester, '多选浮条横向滚动');
    await tester.tap(find.byKey(const Key('explore-sel-close')));
    await tester.pumpAndSettle();
    expect(bar, findsNothing);
    expect(find.byKey(const Key('explore-select')), findsOneWidget);
  });

  testWidgets('360dp 检查器 / 详情信息抽屉关闭按钮 ≥48dp', (tester) async {
    await pumpMobile(tester, size: const Size(360, 640));
    await tester.tap(find.byKey(const Key('explore-mobile-stage')));
    await tester.pumpAndSettle();

    // 检查器整宽覆盖，头部关闭 48。
    await tester.tap(find.byKey(const Key('explore-inspector-toggle')));
    await tester.pumpAndSettle();
    expectNoException(tester, '检查器打开');
    expectMinTouchTarget(tester, 'explore-drawer-close');
    await tester.tap(find.byKey(const Key('explore-drawer-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('explore-drawer-close')), findsNothing);

    // 双击卡片进详情，打开信息抽屉：关闭 48。
    await tester.tap(find.byKey(const Key('explore-card-c27')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const Key('explore-card-c27')));
    await tester.pumpAndSettle();
    expectNoException(tester, '详情打开');
    await tester.tap(find.byKey(const Key('viewer-info-toggle')));
    await tester.pumpAndSettle();
    expectNoException(tester, '详情信息抽屉打开');
    expectMinTouchTarget(tester, 'explore-detail-info-close');
  });

  testWidgets('桌面端命中区与视觉尺寸保持原样', (tester) async {
    debugForceMobileLayout = false;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loadStudioCaptureFonts();
    final view = ExploreFixture.view();
    await tester.pumpWidget(
      exploreApp(
        StyleExplorePage(
          data: view,
          actions: ExploreActions.none,
          editor: (context, parts) => Container(
            key: const Key('explore-editor-stub'),
            child: const Align(
              alignment: Alignment.topLeft,
              child: Text('editor'),
            ),
          ),
        ),
      ),
    );
    await precacheExplore(tester, [
      for (final c in view.run?.candidates ?? const <ExploreCandidate>[]) ...[
        ?c.thumb,
        ?c.image,
      ],
    ]);
    await tester.pumpAndSettle();

    // 小图标的视觉/命中尺寸保持桌面原值，不被 48 命中区撑大。
    expect(
      tester.getSize(find.byKey(const Key('explore-heart-c27'))),
      const Size(26, 26),
    );
    expect(
      tester.getSize(find.byKey(const Key('explore-pick-r3'))).height,
      lessThan(48),
    );
    expect(
      tester.getSize(find.byKey(const Key('explore-inspector-toggle'))).width,
      28,
    );
    expect(tester.getSize(find.byKey(const Key('explore-sort'))).width, 28);

    // 桌面多选浮条保持 44 高（手机端才是 60）。
    await tester.tap(find.byKey(const Key('explore-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('explore-check-c27')));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('explore-selection-bar'))).height,
      44,
    );
    expect(
      tester.getSize(find.byKey(const Key('explore-check-c27'))),
      const Size(22, 22),
    );
  });
}
