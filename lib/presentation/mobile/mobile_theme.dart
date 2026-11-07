import 'package:flutter/material.dart';

/// 手机端主题微调：不改变颜色方案，只把桌面交互语义换成触屏语义。
///
/// - Tooltip 改为长按触发（覆盖现有全部 Tooltip 调用点）；
/// - 触摸目标按 Material 建议留白；
/// - 保持现有视觉密度，避免与桌面设计稿产生偏差。
ThemeData mobileAdaptiveTheme(ThemeData base) {
  return base.copyWith(
    tooltipTheme: base.tooltipTheme.copyWith(
      triggerMode: TooltipTriggerMode.longPress,
      waitDuration: const Duration(milliseconds: 350),
      showDuration: const Duration(seconds: 3),
    ),
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
  );
}
