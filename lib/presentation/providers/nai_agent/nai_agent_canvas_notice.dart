import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/nai_agent/agent_canvas_notice_event.dart';
import 'nai_agent_workspace_controller.dart';
import 'nai_agent_workspace_provider.dart';

export '../../../core/models/nai_agent/agent_canvas_notice_event.dart';

/// 真正会让画布内容变化的工具。读取类工具（查图库、读设置…）刻意不算。
const _canvasTools = {
  'generation_run',
  'image_generate',
  'prompt_update',
  'prompt_set',
};

String _toolNameOf(Object? tool) {
  final name = (tool as Map?)?['toolName'] as String? ?? '';
  return name.startsWith('mcp__nai_studio__')
      ? name.substring('mcp__nai_studio__'.length)
      : name;
}

class NaiAgentCanvasNoticeController extends ChangeNotifier {
  AgentCanvasNoticeEvent? _notice;
  final _executing = <String, String>{};

  /// 最近一条；过期的由界面按 [AgentCanvasNoticeEvent.at] 自己判断。
  AgentCanvasNoticeEvent? get notice => _notice;

  /// 用控制器的最新快照对一次差；同一个工具只报一次。
  void sync(NaiAgentWorkspaceController controller) {
    final live = <String, String>{};
    for (final runtime in controller.heldRuntimes) {
      for (final entry in runtime.executingTools.entries) {
        live[entry.key] = _toolNameOf(entry.value);
      }
    }
    AgentCanvasNoticeEvent? next;
    for (final id in _executing.keys.toList()) {
      if (live.containsKey(id)) continue;
      final name = _executing.remove(id)!;
      if (!_canvasTools.contains(name)) continue;
      // 只有留下结束事件的才是「跑完了」；中途清空（停止、换会话）不算。
      if (!_ended(controller, id)) continue;
      next ??= AgentCanvasNoticeEvent(id: id, at: DateTime.now());
    }
    _executing.addAll(live);
    if (next != null && next.id != _notice?.id) {
      _notice = next;
      notifyListeners();
    }
  }

  static bool _ended(NaiAgentWorkspaceController controller, String id) {
    for (final runtime in controller.heldRuntimes) {
      final tool = runtime.tools[id];
      if (tool == null) continue;
      return tool['type'] == 'tool_execution_end';
    }
    return false;
  }
}

/// 只在画布可见时订阅；面板展开或不在生图页时不做差。
final naiAgentCanvasNoticeProvider =
    ChangeNotifierProvider.autoDispose<NaiAgentCanvasNoticeController>((ref) {
      final controller = NaiAgentCanvasNoticeController();
      ref.listen(
        naiAgentControllerProvider,
        (_, next) => controller.sync(next),
      );
      ref.onDispose(controller.dispose);
      return controller;
    });
