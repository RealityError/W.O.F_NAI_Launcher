import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../utils/app_support_directory.dart';
import '../utils/desktop_platform.dart';
import 'node_runtime_bundle.dart';
import 'pi_host_process.dart';

/// Android-only holder for the embedded NAI Agent runtime.
///
/// The packed runtime is extracted lazily on the first Agent session; the
/// process-wide libnode instance then stays alive for every later session.
class AndroidNaiAgentRuntime {
  AndroidNaiAgentRuntime();

  AndroidNodeRuntimeBundle? _bundle;
  Future<Directory>? _ready;

  Future<Directory> ensure({
    void Function(String message, double progress)? onProgress,
  }) => _ready ??= _prepare(onProgress);

  Future<Directory> _prepare(
    void Function(String message, double progress)? onProgress,
  ) async {
    final support = await getApplicationSupportDirectory();
    final bundle = AndroidNodeRuntimeBundle(
      root: Directory(p.join(support.path, 'nai_agent', 'runtime')),
    );
    final directory = await bundle.ensure(onProgress: onProgress);
    _bundle = bundle;
    return directory;
  }

  String get hostScript {
    final bundle = _bundle;
    if (bundle == null) {
      throw StateError('NAI Agent runtime is not ready');
    }
    return bundle.hostScript;
  }

  Future<PiHostProcess> start({required String hostScript}) async {
    final directory = await ensure();
    return EmbeddedNodePiHostProcess.start(
      hostScript: p.join(directory.path, 'android-host.mjs'),
      workingDirectory: directory.path,
    );
  }
}

/// Null on desktop, where the installer-owned runtime is used instead.
final androidNaiAgentRuntimeProvider = Provider<AndroidNaiAgentRuntime?>((ref) {
  if (!isAndroidPlatform) return null;
  return AndroidNaiAgentRuntime();
});
