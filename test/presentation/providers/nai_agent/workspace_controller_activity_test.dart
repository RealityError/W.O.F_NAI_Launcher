import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nai_launcher/core/nai_agent/pi_host_client.dart';
import 'package:nai_launcher/core/nai_agent/vision_access.dart';
import 'package:nai_launcher/data/services/nai_agent/agent_workspace_store.dart';
import 'package:nai_launcher/presentation/providers/nai_agent/nai_agent_workspace_controller.dart';
import 'package:nai_launcher/presentation/ui/agent/agent_glyphs.dart';
import 'package:nai_launcher/presentation/wiring/nai_agent/agent_toggle_badge.dart';

class _Client extends Mock implements PiHostClient {}

/// 宿主信封经控制器落到「阶段 + 正在跑的工具」，再变成入口角标。
/// 这条链路是手机端唯一能看到「Agent 现在在干嘛」的实时信号（面板全屏时看标题
/// 左侧的小人/圆点，收起时看工具栏角标）。
void main() {
  late Directory root;
  late StreamController<Map<String, dynamic>> events;
  late _Client client;
  late NaiAgentWorkspaceController c;
  late Completer<Map<String, dynamic>> held;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('agent-activity-');
    events = StreamController<Map<String, dynamic>>.broadcast(sync: true);
    held = Completer<Map<String, dynamic>>();
    client = _Client();
    when(() => client.isClosed).thenReturn(false);
    when(client.cancelSuggestion).thenAnswer((_) async => {});
    when(() => client.visionAccess).thenReturn(const NaiAgentVisionAccess());
    when(() => client.initialState).thenAnswer((_) => {'messages': <Object>[]});
    when(() => client.events).thenAnswer((_) => events.stream);
    when(() => client.close()).thenAnswer((_) async {});
    when(
      () => client.prompt(
        any(),
        images: any(named: 'images'),
        steer: any(named: 'steer'),
        queueId: any(named: 'queueId'),
      ),
    ).thenAnswer((_) => held.future);
    final store = AgentWorkspaceStore(root);
    final workspace = await store.createWorkspace('Fixture');
    await store.createChat(workspace.id, 'Saved');
    c = NaiAgentWorkspaceController(
      store: store,
      startClient: (_, __, ___, ____, _____) async => client,
      initialWorkspaceName: 'Workspace',
      initialChatName: 'New chat',
    );
    await c.initialize(restoreHistory: false);
  });

  tearDown(() async {
    if (!held.isCompleted) held.complete({'messages': <Object>[]});
    await c.close();
    c.dispose();
    await events.close();
    await root.delete(recursive: true);
  });

  /// 开始一次会一直挂着的运行，等它真正进入 running。
  Future<(Future<void>, AgentChatRuntime)> startRun(String text) async {
    final pending = c.sendText(text);
    final runtime = c.selected!;
    for (var i = 0; i < 300 && !runtime.running; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(runtime.running, isTrue, reason: '运行没开始，后面的活动事件都会被丢掉');
    return (pending, runtime);
  }

  Map<String, dynamic> assistant() => {
    'role': 'assistant',
    'timestamp': 1,
    'content': <Object>[],
  };
  void delta(String type) => events.add({
    'type': 'event',
    'event': {
      'type': 'message_update',
      'message': assistant(),
      'assistantMessageEvent': {'type': type},
    },
  });
  void toolStart(String id, String name) => events.add({
    'type': 'event',
    'event': {
      'type': 'tool_execution_start',
      'toolCallId': id,
      'toolName': name,
      'args': {'query': 'watercolor'},
    },
  });
  void toolEnd(String id) => events.add({
    'type': 'event',
    'event': {'type': 'tool_execution_end', 'toolCallId': id},
  });

  test('阶段跟着回答增量走，工具起止维护正在执行的工具，角标同步', () async {
    final (pending, runtime) = await startRun('go');
    expect(runtime.streamPhase, AgentStreamPhase.thinking);
    expect(agentRuntimeBadge(runtime), AgentToggleBadge.thinking);

    delta('text_delta');
    expect(runtime.streamPhase, AgentStreamPhase.writing);
    expect(agentRuntimeBadge(runtime), AgentToggleBadge.writing);

    delta('thinking_delta');
    expect(runtime.streamPhase, AgentStreamPhase.thinking);

    toolStart('call-1', 'gallery_query');
    expect(runtime.executingTools.keys, ['call-1']);
    expect(agentRuntimeBadge(runtime), AgentToggleBadge.tool);

    // 工具返回后回到思考；已完成的历史工具仍在 tools 里，不受活动流影响。
    toolEnd('call-1');
    expect(runtime.executingTools, isEmpty);
    expect(runtime.streamPhase, AgentStreamPhase.thinking);
    expect(runtime.tools['call-1']!['type'], 'tool_execution_end');

    // 新一轮请求（自动重试/排队消息）把阶段拉回思考。
    delta('text_delta');
    events.add({'type': 'request_started'});
    expect(runtime.streamPhase, AgentStreamPhase.thinking);

    held.complete({'messages': <Object>[]});
    await pending;
  });

  test('生成图片类工具报「生成中」，其余工具报「执行中」', () async {
    final (pending, runtime) = await startRun('draw');
    toolStart('gen', 'generation_run');
    expect(agentRuntimeBadge(runtime), AgentToggleBadge.generating);

    toolStart('read', 'gallery_query');
    expect(agentRuntimeBadge(runtime), AgentToggleBadge.generating);

    toolEnd('gen');
    expect(agentRuntimeBadge(runtime), AgentToggleBadge.tool);

    toolEnd('read');
    expect(agentRuntimeBadge(runtime), AgentToggleBadge.thinking);

    held.complete({'messages': <Object>[]});
    await pending;
  });

  test('停止后角标不再报运行中', () async {
    final (pending, runtime) = await startRun('go');
    delta('text_delta');
    expect(agentRuntimeBadge(runtime), AgentToggleBadge.writing);

    runtime.running = false;
    expect(agentRuntimeBadge(runtime), AgentToggleBadge.none);

    held.complete({'messages': <Object>[]});
    await pending;
  });
}
