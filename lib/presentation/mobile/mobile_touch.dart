import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 手机端最小触摸目标（Material 建议 48dp）。
const double kMobileMinTouchTarget = 48.0;

/// 触感反馈包装：轻触反馈失败时静默忽略（部分设备/测试环境无震动马达）。
Future<void> mobileHapticTap() async {
  try {
    await HapticFeedback.selectionClick();
  } catch (_) {
    // 触感反馈不是功能依赖。
  }
}

/// 手机端可点击卡片：按下时给出可见的按压态，替代桌面 hover 效果。
class MobileTapCard extends StatefulWidget {
  const MobileTapCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.color,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;
  final Color? color;

  @override
  State<MobileTapCard> createState() => _MobileTapCardState();
}

class _MobileTapCardState extends State<MobileTapCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(10);
    return Material(
      color: widget.color ?? Colors.transparent,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: radius,
        onTap: widget.onTap == null
            ? null
            : () {
                mobileHapticTap();
                widget.onTap!();
              },
        onLongPress: widget.onLongPress,
        onHighlightChanged: (value) => setState(() => _pressed = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          decoration: BoxDecoration(
            borderRadius: radius,
            color: _pressed
                ? Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.06)
                : Colors.transparent,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
