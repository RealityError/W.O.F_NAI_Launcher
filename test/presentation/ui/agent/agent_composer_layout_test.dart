import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/ui/agent/agent_contract.dart';
import 'package:nai_launcher/presentation/ui/agent/agent_fixture.dart';

import '../../../helpers/studio_capture_fonts.dart';
import 'agent_test_harness.dart';

/// 底栏在手机竖屏（360–412dp，扣掉内边距只剩 320–375dp）必须整行放得下。
/// 曾经「⚠ 完全权限」+「排队发送」+ 停止占满整行，模型药丸只剩二十几 dp，
/// 箭头顶到 Row 外面，红色 RIGHT OVERFLOWED 直接压在输入文字上。
void main() {
  setUpAll(loadStudioCaptureFonts);

  AgentViewData view({
    required AgentPermissionMode permission,
    required AgentRunStatus status,
    required String text,
    String? modelLabel,
  }) {
    final base = AgentFixture.view(AgentScene.chat);
    final models = [
      for (final m in base.models)
        AgentModelOption(
          providerId: m.providerId,
          modelId: m.modelId,
          provider: m.provider,
          label: m.selected ? modelLabel ?? m.label : m.label,
          selected: m.selected,
          logoAsset: m.logoAsset,
          mark: m.mark,
          chatGptUsageUrl: m.chatGptUsageUrl,
        ),
    ];
    return AgentViewData(
      now: base.now,
      workspace: base.workspace,
      chat: base.chat,
      workspaces: base.workspaces,
      chats: base.chats,
      composer: AgentComposerData(
        text: text,
        canSend: true,
        canAttachCanvas: true,
        enterSends: false,
        queue: status == AgentRunStatus.idle
            ? const []
            : const [
                AgentQueued(
                  id: 'q1',
                  text: '然后把最好的一张做成积木',
                  kind: AgentQueueKind.queued,
                ),
              ],
      ),
      thread: base.thread,
      shelf: base.shelf,
      memory: base.memory,
      usage: base.usage,
      models: models,
      thinking: base.thinking,
      permission: permission,
      mentions: base.mentions,
      skills: base.skills,
      slashCommands: base.slashCommands,
      status: status,
      revision: base.revision,
      history: base.history,
    );
  }

  /// 真机竖屏：360dp 最常见，393/412dp 是主流大屏手机。
  const phoneWidths = [320.0, 360.0, 393.0, 412.0];
  const runningStates = [
    AgentRunStatus.idle,
    AgentRunStatus.working,
    AgentRunStatus.waitingUser,
    AgentRunStatus.compacting,
  ];

  for (final width in phoneWidths) {
    for (final status in runningStates) {
      testWidgets('窄屏底栏不溢出 ${width.toInt()}dp $status', (t) async {
        await pumpAgent(
          t,
          width: width,
          data: view(
            permission: AgentPermissionMode.bypass,
            status: status,
            text: '你觉得我们现在的tag还缺少什么吗？',
          ),
        );
        expect(t.takeException(), isNull);
      });
    }
  }

  // 各语言按钮/药丸文案长短不同（Full access、フルアクセス…），用真实字体一起压。
  for (final locale in ['en', 'ja', 'ko']) {
    testWidgets('窄屏底栏不溢出 360dp $locale', (t) async {
      await pumpAgent(
        t,
        width: 360,
        locale: locale,
        data: view(
          permission: AgentPermissionMode.bypass,
          status: AgentRunStatus.working,
          text: 'What tags are we still missing?',
        ),
      );
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('窄屏把宽度让给模型名：360dp 下完整显示当前模型', (t) async {
    await pumpAgent(
      t,
      width: 360,
      data: view(
        permission: AgentPermissionMode.bypass,
        status: AgentRunStatus.working,
        text: '你觉得我们现在的tag还缺少什么吗？',
      ),
    );
    expect(t.takeException(), isNull);
    expect(find.text('Sonnet 4.5'), findsOneWidget);
    final pill = t.getRect(find.byKey(const Key('agent-model')));
    // 名称完整 + 箭头都画出来才需要这么宽；被挤到只剩箭头时只有 26。
    expect(pill.width, greaterThan(70));
    // 主按钮收成图标，仍在底栏内。
    final send = t.getRect(find.byKey(const Key('agent-send')));
    expect(send.right, lessThanOrEqualTo(360 - 6));
    expect(send.width, 30);
  });

  testWidgets('窄屏超长模型名只省略文字，不溢出', (t) async {
    await pumpAgent(
      t,
      width: 360,
      data: view(
        permission: AgentPermissionMode.bypass,
        status: AgentRunStatus.working,
        text: '长模型名的兜底',
        modelLabel: 'claude-sonnet-4-5-20250929',
      ),
    );
    expect(t.takeException(), isNull);
    expect(find.text('claude-sonnet-4-5-20250929'), findsOneWidget);
  });

  testWidgets('窄屏点箭头就是发送（运行中是排队发送）', (t) async {
    final rec = await pumpAgent(
      t,
      width: 360,
      data: view(
        permission: AgentPermissionMode.auto,
        status: AgentRunStatus.working,
        text: '排队一句',
      ),
    );
    expect(t.takeException(), isNull);
    await t.tap(find.byKey(const Key('agent-send')));
    await t.pump();
    // 运行中点箭头 = 排队发送（不是引导插入）。
    expect(rec.last('send'), isFalse);
  });

  testWidgets('桌面宽度保持原样：发送按钮带文字、模型档位可见', (t) async {
    await pumpAgent(
      t,
      width: 520,
      data: view(
        permission: AgentPermissionMode.auto,
        status: AgentRunStatus.idle,
        text: 'hi',
      ),
    );
    expect(t.takeException(), isNull);
    expect(find.text('发送'), findsOneWidget);
    expect(find.text('Medium'), findsOneWidget);
    expect(
      t.getRect(find.byKey(const Key('agent-send'))).width,
      greaterThan(60),
    );
  });
}
