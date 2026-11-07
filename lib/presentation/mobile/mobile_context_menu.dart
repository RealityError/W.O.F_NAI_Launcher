import 'package:flutter/material.dart';

import 'mobile_breakpoints.dart';
import 'mobile_sheet.dart';

/// 手机端上下文菜单项。
class MobileMenuItem {
  const MobileMenuItem({
    required this.label,
    this.icon,
    this.onTap,
    this.destructive = false,
    this.enabled = true,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool destructive;
  final bool enabled;
}

/// 弹出手机端上下文菜单（bottom sheet）。
Future<void> showMobileContextMenu(
  BuildContext context, {
  String? title,
  required List<MobileMenuItem> items,
}) {
  if (items.isEmpty) return Future<void>.value();
  return showMobileSheet<void>(
    context: context,
    title: title,
    heightFactor: 0.6,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final scheme = theme.colorScheme;
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          for (final item in items)
            ListTile(
              enabled: item.enabled,
              leading: item.icon == null ? null : Icon(item.icon, size: 22),
              title: Text(
                item.label,
                style: TextStyle(
                  color: !item.enabled
                      ? scheme.onSurface.withValues(alpha: 0.38)
                      : item.destructive
                      ? scheme.error
                      : null,
                  fontWeight: item.destructive ? FontWeight.w600 : null,
                ),
              ),
              onTap: item.enabled
                  ? () {
                      Navigator.of(sheetContext).pop();
                      item.onTap?.call();
                    }
                  : null,
            ),
        ],
      );
    },
  );
}

/// 让子组件同时支持"桌面右键"和"手机长按"的上下文菜单。
///
/// 仅在移动端布局分支使用；桌面端不做任何拦截（保持原有右键菜单行为）。
class MobileContextMenuRegion extends StatelessWidget {
  const MobileContextMenuRegion({
    super.key,
    required this.child,
    required this.items,
    this.title,
    this.onLongPress,
    this.enabled,
  });

  final Widget child;
  final List<MobileMenuItem> items;
  final String? title;

  /// 额外的长按回调（例如进入多选模式），执行后不再弹出菜单。
  final VoidCallback? onLongPress;

  /// 默认按平台判断；widget 测试可显式开启。
  final bool? enabled;

  @override
  Widget build(BuildContext context) {
    if (!(enabled ?? usesMobileLayout)) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: () {
        if (onLongPress != null) {
          onLongPress!();
          return;
        }
        showMobileContextMenu(context, title: title, items: items);
      },
      child: child,
    );
  }
}
