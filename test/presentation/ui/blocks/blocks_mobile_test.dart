import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/utils/localization_extension.dart';
import 'package:nai_launcher/presentation/mobile/mobile_breakpoints.dart';
import 'package:nai_launcher/presentation/ui/blocks/blocks_contract.dart';
import 'package:nai_launcher/presentation/ui/blocks/blocks_fixture.dart';
import 'package:nai_launcher/presentation/ui/blocks/blocks_page.dart';
import 'package:nai_launcher/presentation/ui/blocks/blocks_wall.dart';

import '../../../helpers/studio_capture_fonts.dart';
import 'blocks_test_harness.dart';

/// 360×780 手机竖屏：手机分支由 `debugForceMobileLayout` 决定，不依赖窗口宽度。
Future<void> pumpBlocksMobile(
  WidgetTester tester, {
  String locale = 'zh',
  BlocksLibraryViewData? data,
  List<BlockThumbPick>? galleryPicks,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 780);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await loadStudioCaptureFonts();
  final rec = RecordingBlocks(galleryPicks: galleryPicks);
  final view =
      data ??
      BlocksFixture.library(image: blocksTestImage, view: BlocksView.masonry);
  await tester.pumpWidget(
    blocksApp(
      BlocksLibraryPage(data: view, actions: rec.library),
      locale: locale,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => debugForceMobileLayout = true);
  tearDown(() => debugForceMobileLayout = null);

  testWidgets('块库手机端是单列：手机工具栏 + 卡片墙，没有桌面三栏', (tester) async {
    await pumpBlocksMobile(tester);

    expect(find.byKey(const Key('blocks-toolbar-mobile')), findsOneWidget);
    expect(find.byKey(const Key('blocks-filter-row')), findsOneWidget);
    expect(find.byType(BlocksWall), findsOneWidget);
    expect(find.byKey(const Key('blocks-card-y99')), findsOneWidget);

    // 桌面三栏（左栏 / 详情 / 61 高工具栏）在手机上不渲染。
    expect(find.byKey(const Key('blocks-nav')), findsNothing);
    expect(find.byKey(const Key('blocks-inspector')), findsNothing);
    expect(find.byKey(const Key('blocks-toolbar')), findsNothing);
    // 卡片大小滑杆在手机上收起。
    expect(find.byKey(const Key('blocks-card-size')), findsNothing);

    expect(tester.takeException(), isNull);
  });

  testWidgets('单击卡片打开整宽详情弹层', (tester) async {
    await pumpBlocksMobile(tester);

    await tester.tap(find.byKey(const Key('blocks-card-y99')));
    await tester.pumpAndSettle();

    final sheet = find.byKey(const Key('blocks-inspector'));
    expect(sheet, findsOneWidget);
    final width = tester.getSize(sheet).width;
    expect(width, greaterThanOrEqualTo(300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('长按卡片弹出底部菜单（桌面右键的替代）', (tester) async {
    await pumpBlocksMobile(tester);
    final l = tester.element(find.byType(BlocksMobileToolbar)).l10n;

    await tester.longPressAt(
      tester.getTopLeft(find.byKey(const Key('blocks-card-y99'))) +
          const Offset(12, 12),
    );
    await tester.pumpAndSettle();

    expect(find.text(l.blocks_edit), findsWidgets);
    expect(find.text(l.blocks_insertToPrompt), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('左栏入口弹出整宽底部弹层，关闭按钮可用', (tester) async {
    await pumpBlocksMobile(tester);

    await tester.tap(find.byKey(const Key('blocks-mobile-nav')));
    await tester.pumpAndSettle();

    final nav = find.byKey(const Key('blocks-nav'));
    expect(nav, findsOneWidget);
    expect(tester.getSize(nav).width, greaterThanOrEqualTo(300));
    expect(find.byKey(const Key('blocks-nav-close')), findsOneWidget);

    await tester.tap(find.byKey(const Key('blocks-nav-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('blocks-nav')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('多选操作条整宽显示且不溢出', (tester) async {
    await pumpBlocksMobile(tester);

    await tester.tap(find.byKey(const Key('blocks-mobile-more')));
    await tester.pumpAndSettle();
    final l = tester.element(find.byType(BlocksMobileToolbar)).l10n;
    await tester.tap(find.text(l.blocks_multiSelect).last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('blocks-card-y99')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('blocks-selection-bar')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('blocks-selection-bar'))).width,
      greaterThan(300),
    );
    expect(find.byKey(const Key('blocks-sel-more')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑弹层把预览面板收成一行入口，点开弹层可多选加图', (tester) async {
    await pumpBlocksMobile(
      tester,
      galleryPicks: [
        for (var i = 0; i < 3; i++)
          BlockThumbPick(blocksTestImage('pick-$i'), 'pick-$i'),
      ],
    );

    await tester.tap(find.byKey(const Key('blocks-card-y99')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('blocks-insp-thumb')));
    await tester.pumpAndSettle();

    // 360dp 放不下 330 的桌面预览面板，收成一行入口。
    expect(find.byKey(const Key('block-edit')), findsOneWidget);
    expect(find.byKey(const Key('block-edit-preview-panel')), findsNothing);
    expect(find.byKey(const Key('block-edit-preview-bar')), findsOneWidget);

    await tester.tap(find.byKey(const Key('block-edit-preview-bar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('block-edit-preview-sheet')), findsOneWidget);
    expect(
      find.byKey(const Key('block-edit-preview-sheet-body')),
      findsOneWidget,
    );

    // 缩略图条的「+」走多选添加：y99 已有 1 张封面，再加 3 张。
    final l = tester.element(find.byKey(const Key('block-edit'))).l10n;
    await tester.tap(find.byKey(const Key('block-edit-add-thumbnails')));
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      expect(find.byKey(Key('block-thumbnail-$i')), findsOneWidget);
    }
    expect(find.text(l.blocks_previewCount(4)), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('block-edit-preview-sheet-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('block-edit-preview-sheet')), findsNothing);
    expect(find.text(l.blocks_previewCount(4)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('四种语言 360dp 不溢出', (tester) async {
    for (final locale in ['zh', 'en', 'ja', 'ko']) {
      await pumpBlocksMobile(tester, locale: locale);
      expect(tester.takeException(), isNull, reason: locale);
    }
  });
}
