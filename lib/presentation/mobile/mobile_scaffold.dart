import 'package:flutter/material.dart';

/// 手机端统一页面骨架：状态栏安全区 + 56dp 标题栏 + 返回 + 右侧操作 + 可选底栏。
///
/// 只用于移动端布局分支；桌面端继续使用原有页面结构。
class MobilePageScaffold extends StatelessWidget {
  const MobilePageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.bottomBar,
    this.onBack,
    this.showBack = true,
    this.backgroundColor,
    this.bodyPadding,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;

  /// 底部固定操作区；自动处理导航栏与键盘 inset。
  final Widget? bottomBar;

  /// 默认 `Navigator.maybePop`。
  final VoidCallback? onBack;
  final bool showBack;
  final Color? backgroundColor;
  final EdgeInsetsGeometry? bodyPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final media = MediaQuery.of(context);
    final topInset = media.padding.top;
    final bottomInset = media.viewInsets.bottom > 0
        ? media.viewInsets.bottom
        : media.padding.bottom;
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: backgroundColor ?? scheme.surface,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: EdgeInsets.only(top: topInset),
              decoration: BoxDecoration(
                color: backgroundColor ?? scheme.surface,
                border: Border(
                  bottom: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
              ),
              child: SizedBox(
                height: 56,
                child: Row(
                  children: [
                    if (showBack)
                      _HeaderIconButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).backButtonTooltip,
                        onTap: onBack ?? () => Navigator.maybePop(context),
                      )
                    else
                      const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    ...actions,
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
            Expanded(
              child: bodyPadding == null
                  ? child
                  : Padding(padding: bodyPadding!, child: child),
            ),
            if (bottomBar != null)
              Container(
                padding: EdgeInsets.only(
                  left: media.padding.left,
                  right: media.padding.right,
                  bottom: bottomInset,
                ),
                decoration: BoxDecoration(
                  color: backgroundColor ?? scheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                child: bottomBar,
              ),
          ],
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = InkResponse(
      onTap: onTap,
      radius: 24,
      child: SizedBox(width: 48, height: 48, child: Icon(icon, size: 20)),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// 移动端顶部操作按钮：保证 48dp 触摸目标。
class MobileHeaderAction extends StatelessWidget {
  const MobileHeaderAction({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.badgeCount,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    Widget child = Icon(icon, size: 22);
    if (badgeCount != null && badgeCount! > 0) {
      child = Badge.count(count: badgeCount!, child: child);
    }
    final button = InkResponse(
      onTap: onTap,
      radius: 24,
      child: SizedBox(width: 48, height: 48, child: Center(child: child)),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
