import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../utils/app_logger.dart';
import '../utils/desktop_platform.dart';
import '../utils/file_explorer_utils.dart';

/// Android inbound image sharing (G16): receives images sent to the app from
/// other applications through `ACTION_SEND` (`image/*`).
///
/// The native side (`MainActivity`) copies the shared `content://` image into
/// the app cache and keeps it pending until Dart asks for it:
/// - `getSharedImage` (Dart → native): returns and clears the pending path;
/// - `shareImageReceived` (native → Dart, no args): signal that an image was
///   shared while the app was already running (`onNewIntent`).
///
/// The presentation layer owns what happens with the image; this service only
/// transports cache file paths and never touches the UI. On Windows/macOS it
/// stays completely inert.
class AndroidShareIntake with WidgetsBindingObserver {
  AndroidShareIntake._();

  static final AndroidShareIntake instance = AndroidShareIntake._();

  /// Test hook: lets tests exercise the Android branch on the desktop host.
  @visibleForTesting
  static bool? debugForceSupported;

  static bool get supported => debugForceSupported ?? isAndroidPlatform;

  /// Channel methods shared with `android/app/src/main/kotlin/.../MainActivity.kt`.
  static const String takeSharedImageMethod = 'getSharedImage';
  static const String shareReceivedSignal = 'shareImageReceived';

  Future<void> Function(String path)? _handler;
  bool _attached = false;
  bool _reading = false;
  bool _signalQueued = false;
  final Set<String> _delivered = <String>{};

  /// Registers the consumer and immediately drains any image that started the
  /// app. Called by the presentation wiring; passing null detaches delivery.
  void setHandler(Future<void> Function(String path)? handler) {
    if (!supported) return;
    _handler = handler;
    if (handler != null) {
      unawaited(poll());
    }
  }

  Future<void> attach() async {
    if (!supported || _attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
    PlatformFileChannel.channel.setMethodCallHandler(_onNativeCall);
  }

  Future<void> detach() async {
    if (!_attached) return;
    _attached = false;
    WidgetsBinding.instance.removeObserver(this);
    PlatformFileChannel.channel.setMethodCallHandler(null);
    _handler = null;
    _delivered.clear();
  }

  /// Pulls the next pending shared image from the native side and hands it to
  /// the registered handler. Safe to call repeatedly (startup / resume).
  Future<void> poll() async {
    if (!supported || !_attached) return;
    if (_reading || _handler == null) return;
    _reading = true;
    try {
      final path = await _takeSharedImage();
      if (path == null || path.isEmpty) return;
      if (!_delivered.add(path)) return;
      final handler = _handler;
      if (handler == null) return;
      await handler(path);
    } catch (error) {
      AppLogger.w('处理系统分享图片失败: $error', 'AndroidShare');
    } finally {
      _reading = false;
      if (_signalQueued) {
        _signalQueued = false;
        unawaited(poll());
      }
    }
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method != shareReceivedSignal) {
      throw MissingPluginException();
    }
    // 信号到来时可能已有一次 poll 在读：排到下一轮，避免漏掉这张图。
    if (_reading) {
      _signalQueued = true;
      return null;
    }
    unawaited(poll());
    return null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(poll());
  }

  Future<String?> _takeSharedImage() async {
    try {
      return await PlatformFileChannel.channel.invokeMethod<String>(
        takeSharedImageMethod,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      AppLogger.w(
        'getSharedImage failed: ${error.code} ${error.message}',
        'AndroidShare',
      );
      return null;
    }
  }
}
