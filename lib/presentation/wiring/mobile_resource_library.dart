import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/floating_resource_windows_provider.dart';
import '../ui/kit/ui_colors.dart';
import 'floating_resource_window.dart';
import 'floating_resource_windows_host.dart';

/// 手机端资源库全屏页：块库点按插入提示词，风格库/精准参考点按加入生图页。
///
/// 打开流程见 [ResourceWindowOpener.open]：先建一个不落盘的临时浮窗，再用
/// `showGeneralDialog` 推出本页；关闭/返回时弹窗结束并回收这个临时窗口。
class MobileResourceLibraryPage extends ConsumerWidget {
  const MobileResourceLibraryPage({super.key, required this.windowId});

  final String windowId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final windows = ref.watch(floatingResourceWindowsProvider);
    FloatingWindowData? window;
    for (final item in windows) {
      if (item.id == windowId) {
        window = item;
        break;
      }
    }
    if (window == null) return const SizedBox.shrink();
    return Scaffold(
      backgroundColor: context.ui.bg,
      body: FloatingResourceWindow(
        key: ValueKey('mobile-resource-window-$windowId'),
        window: window,
        controller: FloatingWindowController(
          ref.read(floatingResourceWindowsProvider.notifier),
          windowId,
        ),
        onClose: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}
