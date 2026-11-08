// 大图查看器手机布局（360dp 竖屏）：顶栏/胶片条/信息抽屉/长按更多/全屏控件。
// 桌面端行为（快捷键帽、悬停显隐胶片条）由既有 viewer_test.dart 覆盖。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/mobile/mobile_breakpoints.dart';
import 'package:nai_launcher/presentation/ui/viewer/viewer_contract.dart';
import 'package:nai_launcher/presentation/ui/viewer/viewer_fixture.dart';
import 'package:nai_launcher/presentation/ui/viewer/viewer_parts.dart';
import 'package:nai_launcher/presentation/ui/viewer/viewer_stage.dart';

import 'viewer_test_harness.dart';

void main() {
  setUp(() => debugForceMobileLayout = true);
  tearDown(() => debugForceMobileLayout = null);

  late RecordingViewerActions rec;
  setUp(() => rec = RecordingViewerActions());

  Future<void> mobile(
    WidgetTester t,
    ViewerViewData data, {
    double height = 780,
    double width = 360,
  }) => pumpViewer(
    t,
    data: data,
    actions: rec.actions,
    window: width + viewerRail,
    height: height,
  );

  Future<void> done(WidgetTester t) => t.pumpWidget(const SizedBox());

  testWidgets('手机顶栏与胶片条在 360dp 内排得下且无 overflow', (t) async {
    final data = ViewerFixture.gallery();
    await mobile(t, data);
    expect(t.takeException(), isNull);
    expect(find.byKey(const Key('viewer-topbar')), findsOneWidget);
    expect(
      t.getSize(find.byKey(const Key('viewer-topbar'))).height,
      ViewerStage.mobileTopHeight,
    );
    // 手机顶栏不渲染桌面的快捷键帽。
    expect(find.byType(ViewerKeycap), findsNothing);
    expect(find.byKey(const Key('viewer-filmstrip')), findsOneWidget);

    // 胶片条是横滑列表：手指往左拖，滚动位置前进。
    final scrollable = t.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('viewer-filmstrip')),
        matching: find.byType(Scrollable),
      ),
    );
    final before = scrollable.position.pixels;
    await t.drag(
      find.byKey(const Key('viewer-filmstrip')),
      const Offset(-140, 0),
    );
    await t.pumpAndSettle();
    expect(scrollable.position.pixels, greaterThan(before));
    expect(t.takeException(), isNull);
    await done(t);
  });

  testWidgets('点胶片条缩略图切换当前张', (t) async {
    final data = ViewerFixture.gallery();
    await mobile(t, data);
    final index = data.items.indexWhere((e) => e.key == data.currentKey);
    final other = data.items[index - 1 < 0 ? index + 1 : index - 1];
    await t.tap(find.byKey(Key('viewer-film-${other.key}')));
    await t.pumpAndSettle();
    expect(rec.calls, contains('select:${other.key}'));
    await done(t);
  });

  testWidgets('长按照片打开手机底部「更多」面板', (t) async {
    final data = ViewerFixture.gallery();
    await mobile(t, data);
    expect(find.byKey(const Key('viewer-more')), findsNothing);

    await t.longPress(find.byKey(const Key('viewer-view')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('viewer-more')), findsOneWidget);

    // 手机端弹层是通栏底部面板，不是贴锚点的桌面浮层。
    final width = t.getSize(find.byKey(const Key('viewer-more'))).width;
    expect(width, greaterThan(300));

    // 点面板外的遮罩收起。
    await t.tapAt(const Offset(180, 40));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('viewer-more')), findsNothing);
    await done(t);
  });

  testWidgets('信息抽屉在手机上整屏宽，「更多」也走底部面板', (t) async {
    final data = ViewerFixture.gallery(infoOpen: false);
    await mobile(t, data);
    expect(find.byKey(const Key('viewer-info')), findsNothing);

    await t.tap(find.byKey(const Key('viewer-info-toggle')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('viewer-drawer')), findsOneWidget);
    expect(find.byKey(const Key('viewer-info')), findsOneWidget);
    expect(t.getSize(find.byKey(const Key('viewer-info'))).width, 360);

    await t.tap(find.byKey(const Key('viewer-info-more')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('viewer-more')), findsOneWidget);
    await done(t);
  });

  testWidgets('手机全屏：控件常显，点图片切换显隐', (t) async {
    final data = ViewerFixture.gallery(fullscreen: true);
    await mobile(t, data);
    expect(find.byKey(const Key('viewer-fullscreen-badge')), findsOneWidget);
    expect(find.byKey(const Key('viewer-filmstrip')), findsOneWidget);
    // 全屏角标换成图标按钮，不再带键盘帽。
    expect(find.byType(ViewerKeycap), findsNothing);

    // 桌面端 2 秒自动隐藏；手机端不能隐藏，否则触屏再也没有「退出全屏」。
    await t.pump(const Duration(seconds: 3));
    expect(find.byKey(const Key('viewer-fullscreen-badge')), findsOneWidget);
    expect(find.byKey(const Key('viewer-filmstrip')), findsOneWidget);

    Future<void> tapImage() async {
      await t.tap(find.byKey(const Key('viewer-view')));
      // 图片同时挂了双击缩放，单击要等双击判定超时。
      await t.pump(const Duration(milliseconds: 350));
      await t.pumpAndSettle();
    }

    await tapImage();
    expect(find.byKey(const Key('viewer-fullscreen-badge')), findsNothing);
    expect(find.byKey(const Key('viewer-filmstrip')), findsNothing);

    await tapImage();
    expect(find.byKey(const Key('viewer-fullscreen-badge')), findsOneWidget);
    expect(find.byKey(const Key('viewer-filmstrip')), findsOneWidget);
    await done(t);
  });

  testWidgets('手机全屏的退出按钮回到非全屏', (t) async {
    final data = ViewerFixture.gallery(fullscreen: true);
    await mobile(t, data);
    await t.tap(find.byKey(const Key('viewer-fullscreen-exit')));
    await t.pumpAndSettle();
    expect(rec.calls, contains('fullscreen:false'));
    await done(t);
  });

  testWidgets('360×640 竖屏：顶栏/胶片条/信息抽屉/更多面板都放得下', (t) async {
    final data = ViewerFixture.gallery();
    // 640dp 是最小验收高度：顶栏 + 舞台 + 胶片条都要挤得下。
    await mobile(t, data, height: 640);
    expect(find.byKey(const Key('viewer-topbar')), findsOneWidget);
    expect(find.byKey(const Key('viewer-filmstrip')), findsOneWidget);
    expect(t.takeException(), isNull);

    // 信息抽屉在手机上整屏宽、内部滚动。
    await t.tap(find.byKey(const Key('viewer-info-toggle')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('viewer-drawer')), findsOneWidget);
    expect(find.byKey(const Key('viewer-info')), findsOneWidget);
    expect(t.takeException(), isNull);

    // 「更多」走通栏底部面板，不能溢出。
    await t.tap(find.byKey(const Key('viewer-info-more')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('viewer-more')), findsOneWidget);
    expect(t.takeException(), isNull);
    await done(t);
  });
}
