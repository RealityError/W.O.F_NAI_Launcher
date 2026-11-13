import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/localization_extension.dart';
import '../../../core/utils/app_logger.dart';
import '../../providers/nai_agent/nai_agent_canvas_notice.dart';
import '../../providers/nai_agent/nai_agent_window_controller.dart';
import '../../providers/nai_agent/nai_agent_workspace_provider.dart';
import '../../ui/agent/agent_canvas_notice.dart';
import '../../widgets/common/app_toast.dart';

/// 画布浮条：Agent 收起（面板没挡住画布）时，Agent 动过画布就提示一下。
class AgentCanvasNoticeWiring extends ConsumerWidget {
  const AgentCanvasNoticeWiring({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 别为了画一条提示去初始化 Agent 宿主。
    if (!ref.exists(naiAgentControllerProvider)) return const SizedBox.shrink();
    final controller = ref.watch(naiAgentControllerProvider);
    final expanded = ref.exists(naiAgentWindowControllerProvider)
        ? ref.watch(naiAgentWindowControllerProvider).presentationExpanded ??
              controller.settings.panelExpanded
        : controller.settings.panelExpanded;
    if (expanded) return const SizedBox.shrink();
    final event = ref.watch(naiAgentCanvasNoticeProvider).notice;
    if (event == null) return const SizedBox.shrink();
    return AgentCanvasNotice(
      event: event,
      onView: () => unawaited(
        ref.read(naiAgentWindowControllerProvider).toggle().catchError((
          Object error,
        ) {
          AppLogger.w('NAI Agent open failed: $error', 'Agent');
          if (context.mounted) {
            AppToast.error(context, context.l10n.naiAgent_error);
          }
        }),
      ),
    );
  }
}
