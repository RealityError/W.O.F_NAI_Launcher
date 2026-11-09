// 手机端「模型与接口 → 服务商」：列表 → 全屏编辑页 → 模型参数底部弹层，
// 以及模型列表的上移 / 下移排序（48dp 触摸目标，复用 onReorderModels）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/ui/model_providers/model_providers_controller.dart'
    show ProvidersListMode;
import 'package:nai_launcher/presentation/ui/model_providers/model_providers_fixture.dart';
import 'package:nai_launcher/presentation/ui/settings/settings_contract.dart';

import '../../../../helpers/studio_capture_fonts.dart';
import '../../settings/settings_test_harness.dart';
import '../model_providers_harness.dart';

/// 手机竖屏逻辑宽度（dp）。
const _phoneWidths = [360.0, 430.0];

Future<ProvidersRecorder> pumpPhone(
  WidgetTester tester, {
  double width = 360,
}) => pumpProviders(tester, window: width + settingsRail, height: 780);

void main() {
  setUpAll(loadStudioCaptureFonts);
  setUp(() => debugForceMobileSettingsLayout = true);
  tearDown(() => debugForceMobileSettingsLayout = false);

  testWidgets('手机布局：服务商列表 → 全屏编辑页 → 滚到底无溢出', (tester) async {
    for (final width in _phoneWidths) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await pumpPhone(tester, width: width);
      final where = '${width.round()}dp';
      expect(find.byKey(const Key('mp-mobile')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$where 服务商列表');
      // 桌面三栏不出现在手机端。
      expect(find.byKey(const Key('mp-middle')), findsNothing);

      final listScroll = find.byKey(const Key('settings-scroll'));
      await tester.drag(listScroll, const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$where 列表滚动到底');
      await tester.drag(listScroll, const Offset(0, 900));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('mp-provider-ds')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('mp-mobile-editor-scroll')),
        findsOneWidget,
        reason: '$where 编辑页',
      );
      expect(tester.takeException(), isNull, reason: '$where 编辑页首屏');

      final editorScroll = find.byKey(const Key('mp-mobile-editor-scroll'));
      for (var i = 0; i < 8; i++) {
        await tester.drag(editorScroll, const Offset(0, -500));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull, reason: '$where 编辑页滚动到底');

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mp-mobile')), findsOneWidget);
    }
  });

  testWidgets('手机布局：上移 / 下移按钮 48dp，两端禁用，顺序走 onReorderModels', (tester) async {
    final rec = await pumpPhone(tester);
    await tester.tap(find.byKey(const Key('mp-provider-ds')));
    await tester.pumpAndSettle();

    // 手机端提示换成“用上移 / 下移”，不再提拖动。
    expect(find.byKey(const Key('mp-reorder-hint')), findsOneWidget);
    expect(find.text('拖动排序决定功能分配里的默认顺序'), findsNothing);

    final upFlash = find.byKey(const Key('mp-model-up-deepseek-flash'));
    final downFlash = find.byKey(const Key('mp-model-down-deepseek-flash'));
    expect(upFlash, findsOneWidget);
    expect(downFlash, findsOneWidget);
    final upSize = tester.getSize(upFlash);
    expect(upSize.width, greaterThanOrEqualTo(48));
    expect(upSize.height, greaterThanOrEqualTo(48));

    // 第一条没有上一条：上移禁用，点了不产生回调。
    await tester.ensureVisible(upFlash);
    await tester.tap(upFlash);
    await tester.pumpAndSettle();
    expect(rec.calls.where((c) => c.startsWith('reorder:')), isEmpty);

    // 下移第二条 → 顺序交换。
    await tester.ensureVisible(downFlash);
    await tester.tap(downFlash);
    await tester.pumpAndSettle();
    expect(rec.calls.where((c) => c.startsWith('reorder:')).toList(), [
      'reorder:ds:deepseek-v4-pro,deepseek-flash',
    ]);
    // 数据刷新后列表按新顺序渲染。
    expect(
      tester.getTopLeft(find.byKey(const Key('mp-model-deepseek-v4-pro'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('mp-model-deepseek-flash'))).dy,
      ),
    );
    // 新顺序下最后一条的下移禁用。
    await tester.ensureVisible(
      find.byKey(const Key('mp-model-down-deepseek-flash')),
    );
    await tester.tap(find.byKey(const Key('mp-model-down-deepseek-flash')));
    await tester.pumpAndSettle();
    expect(rec.calls.where((c) => c.startsWith('reorder:')).toList(), [
      'reorder:ds:deepseek-v4-pro,deepseek-flash',
    ]);
  });

  testWidgets('手机布局：点模型行打开参数弹层，可编辑并保存', (tester) async {
    final rec = await pumpPhone(tester);
    await tester.tap(find.byKey(const Key('mp-provider-ds')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('mp-model-deepseek-flash')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mp-inspector')), findsOneWidget);
    expect(tester.takeException(), isNull);

    final sheetScroll = find.byKey(const Key('mp-inspector-scroll'));
    await tester.drag(sheetScroll, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(sheetScroll, const Offset(0, 800));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('mp-alias')), 'fast');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mp-inspector-close')));
    await tester.pumpAndSettle();

    // 关闭弹层后编辑页底部出现整宽保存条。
    expect(find.byKey(const Key('mp-mobile-save')), findsOneWidget);
    await tester.tap(find.byKey(const Key('mp-mobile-save')));
    await tester.pumpAndSettle();
    expect(rec.has('save:ds'), isTrue);
    expect(rec.lastSaved!.model('deepseek-flash')!.alias, 'fast');
  });

  testWidgets('手机布局：模型参数弹层底部可直接移除模型', (tester) async {
    final rec = await pumpPhone(tester);
    await tester.tap(find.byKey(const Key('mp-provider-ds')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mp-model-deepseek-flash')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mp-inspector')), findsOneWidget);

    // 桌面端藏在「⋯」菜单里，手机端弹层底部要有显式入口。
    final remove = find.byKey(const Key('mp-mobile-remove-model'));
    expect(remove, findsOneWidget);
    await tester.ensureVisible(remove);
    await tester.pumpAndSettle();
    await tester.tap(remove);
    await tester.pumpAndSettle();

    // 编辑页是独立路由，确认必须用本页对话框（设置页的确认层被盖住），
    // 确认前不写数据。
    expect(find.byKey(const Key('settings-confirm-dialog')), findsOneWidget);
    expect(rec.calls, isEmpty);
    await tester.tap(find.byKey(const Key('confirm-ok')));
    await tester.pumpAndSettle();
    expect(rec.calls, ['remove:ds:deepseek-flash']);
    expect(find.byKey(const Key('mp-inspector')), findsNothing);
    expect(find.byKey(const Key('mp-model-deepseek-flash')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机布局：删除服务商用编辑页自己的确认框', (tester) async {
    final rec = await pumpPhone(tester);
    await tester.tap(find.byKey(const Key('mp-provider-ds')));
    await tester.pumpAndSettle();

    final delete = find.byKey(const Key('mp-delete'));
    await tester.ensureVisible(delete);
    await tester.pumpAndSettle();
    await tester.tap(delete);
    await tester.pumpAndSettle();

    // 设置页的确认层会被编辑页盖住，确认框必须由编辑页自己弹。
    expect(find.byKey(const Key('settings-confirm-dialog')), findsOneWidget);
    expect(rec.calls, isEmpty);
    await tester.tap(find.byKey(const Key('confirm-ok')));
    await tester.pumpAndSettle();
    expect(rec.calls, ['delete:ds']);
    expect(find.byKey(const Key('mp-mobile-editor-scroll')), findsNothing);
    expect(find.byKey(const Key('mp-provider-ds')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机布局：服务商目录模式与勾选面板无溢出', (tester) async {
    await pumpPhone(tester);
    await tester.ensureVisible(find.byKey(const Key('mp-provider-or')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mp-provider-or')));
    await tester.pumpAndSettle();

    final mode = find.byKey(const Key('mp-mode'));
    await tester.ensureVisible(mode);
    await tester.tap(find.byKey(const ValueKey(ProvidersListMode.catalog)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '目录模式首屏');

    final editorScroll = find.byKey(const Key('mp-mobile-editor-scroll'));
    for (var i = 0; i < 8; i++) {
      await tester.drag(editorScroll, const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull, reason: '目录模式滚动到底');
  });

  testWidgets('手机布局：目录勾选后底部出现添加条，点添加会加模型', (tester) async {
    final rec = await pumpPhone(tester);
    await tester.ensureVisible(find.byKey(const Key('mp-provider-or')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mp-provider-or')));
    await tester.pumpAndSettle();

    final mode = find.byKey(const Key('mp-mode'));
    await tester.ensureVisible(mode);
    await tester.tap(find.byKey(const ValueKey(ProvidersListMode.catalog)));
    await tester.pumpAndSettle();

    // 手机端编辑页没有右栏勾选面板，目录模式底部必须常驻提交条。
    final add = find.byKey(const Key('mp-mobile-add-picked'));
    expect(
      find.byKey(const Key('mp-mobile-catalog-dock')),
      findsOneWidget,
      reason: '目录模式底部提交条',
    );
    expect(find.text('已选 0 个'), findsOneWidget);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(rec.calls, isEmpty, reason: '未勾选时添加按钮禁用');
    expect(tester.takeException(), isNull);

    final row = find.byKey(const Key('mp-cat-anthropic/claude-opus-5'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('已选 1 个'), findsOneWidget);
    expect(find.text('添加 1 个模型'), findsOneWidget);

    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(rec.calls, ['add:or:anthropic/claude-opus-5:false']);
    expect(find.byKey(const Key('mp-mobile-catalog-dock')), findsNothing);
    expect(
      find.byKey(const Key('mp-model-anthropic/claude-opus-5')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机布局：没有服务商时显示空态并可添加', (tester) async {
    await pumpProviders(
      tester,
      window: 360 + settingsRail,
      height: 780,
      data: ProvidersFixture.empty,
    );
    expect(find.byKey(const Key('mp-empty')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('mp-empty-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mp-picker-scroll')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机布局：添加服务商是全屏页而不是居中弹窗', (tester) async {
    final rec = await pumpPhone(tester);
    await tester.tap(find.byKey(const Key('mp-mobile-add')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mp-picker-scroll')), findsOneWidget);
    expect(find.byKey(const Key('mp-picker-search')), findsOneWidget);
    expect(tester.takeException(), isNull);
    final pickerScroll = find.byKey(const Key('mp-picker-scroll'));
    await tester.drag(pickerScroll, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(pickerScroll, const Offset(0, 600));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('mp-preset-deepseek')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mp-picker-next')));
    await tester.pumpAndSettle();
    expect(rec.has('create:deepseek'), isTrue);
    // 创建失败（宿主返回 null）后回到服务商列表。
    expect(find.byKey(const Key('mp-mobile')), findsOneWidget);
  });
}
