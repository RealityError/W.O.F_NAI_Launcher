import 'package:flutter/material.dart';

/// 手机端统一底部弹层（bottom sheet）。
///
/// 用于替代桌面端的侧栏 / 固定面板 / 对话框：设置项编辑、生成页参数与提示词、
/// 图库筛选与操作菜单等。自动处理安全区、键盘 inset 与顶部圆角。
Future<T?> showMobileSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  double heightFactor = 0.9,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useRootNavigator = false,
  Color? backgroundColor,
}) {
  final theme = Theme.of(context);
  final screenHeight = MediaQuery.sizeOf(context).height;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useRootNavigator: useRootNavigator,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: screenHeight * heightFactor),
          child: Material(
            color: backgroundColor ?? theme.colorScheme.surface,
            clipBehavior: Clip.antiAlias,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SheetHandle(title: title),
                Flexible(child: builder(sheetContext)),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle({this.title});

  final String? title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title!,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// 弹层里常用的滚动列表容器：自带底部安全区留白。
class MobileSheetScrollView extends StatelessWidget {
  const MobileSheetScrollView({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 24),
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ListView(shrinkWrap: true, padding: padding, children: children);
  }
}
