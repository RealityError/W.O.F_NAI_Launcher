import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/themes/presets/geist_theme.dart';
import 'package:nai_launcher/presentation/ui/agent/agent_mark.dart';
import 'package:nai_launcher/presentation/ui/kit/ui_colors.dart';

/// 静态 Anlas 小人 + 状态角标：不跑动画，只要求「每个状态都画得出来」且角标颜色
/// 跟状态对得上。
void main() {
  Future<BuildContext> pump(WidgetTester t, Widget child) async {
    late BuildContext context;
    await t.pumpWidget(
      MaterialApp(
        theme: GeistTheme.light,
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (c) {
                context = c;
                return child;
              },
            ),
          ),
        ),
      ),
    );
    return context;
  }

  testWidgets('每个状态、每种尺寸都能画出来（浅色/深色）', (t) async {
    for (final theme in [GeistTheme.light, GeistTheme.dark]) {
      for (final badge in AgentToggleBadge.values) {
        for (final size in [14.0, 17.0, 26.0]) {
          await t.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: Center(
                  child: AgentMark(badge: badge, size: size),
                ),
              ),
            ),
          );
          expect(t.takeException(), isNull, reason: '${badge.name} @ $size');
        }
      }
    }
  });

  test('像素帧数据跟桌面版一致', () {
    for (final frame in agentMarkFrames.values) {
      expect(frame, hasLength(9));
      for (final row in frame) {
        expect(row.length, anyOf(9, 11));
      }
    }
    expect(agentMarkFrames['base']!.first, '....#....');
    expect(agentMarkFrames['base']![6], '##oo#oo#=');
  });

  testWidgets('角标圆点：收起时按状态上色，展开和空闲都不画', (t) async {
    final context = await pump(t, const SizedBox.shrink());
    final c = context.ui;
    for (final badge in AgentToggleBadge.values) {
      await pump(
        t,
        AgentToggleButton(
          expanded: false,
          badge: badge,
          tooltip: 'Agent',
          onPressed: () {},
        ),
      );
      final dot = find.byKey(Key('agent-toggle-badge-${badge.name}'));
      if (badge == AgentToggleBadge.none) {
        expect(dot, findsNothing);
        continue;
      }
      expect(dot, findsOneWidget, reason: badge.name);
      final box = t.widget<Container>(dot);
      expect(
        (box.decoration! as BoxDecoration).color,
        agentBadgeColor(c, badge),
        reason: badge.name,
      );
    }

    await pump(
      t,
      AgentToggleButton(
        expanded: true,
        badge: AgentToggleBadge.thinking,
        tooltip: 'Agent',
        onPressed: () {},
      ),
    );
    expect(find.byKey(const Key('agent-toggle-badge-thinking')), findsNothing);
    expect(find.byKey(const Key('agent-toggle')), findsOneWidget);
  });

  testWidgets('标题状态标志：在跑时带圆点，空闲不带', (t) async {
    final context = await pump(t, const SizedBox.shrink());
    final c = context.ui;
    await pump(t, const AgentStatusMark());
    expect(find.byKey(const Key('agent-toggle-badge-none')), findsNothing);

    await pump(t, const AgentStatusMark(badge: AgentToggleBadge.generating));
    final dot = find.byKey(const Key('agent-toggle-badge-generating'));
    expect(dot, findsOneWidget);
    expect(
      (t.widget<Container>(dot).decoration! as BoxDecoration).color,
      c.accent,
    );

    await pump(t, const AgentStatusMark(badge: AgentToggleBadge.approval));
    expect(
      (t
                  .widget<Container>(
                    find.byKey(const Key('agent-toggle-badge-approval')),
                  )
                  .decoration!
              as BoxDecoration)
          .color,
      c.warn,
    );

    await pump(t, const AgentStatusMark(badge: AgentToggleBadge.error));
    expect(
      (t
                  .widget<Container>(
                    find.byKey(const Key('agent-toggle-badge-error')),
                  )
                  .decoration!
              as BoxDecoration)
          .color,
      c.error,
    );
  });
}
