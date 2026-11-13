import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nai_launcher/presentation/providers/nai_agent/nai_agent_canvas_notice.dart';
import 'package:nai_launcher/presentation/providers/nai_agent/nai_agent_workspace_controller.dart';

class _Controller extends Mock implements NaiAgentWorkspaceController {}

class _Runtime extends Mock implements AgentChatRuntime {}

Map<String, dynamic> _tool(String name) => {'toolName': name};

void main() {
  late _Controller controller;
  late _Runtime runtime;
  late NaiAgentCanvasNoticeController notice;

  /// 让控制器报告 [executing] 正在跑、[tools] 里有历史工具。
  void stub(
    Map<String, Map<String, dynamic>> executing, {
    Map<String, Map<String, dynamic>> ended = const {},
  }) {
    when(() => controller.heldRuntimes).thenReturn([runtime]);
    when(() => runtime.executingTools).thenReturn(executing);
    when(() => runtime.tools).thenReturn({
      for (final id in ended.keys) id: {'type': 'tool_execution_end'},
    });
  }

  setUp(() {
    controller = _Controller();
    runtime = _Runtime();
    notice = NaiAgentCanvasNoticeController();
    // 第一次同步只是记下已经在跑的工具，不报旧事。
    stub({'call': _tool('generation_run')});
    notice.sync(controller);
    expect(notice.notice, isNull);
  });

  /// 工具从执行中消失（结束事件已到）：画布被改过。
  test('生成类工具跑完 → 提示一次', () {
    stub({}, ended: {'call': {}});
    notice.sync(controller);
    expect(notice.notice?.id, 'call');
  });

  test('读类工具跑完不提示', () {
    stub({'read': _tool('gallery_query')});
    notice.sync(controller);
    stub({}, ended: {'read': {}});
    notice.sync(controller);
    expect(notice.notice, isNull);
  });

  test('没留下结束事件（停止/换会话清空）不算画布更新', () {
    stub({});
    notice.sync(controller);
    expect(notice.notice, isNull);
  });

  test('mcp 前缀的工具名照样认', () {
    stub({'call': _tool('mcp__nai_studio__prompt_update')});
    notice.sync(controller);
    stub({}, ended: {'call': {}});
    notice.sync(controller);
    expect(notice.notice?.id, 'call');
  });

  test('同一个工具重复同步只提示一次', () {
    stub({}, ended: {'call': {}});
    notice.sync(controller);
    var notified = 0;
    notice.addListener(() => notified++);
    notice.sync(controller);
    notice.sync(controller);
    expect(notified, 0);
    expect(notice.notice?.id, 'call');
  });
}
