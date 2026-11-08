import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/mobile/mobile_breakpoints.dart';
import 'package:nai_launcher/presentation/ui/kit/ui_popover.dart';

class _PopoverHost extends StatefulWidget {
  const _PopoverHost();

  @override
  State<_PopoverHost> createState() => _PopoverHostState();
}

class _PopoverHostState extends State<_PopoverHost> {
  UiPopoverAnchor? anchor;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: UiPopover(
            anchor: anchor,
            onDismiss: () => setState(() => anchor = null),
            builder: (_) => const UiPopoverSurface(
              width: 220,
              child: SizedBox(
                key: Key('popover-body'),
                height: 100,
                child: Text('menu'),
              ),
            ),
            child: TextButton(
              key: const Key('open-popover'),
              onPressed: () => setState(
                () => anchor = const UiPopoverAnchor(Offset(10, 100)),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => debugForceMobileLayout = true);
  tearDown(() => debugForceMobileLayout = null);

  testWidgets('手机端弹层从底部升起并撑满可用宽度', (tester) async {
    await tester.pumpWidget(const _PopoverHost());
    await tester.tap(find.byKey(const Key('open-popover')));
    await tester.pumpAndSettle();

    final body = find.byKey(const Key('popover-body'));
    expect(body, findsOneWidget);
    final rect = tester.getRect(body);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(rect.left, 9, reason: '外框 8 + 1 描边');
    expect(rect.right, screen.width - 9);
    expect(rect.bottom, screen.height - 9);
  });

  testWidgets('点遮罩收起手机端弹层', (tester) async {
    await tester.pumpWidget(const _PopoverHost());
    await tester.tap(find.byKey(const Key('open-popover')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('popover-body')), findsOneWidget);

    await tester.tapAt(const Offset(400, 60));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('popover-body')), findsNothing);
  });
}
