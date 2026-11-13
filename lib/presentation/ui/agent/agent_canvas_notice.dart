import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/utils/localization_extension.dart';
import '../../providers/nai_agent/nai_agent_canvas_notice.dart';
import '../../widgets/common/studio_glass_surface.dart';
import '../kit/ui_colors.dart';
import '../kit/ui_text.dart';

/// 画布上浮起的一条「Agent 动过画布」提示，5 秒后自己淡出。
/// 常驻的 Agent 角标是另一条线（[AgentToggleBadge]），互不影响。
class AgentCanvasNotice extends StatefulWidget {
  const AgentCanvasNotice({
    super.key,
    required this.event,
    required this.onView,
  });

  final AgentCanvasNoticeEvent event;
  final VoidCallback onView;
  static const duration = Duration(seconds: 5);

  @override
  State<AgentCanvasNotice> createState() => _AgentCanvasNoticeState();
}

class _AgentCanvasNoticeState extends State<AgentCanvasNotice> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(AgentCanvasNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event.id != widget.event.id) _start();
  }

  void _start() {
    _timer?.cancel();
    final remaining = widget.event.at
        .add(AgentCanvasNotice.duration)
        .difference(DateTime.now());
    _visible = remaining > Duration.zero;
    if (_visible) {
      _timer = Timer(remaining, () {
        if (mounted) setState(() => _visible = false);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ui, l = context.l10n;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return IgnorePointer(
      ignoring: !_visible,
      child: ExcludeSemantics(
        excluding: !_visible,
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: reduced ? Duration.zero : const Duration(milliseconds: 160),
          child: Semantics(
            liveRegion: true,
            container: true,
            child: StudioGlassSurface(
              key: const Key('agent-canvas-notice'),
              borderRadius: BorderRadius.circular(11),
              backdropBlur: true,
              useGradient: false,
              child: SizedBox(
                height: 38,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: LayoutBuilder(
                    builder: (context, box) => Row(
                      children: [
                        if (box.maxWidth >= 130) ...[
                          Icon(Icons.north_east, size: 14, color: c.accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Tooltip(
                              message: l.ag_canvasUpdated,
                              child: Text(
                                l.ag_canvasUpdated,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: UiText.sans(12, color: c.ink),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ] else
                          const Spacer(),
                        TextButton(
                          key: const Key('agent-canvas-notice-view'),
                          onPressed: widget.onView,
                          style: TextButton.styleFrom(
                            foregroundColor: c.accent,
                            minimumSize: const Size(40, 30),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: UiText.sans(12, weight: FontWeight.w500),
                          ),
                          child: Text(l.ag_canvasView),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
