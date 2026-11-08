import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/localization_extension.dart';
import '../providers/canvas_settings_provider.dart';
import '../ui/gen/gen_parts.dart';
import '../ui/kit/ui_glyph.dart';

/// 手机端「解除相机锁定」入口：锁相机会禁用一切手动相机输入（拖拽平移、
/// 双指缩放），触屏上没有任何替代操作，画布看上去就像「图片流不动了」。
/// 因此只在锁定状态出现一个顶栏按钮，点一下即恢复手势浏览。
///
/// 读 provider 的接线放在这里：`lib/presentation/ui/gen` 只认契约，
/// 由 [GenSlots.mobileHeaderActions] 注入手机顶栏动作。
class GenMobileCameraLockWiring extends ConsumerWidget {
  const GenMobileCameraLockWiring({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = ref.watch(canvasLockCameraNotifierProvider);
    if (!locked) return const SizedBox.shrink();
    return GenIb(
      key: const Key('gen-mobile-unlock-camera'),
      glyph: UiGlyphs.lock,
      glyphSize: 16,
      tooltip: context.l10n.gen_unlockCamera,
      onTap: () =>
          ref.read(canvasLockCameraNotifierProvider.notifier).setLocked(false),
    );
  }
}
