import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/app_logger.dart';
import '../utils/desktop_platform.dart';
import '../utils/file_explorer_utils.dart';

/// Android outbound image sharing (G15) built on the existing
/// `com.nailauncher/platform` channel used by [PlatformFileChannel].
///
/// Two shapes of source images exist by the time a share entry is tapped:
/// - a real file path (local gallery, saved generation result),
/// - raw PNG bytes only (unsaved generation result).
/// Both end up as an `ACTION_SEND` share sheet through the platform channel.
///
/// The whole service is inert on Windows/macOS so desktop menus and behavior
/// stay unchanged.
class AndroidShareService {
  AndroidShareService._();

  /// Test hook: lets widget/unit tests exercise the Android branch on the
  /// desktop test host, where [Platform.isAndroid] is false.
  @visibleForTesting
  static bool? debugForceSupported;

  static bool get supported => debugForceSupported ?? isAndroidPlatform;

  /// Shares an existing file through the system share sheet.
  static Future<bool> shareFile(String path, {String? mimeType}) async {
    if (!supported) return false;
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    if (!await File(trimmed).exists()) {
      AppLogger.w('分享失败，文件不存在: $trimmed', 'AndroidShare');
      return false;
    }
    return _invokeShare(
      trimmed,
      mimeType ?? PlatformFileChannel.mimeTypeForPath(trimmed),
    );
  }

  /// Writes [bytes] into a cache file and shares that file.
  ///
  /// Used by the generation viewer when the image has not been saved yet.
  static Future<bool> shareBytes(
    Uint8List bytes, {
    String fileName = 'image.png',
    String? mimeType,
  }) async {
    if (!supported) return false;
    if (bytes.isEmpty) return false;
    try {
      final directory = await _outgoingDirectory();
      final target = File(p.join(directory.path, shareTempFileName(fileName)));
      await target.writeAsBytes(bytes, flush: true);
      return await _invokeShare(
        target.path,
        mimeType ?? PlatformFileChannel.mimeTypeForPath(target.path),
      );
    } catch (error) {
      AppLogger.w('分享图片字节失败: $error', 'AndroidShare');
      return false;
    }
  }

  static Future<bool> _invokeShare(String path, String mimeType) async {
    try {
      final shared = await PlatformFileChannel.channel.invokeMethod<bool>(
        'shareFile',
        {'path': path, 'mimeType': mimeType},
      );
      return shared ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      AppLogger.w(
        'shareFile failed: ${error.code} ${error.message}',
        'AndroidShare',
      );
      return false;
    }
  }

  static Future<Directory> _outgoingDirectory() async {
    final temporary = await getTemporaryDirectory();
    final directory = Directory(p.join(temporary.path, 'outgoing_shares'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    } else {
      await _pruneOldFiles(directory);
    }
    return directory;
  }

  /// Shared images handed to other apps must stay on disk until the receiver
  /// has read the granted content uri, so only prune day-old leftovers.
  static Future<void> _pruneOldFiles(Directory directory) async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 1));
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          await entity.delete();
        }
      }
    } catch (error) {
      AppLogger.w('清理分享缓存失败: $error', 'AndroidShare');
    }
  }

  /// Cache file name for a byte share: timestamp prefix keeps names unique
  /// while the receiver still sees the original image name.
  static String shareTempFileName(String fileName, {DateTime? now}) {
    final stamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return '${stamp}_${safeShareFileName(fileName)}';
  }

  /// Strips path separators / characters the share sheet would reject and
  /// guarantees a file extension.
  static String safeShareFileName(String fileName) {
    var base = p.basename(fileName).trim();
    base = base.replaceAll(RegExp(r'[\\/:*?"<>|\u0000-\u001f]'), '_');
    if (base.replaceAll('_', '').isEmpty) {
      base = 'image';
    }
    if (!base.contains('.')) {
      base = '$base.png';
    }
    return base;
  }
}
