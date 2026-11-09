import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_support_directory.dart';
import 'studio_sandbox.dart';

abstract final class AppBundlePaths {
  static const macBundleId = 'com.wof.naiStudio';
  static final executableDirectory = p.dirname(Platform.resolvedExecutable);

  static String? get macBundle {
    if (!Platform.isMacOS || p.basename(executableDirectory) != 'MacOS') {
      return null;
    }
    final contents = p.dirname(executableDirectory);
    final bundle = p.dirname(contents);
    return p.basename(contents) == 'Contents' && bundle.endsWith('.app')
        ? bundle
        : null;
  }

  static String get toolsDirectory {
    final bundle = macBundle;
    return bundle == null
        ? p.join(executableDirectory, 'tools')
        : p.join(bundle, 'Contents', 'Resources', 'tools');
  }

  static String? _macSupport;
  static String? _androidSupport;

  static Future<void> prepare() async {
    if (Platform.isMacOS) {
      _macSupport = (await getApplicationSupportDirectory()).path;
    }
    if (Platform.isAndroid) {
      _androidSupport = (await getApplicationSupportDirectory()).path;
    }
  }

  /// Android has no writable directory next to the executable (the APK's
  /// native-library folder is read-only), so Agent state belongs in the app
  /// support directory. Desktop keeps the installer-owned layout beside the
  /// executable and is unchanged.
  static String resolveAgentDataDirectory({
    required bool android,
    required String executableDirectory,
    String? androidSupport,
    String? macSupport,
    bool macOS = false,
  }) {
    if (android) {
      final root = androidSupport;
      if (root == null) {
        throw StateError('Application data is not prepared');
      }
      return p.join(root, 'nai_agent', 'agent-data');
    }
    final root = macOS ? macSupport : executableDirectory;
    if (root == null) {
      throw StateError('Application data is not prepared');
    }
    return p.join(root, 'agent-data');
  }

  static String get agentDataDirectory {
    if (studioSandboxRoot() case final sandbox?) {
      return p.join(sandbox, 'agent-data');
    }
    final macFallback =
        _macSupport ??
        (Platform.environment['FLUTTER_TEST'] == 'true'
            ? p.join(Directory.systemTemp.path, 'nai-launcher-test')
            : null);
    return resolveAgentDataDirectory(
      android: Platform.isAndroid,
      executableDirectory: executableDirectory,
      androidSupport: _androidSupport,
      macSupport: macFallback,
      macOS: Platform.isMacOS,
    );
  }
}
