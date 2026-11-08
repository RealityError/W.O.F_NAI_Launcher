// 局部重绘 / 蒙版页在手机竖屏（360×780）下的回归测试（G14）。
//
// 编辑器本体复用生成页同一套 `ToolsEditorPage`：手机端走画布优先 +
// 底部工具条 + 参数/图层面板弹层。这里用真实 `ImageEditorScreen`（inpaint
// 模式）验证参数弹层、图层面板、应用分割按钮与触屏画蒙版都能用。
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/mobile/mobile_breakpoints.dart';
import 'package:nai_launcher/presentation/widgets/common/text_editing_shortcuts.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/canvas/editor_canvas.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/image_editor_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugForceMobileLayout = true;
  });
  tearDown(() {
    debugForceMobileLayout = null;
  });

  Future<void> pumpInpaint(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (_, child) => TextEditingShortcuts(child: child!),
        home: ImageEditorScreen(
          initialImage: _buildSolidPng(128, 96, const Color(0xFF224466)),
          mode: ImageEditorMode.inpaint,
        ),
      ),
    );
    await _pumpForAsyncEditorWork(tester);
    await _pumpUntil(tester, () {
      final state = tester.state(find.byType(ImageEditorScreen)) as dynamic;
      return state.debugActiveLayerName == '图层 1' &&
          state.debugCurrentToolId == 'brush' &&
          find.byType(EditorCanvas).evaluate().isNotEmpty;
    });
  }

  testWidgets('手机布局：画布优先，底部工具条 + 应用条，桌面竖栏不内联', (tester) async {
    await pumpInpaint(tester);

    expect(find.byType(EditorCanvas), findsOneWidget);
    expect(
      find.byKey(const Key('tools-editor-mobile-toolbar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('tools-editor-mobile-apply-bar')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('tools-editor-rail')), findsNothing);
    expect(find.byKey(const Key('tools-editor-options')), findsNothing);
    expect(find.byKey(const Key('tools-editor-status')), findsNothing);
    // 局部重绘的主操作是「应用蒙版」+ 下拉（仅应用 / 应用并生成）。
    expect(find.text('应用蒙版'), findsOneWidget);
    expect(find.byKey(const Key('tools-editor-apply-menu')), findsOneWidget);
    // 蒙版工具挂在底部工具条：画笔 / 橡皮 / 填充 / 焦点 / 清除 / 扩展。
    expect(find.byKey(const Key('tools-tool-clear')), findsOneWidget);
    expect(find.byKey(const Key('tools-tool-expand')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('参数弹层：蒙版画笔大小 / 方笔 / 不透明度都在', (tester) async {
    await pumpInpaint(tester);

    await tester.tap(find.byKey(const Key('tools-editor-mobile-options')));
    await _settle(tester);
    expect(
      find.byKey(const Key('tools-editor-mobile-options-sheet')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('tools-opt-size')), findsOneWidget);
    expect(find.byKey(const Key('tools-opt-square')), findsOneWidget);
    // 蒙版显示样式（颜色 / 不透明度 / 图案）也在参数弹层里。
    expect(find.byKey(const Key('tools-mask-look')), findsOneWidget);
    expect(find.byKey(const Key('tools-mask-opacity')), findsOneWidget);

    // 点遮罩收起，弹层不残留。
    await tester.tap(find.byKey(const Key('tools-editor-mobile-scrim')));
    await _settle(tester);
    expect(
      find.byKey(const Key('tools-editor-mobile-options-sheet')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('图层面板：重绘强度 / 输出设置 / 图层都在，关掉恢复画布', (tester) async {
    await pumpInpaint(tester);

    await tester.tap(find.byKey(const Key('tools-editor-mobile-side')));
    await _settle(tester);
    expect(
      find.byKey(const Key('tools-editor-mobile-side-sheet')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('tools-inpaint-settings')), findsOneWidget);
    expect(find.byKey(const Key('tools-inpaint-strength')), findsOneWidget);
    expect(find.byKey(const Key('tools-inpaint-output')), findsOneWidget);
    expect(find.byKey(const Key('tools-layers')), findsOneWidget);

    await tester.tap(find.byKey(const Key('tools-editor-mobile-side-close')));
    await _settle(tester);
    expect(
      find.byKey(const Key('tools-editor-mobile-side-sheet')),
      findsNothing,
    );
    expect(find.byType(EditorCanvas), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机上能用手指在画布上涂蒙版', (tester) async {
    await pumpInpaint(tester);
    final state = tester.state(find.byType(ImageEditorScreen)) as dynamic;
    final canvasTopLeft = tester.getTopLeft(find.byType(EditorCanvas));
    final start =
        canvasTopLeft +
        (state.debugCanvasToScreen(const Offset(32, 32)) as Offset);
    final end =
        canvasTopLeft +
        (state.debugCanvasToScreen(const Offset(86, 62)) as Offset);

    final gesture = await tester.startGesture(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(state.debugActiveLayerStrokeCount, greaterThan(0));
    expect(state.debugHasMaskContent, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('应用下拉在手机上是底部弹层，能选仅应用 / 应用并生成', (tester) async {
    await pumpInpaint(tester);

    await tester.tap(find.byKey(const Key('tools-editor-apply-menu')));
    await _settle(tester);
    expect(find.byKey(const Key('tools-apply-only')), findsOneWidget);
    expect(find.byKey(const Key('tools-apply-generate')), findsOneWidget);

    await tester.tap(find.byKey(const Key('tools-apply-only')));
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpForAsyncEditorWork(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 10; i++) {
    if (condition()) {
      return;
    }
    await _pumpForAsyncEditorWork(tester);
  }
  expect(condition(), isTrue);
}

Uint8List _buildSolidPng(int width, int height, Color color) {
  final image = img.Image(width: width, height: height);
  img.fill(
    image,
    color: img.ColorRgba8(
      (color.r * 255).round().clamp(0, 255),
      (color.g * 255).round().clamp(0, 255),
      (color.b * 255).round().clamp(0, 255),
      (color.a * 255).round().clamp(0, 255),
    ),
  );
  return Uint8List.fromList(img.encodePng(image));
}

/// 编辑器画布会持续请求重绘，`pumpAndSettle` 会等不到静止；弹层本身没有动画，
/// 手动泵两帧就够。
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}
