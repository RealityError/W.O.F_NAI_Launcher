import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/android_share_intake.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/desktop_platform.dart';
import '../../core/utils/localization_extension.dart';
import '../router/app_router.dart';
import '../services/image_workflow_launcher.dart';
import '../widgets/common/app_toast.dart';

/// Mounts the Android "share image into the app" intake (G16).
///
/// Uses the same global side-effect mounting layer as the clipboard history
/// paste bridge: `AppBootstrapEffects.initState` calls [attach] and `dispose`
/// calls [detach]. On Windows/macOS both are no-ops, so desktop is untouched.
class AndroidShareWiring {
  AndroidShareWiring._();

  static WidgetRef? _ref;
  static bool _attached = false;

  static void attach(WidgetRef ref) {
    if (!isAndroidPlatform || _attached) return;
    _attached = true;
    _ref = ref;
    final intake = AndroidShareIntake.instance;
    // attach() 先置上 _attached，setHandler() 的首次 poll 才能取到冷启动分享。
    unawaited(intake.attach());
    intake.setHandler(_openSharedImageInImg2Img);
  }

  static void detach() {
    if (!_attached) return;
    _attached = false;
    _ref = null;
    unawaited(AndroidShareIntake.instance.detach());
  }

  /// Reuses the desktop gallery "发送到图生图" flow: load the shared image as
  /// the img2img source, focus the generation page and show the same toast.
  static Future<void> _openSharedImageInImg2Img(String path) async {
    final ref = _ref;
    if (ref == null) return;
    final Uint8List bytes;
    try {
      final file = File(path);
      bytes = await file.readAsBytes();
      // The native side copies every share into the cache; drop the copy once
      // it is loaded into the generation workflow.
      await file.delete();
    } catch (error) {
      AppLogger.w('读取系统分享图片失败: $path ($error)', 'AndroidShare');
      return;
    }
    if (bytes.isEmpty) return;
    try {
      ImageWorkflowLauncher.openImageToImage(ref, bytes);
      ref.read(appRouterProvider).go(AppRoutes.home);
      _showSharedToast();
    } catch (error) {
      AppLogger.w('打开系统分享图片失败: $path ($error)', 'AndroidShare');
    }
  }

  static void _showSharedToast() {
    final context = _ref
        ?.read(appRouterProvider)
        .routerDelegate
        .navigatorKey
        .currentContext;
    if (context == null || !context.mounted) return;
    AppToast.success(context, context.l10n.localGallery_sentToImageToImage);
  }
}
