// 测试里的 widget 树含非 const 的 TextField，整棵树无法 const 化。
// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/widgets/common/continuous_text_selection.dart';

Widget _host({required Widget child}) => MaterialApp(
  home: DefaultSelectionStyle(
    selectionColor: const Color(0x553B82F6),
    child: Scaffold(
      body: Center(child: SizedBox(width: 280, child: child)),
    ),
  ),
);

void main() {
  testWidgets(
    'multiline field still edits and selects without painting errors',
    (tester) async {
      final controller = TextEditingController(
        text: 'line one\nline two\nline three',
      );
      addTearDown(controller.dispose);
      final focus = FocusNode();
      addTearDown(focus.dispose);

      await tester.pumpWidget(
        _host(
          child: ContinuousTextSelection(
            child: TextField(
              key: const Key('cts-input'),
              controller: controller,
              focusNode: focus,
              minLines: 1,
              maxLines: 6,
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('cts-input')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('cts-input')));
      await tester.pumpAndSettle();
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 17,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.enterText(find.byKey(const Key('cts-input')), 'replaced');
      await tester.pump();
      expect(controller.text, 'replaced');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('passes through when no selection color is available', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: ContinuousTextSelection(
                child: TextField(
                  key: const Key('cts-plain'),
                  minLines: 2,
                  maxLines: 4,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('cts-plain')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
