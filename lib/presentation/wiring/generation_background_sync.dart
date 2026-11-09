import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_logger.dart';
import '../../core/utils/localization_extension.dart';
import '../../data/services/generation_foreground_service.dart';
import '../providers/image_generation_provider.dart';
import 'notification_permission_wiring.dart';

/// 生成中把 App 挂到 Android 前台服务上：切后台不被系统回收，通知栏显示进度，
/// 完成 / 失败 / 取消时用一条普通通知告诉用户。
///
/// 只在 Android 生效；桌面平台 [GenerationForegroundService.isSupported] 为
/// false，所有调用都是 no-op，不改变桌面行为。
class GenerationBackgroundSync {
  GenerationBackgroundSync._();

  static bool _attached = false;
  static WidgetRef? _ref;
  static ProviderSubscription<ImageGenerationState>? _subscription;
  static double _lastProgress = -1;
  static int _lastCurrentImage = -1;

  /// 在应用启动时挂一次（`_AppBootstrapEffectsState.initState`）。
  ///
  /// initState 阶段不允许用 `ref.listen`（它只能在 build 里调用），这里用
  /// `listenManual` 并持有订阅，由 [detach] 关闭。
  static void attach(WidgetRef ref) {
    if (!GenerationForegroundService.isSupported || _attached) return;
    _attached = true;
    _ref = ref;
    _subscription = ref.listenManual<ImageGenerationState>(
      imageGenerationNotifierProvider,
      (previous, next) => updateForState(previous, next),
    );
    AppLogger.i('Attached background generation sync', 'GenerationBackground');
  }

  /// 解开监听（`_AppBootstrapEffectsState.dispose`）。
  static void detach() {
    _subscription?.close();
    _subscription = null;
    _attached = false;
    _ref = null;
    _lastProgress = -1;
    _lastCurrentImage = -1;
  }

  @visibleForTesting
  static void resetForTest() {
    _subscription?.close();
    _subscription = null;
    _attached = false;
    _ref = null;
    _lastProgress = -1;
    _lastCurrentImage = -1;
  }

  /// 生成状态迁移 → 前台服务 / 通知。状态没变化时只按节流更新进度。
  @visibleForTesting
  static void updateForState(
    ImageGenerationState? previous,
    ImageGenerationState next,
  ) {
    if (!GenerationForegroundService.isSupported) return;
    final previousStatus = previous?.status ?? GenerationStatus.idle;
    if (next.status == previousStatus) {
      if (next.status == GenerationStatus.generating &&
          _shouldUpdateProgress(next)) {
        _updateProgress(next);
      }
      return;
    }
    switch (next.status) {
      case GenerationStatus.generating:
        // 启动时记住当前进度/张数，避免首帧立刻再刷一条重复通知。
        _lastProgress = next.progress;
        _lastCurrentImage = next.currentImage;
        // Android 13+：只在真正开始生成（即将用前台服务跑后台）时申请
        // 通知权限；拒绝后不会重复申请，详见 NotificationPermissionWiring。
        final ref = _ref;
        if (ref != null) {
          NotificationPermissionWiring.onGenerationStarted(ref);
        }
        unawaited(
          GenerationForegroundService.start(
            title: currentL10n.generation_backgroundRunningTitle,
            text: currentL10n.generation_backgroundRunningText,
          ),
        );
      case GenerationStatus.completed:
        unawaited(
          GenerationForegroundService.stop(
            title: currentL10n.generation_backgroundDoneTitle,
            text: currentL10n.generation_backgroundDoneText(_imageCount(next)),
          ),
        );
      case GenerationStatus.error:
        unawaited(
          GenerationForegroundService.stop(
            title: currentL10n.generation_backgroundFailedTitle,
            text: currentL10n.generation_backgroundFailedText,
          ),
        );
      case GenerationStatus.cancelled:
        unawaited(
          GenerationForegroundService.stop(
            title: currentL10n.generation_backgroundCancelledTitle,
            text: currentL10n.generation_backgroundCancelledText,
          ),
        );
      case GenerationStatus.idle:
        break;
    }
  }

  static int _imageCount(ImageGenerationState state) {
    if (state.currentImages.isNotEmpty) return state.currentImages.length;
    return state.totalImages;
  }

  static bool _shouldUpdateProgress(ImageGenerationState state) {
    if (state.progress - _lastProgress >= 0.02 ||
        _lastProgress - state.progress >= 0.02) {
      return true;
    }
    return state.currentImage != _lastCurrentImage;
  }

  static void _updateProgress(ImageGenerationState state) {
    _lastProgress = state.progress;
    _lastCurrentImage = state.currentImage;
    final total = state.totalImages;
    final current = state.currentImage;
    unawaited(
      GenerationForegroundService.update(
        title: currentL10n.generation_backgroundRunningTitle,
        text: total > 0
            ? '${currentL10n.generation_backgroundRunningText}  '
                  '${current.clamp(0, total)}/$total'
            : currentL10n.generation_backgroundRunningText,
        progress: state.progress,
      ),
    );
  }
}
