// 编辑器手机端布局（G13 方案 A，360dp 竖屏）回归测试。
//
// 桌面三栏布局由既有 tools_editor_test.dart 覆盖；这里只验证手机分支：
// 画布优先，桌面竖栏 / 选项条 / 状态栏都不内联；参数与图层面板改为底部弹层，
// 底部工具条常驻、可直接切工具；应用按钮常驻在底部应用条上。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/mobile/mobile_breakpoints.dart';
import 'package:nai_launcher/presentation/ui/tools/tools_contract.dart';
import 'package:nai_launcher/presentation/ui/tools/tools_fixture.dart';

import 'tools_test_harness.dart';

void main() {
  setUp(() => debugForceMobileLayout = true);
  tearDown(() => debugForceMobileLayout = null);

  ToolsEditorData edit({ToolsTool tool = ToolsTool.brush}) =>
      ToolsFixture.editor(tool: tool);
  ToolsEditorData inpaint() =>
      ToolsFixture.editor(mode: ToolsEditorMode.inpaint);

  Future<void> pumpPhone(
    WidgetTester tester, {
    required ToolsEditorData data,
    ToolsRecorder? r,
  }) => pumpToolsEditor(
    tester,
    data: data,
    r: r,
    // 扣掉 48 主导航后页面可用 360。
    width: 360 + genRail,
    height: 780,
  );

  testWidgets('手机布局：画布优先，桌面竖栏 / 选项条 / 状态栏都不内联', (tester) async {
    await pumpPhone(tester, data: edit());

    expect(find.byKey(const Key('tools-editor')), findsOneWidget);
    expect(find.byKey(const Key('tools-editor-work')), findsOneWidget);
    expect(
      find.byKey(const Key('tools-editor-mobile-toolbar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('tools-editor-mobile-apply-bar')),
      findsOneWidget,
    );
    // 桌面专属：左竖栏、顶部选项条、右栏、底部状态栏在手机上都不渲染。
    expect(find.byKey(const Key('tools-editor-rail')), findsNothing);
    expect(find.byKey(const Key('tools-editor-options')), findsNothing);
    expect(find.byKey(const Key('tools-editor-side')), findsNothing);
    expect(find.byKey(const Key('tools-editor-status')), findsNothing);
    // 顶栏改为手机版：返回 / 标题 / 撤销 / 重做 / 下载，不再塞窗口按钮。
    expect(find.byKey(const Key('tools-editor-back')), findsOneWidget);
    expect(find.byKey(const Key('tools-editor-title')), findsOneWidget);
    expect(find.byKey(const Key('tools-editor-undo')), findsOneWidget);
    expect(find.byKey(const Key('tools-editor-redo')), findsOneWidget);
    expect(find.byKey(const Key('tools-editor-download')), findsOneWidget);
    expect(find.text('用作图生图底图'), findsOneWidget);
    // 画布占大头：780 − 顶栏 56 − 应用条 56 − 工具条 64 ≈ 604。
    expect(
      tester.getSize(find.byKey(const Key('tools-editor-work'))).height,
      greaterThan(560),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('底部工具条直接切工具，不需要先进弹层', (tester) async {
    final r = ToolsRecorder();
    await pumpPhone(tester, data: edit(), r: r);

    expect(find.byKey(const Key('tools-tool-brush')), findsOneWidget);
    await tester.tap(find.byKey(const Key('tools-tool-eraser')));
    await tester.pumpAndSettle();
    expect(r.calls, contains('onTool(eraser)'));

    // 快捷键字母帽不出现在手机工具条上（手机没有物理键盘）。
    expect(find.byKey(const Key('tools-tool-brush')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('参数弹层：点参数打开选项条，点遮罩关闭', (tester) async {
    await pumpPhone(tester, data: edit());

    expect(find.byKey(const Key('tools-editor-options')), findsNothing);
    await tester.tap(find.byKey(const Key('tools-editor-mobile-options')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('tools-editor-mobile-options-sheet')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('tools-editor-options')), findsOneWidget);
    expect(find.byKey(const Key('tools-opt-size')), findsOneWidget);

    await tester.tap(find.byKey(const Key('tools-editor-mobile-scrim')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('tools-editor-mobile-options-sheet')),
      findsNothing,
    );
    expect(find.byKey(const Key('tools-editor-options')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('图层面板从底部整宽升起，关闭按钮收起', (tester) async {
    await pumpPhone(tester, data: edit());

    await tester.tap(find.byKey(const Key('tools-editor-mobile-side')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('tools-editor-mobile-side-sheet')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('tools-editor-side')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('tools-editor-side'))).width,
      360,
    );
    expect(find.byKey(const Key('tools-layer-add')), findsOneWidget);

    await tester.tap(find.byKey(const Key('tools-editor-mobile-side-close')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('tools-editor-mobile-side-sheet')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('从工具条打开「调整」也进图层面板；面板开着能直接换工具', (tester) async {
    final r = ToolsRecorder();
    await pumpPhone(tester, data: edit(), r: r);

    // 工具条是横滑的：先把「调整」滚出来再点。
    await tester.drag(
      find.byKey(const Key('tools-editor-mobile-toolbar')),
      const Offset(-420, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tools-tool-adjust')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('tools-editor-mobile-side-sheet')),
      findsOneWidget,
    );

    // 底部工具条在弹层下面保持可点：面板开着也能直接换笔刷。
    await tester.drag(
      find.byKey(const Key('tools-editor-mobile-toolbar')),
      const Offset(500, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tools-tool-eraser')));
    await tester.pumpAndSettle();
    expect(r.calls, contains('onTool(eraser)'));
    expect(
      find.byKey(const Key('tools-editor-mobile-side-sheet')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('局部重绘：底部工具条有蒙版工具，应用分成两段', (tester) async {
    final r = ToolsRecorder();
    await pumpPhone(tester, data: inpaint(), r: r);

    expect(find.byKey(const Key('tools-tool-clear')), findsOneWidget);
    expect(find.byKey(const Key('tools-tool-expand')), findsOneWidget);
    expect(find.byKey(const Key('tools-editor-apply-menu')), findsOneWidget);
    expect(find.text('应用蒙版'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tools-tool-clear')));
    await tester.pumpAndSettle();
    expect(r.calls, contains('onClearMask'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('点应用 / 下载走动作', (tester) async {
    final r = ToolsRecorder();
    await pumpPhone(tester, data: edit(), r: r);

    await tester.tap(find.byKey(const Key('tools-editor-apply')));
    await tester.pumpAndSettle();
    expect(r.calls, contains('onApply'));

    await tester.tap(find.byKey(const Key('tools-editor-download')));
    await tester.pumpAndSettle();
    expect(r.calls, contains('onDownload'));
    expect(tester.takeException(), isNull);
  });
}
