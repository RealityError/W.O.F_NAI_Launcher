import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/nai_agent/nai_agent_canvas_notice.dart';
import 'package:nai_launcher/presentation/themes/presets/geist_theme.dart';
import 'package:nai_launcher/presentation/ui/agent/agent_canvas_notice.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: GeistTheme.light,
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(body: Center(child: child)),
  ),
);

AgentCanvasNoticeEvent _event({Duration age = Duration.zero}) =>
    AgentCanvasNoticeEvent(id: 'call-1', at: DateTime.now().subtract(age));

void main() {
  testWidgets('新提示会浮出来，点「查看」回调', (tester) async {
    var viewed = 0;
    await _pump(
      tester,
      AgentCanvasNotice(event: _event(), onView: () => viewed++),
    );
    await tester.pump();
    expect(find.byKey(const Key('agent-canvas-notice')), findsOneWidget);
    expect(find.text('画布已更新'), findsOneWidget);

    await tester.tap(find.byKey(const Key('agent-canvas-notice-view')));
    expect(viewed, 1);
  });

  testWidgets('超过 5 秒的提示淡出且不吃点击', (tester) async {
    var viewed = 0;
    await _pump(
      tester,
      AgentCanvasNotice(
        event: _event(age: const Duration(seconds: 6)),
        onView: () => viewed++,
      ),
    );
    await tester.pump();
    final opacity = tester.widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.byKey(const Key('agent-canvas-notice')),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    );
    expect(opacity.opacity, 0);
    final ignoring = tester.widget<IgnorePointer>(
      find
          .ancestor(
            of: find.byKey(const Key('agent-canvas-notice')),
            matching: find.byType(IgnorePointer),
          )
          .first,
    );
    expect(ignoring.ignoring, isTrue);
    await tester.tap(
      find.byKey(const Key('agent-canvas-notice-view')),
      warnIfMissed: false,
    );
    expect(viewed, 0);
  });

  testWidgets('窗口太窄只留「查看」', (tester) async {
    await _pump(
      tester,
      SizedBox(
        width: 120,
        child: AgentCanvasNotice(event: _event(), onView: () {}),
      ),
    );
    await tester.pump();
    expect(find.text('画布已更新'), findsNothing);
    expect(find.byKey(const Key('agent-canvas-notice-view')), findsOneWidget);
  });
}
