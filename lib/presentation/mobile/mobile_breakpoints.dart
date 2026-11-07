import 'package:flutter/widgets.dart';

import '../../core/utils/desktop_platform.dart';

/// 手机端布局断点（与 design_tokens.dart 的 600 / 900 对齐）。
const double kMobileBreakpoint = 600;
const double kTabletBreakpoint = 900;

/// 设备形态，仅按可用宽度区分；平台能力用 [usesMobileLayout] 判断。
enum FormFactor { phone, tablet, desktop }

/// 是否使用手机端布局。
///
/// 只由平台决定：桌面窗口最小宽度 800，且桌面视觉/布局必须保持不变；
/// Android（含平板）统一走移动布局，竖屏为验收目标。
bool get usesMobileLayout => debugForceMobileLayout ?? isMobilePlatform;

/// 仅供 widget 测试 / 桌面预览强制启用移动布局；null 表示按平台判断。
bool? debugForceMobileLayout;

/// 按当前可用宽度判断形态（用于移动端内部再细分，如平板放大间距）。
FormFactor formFactorOf(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < kMobileBreakpoint) return FormFactor.phone;
  if (width < kTabletBreakpoint) return FormFactor.tablet;
  return FormFactor.desktop;
}

/// 供移动端布局使用的宽度（不随系统字号缩放）。
double mobileViewportWidth(BuildContext context) =>
    MediaQuery.sizeOf(context).width;

/// 底部安全区 + 键盘 inset，供自定义底部栏使用。
EdgeInsets mobileBottomInset(BuildContext context) {
  final media = MediaQuery.of(context);
  return EdgeInsets.only(
    left: media.padding.left,
    right: media.padding.right,
    bottom: media.viewInsets.bottom > 0
        ? media.viewInsets.bottom
        : media.padding.bottom,
  );
}
