import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../utils/app_logger.dart';

/// Starts one Pi host transport for the current platform.
typedef PiHostProcessLauncher =
    Future<PiHostProcess> Function({required String hostScript});

/// One NAI Agent host transport.
///
/// Desktop starts `host.mjs` as a child process and uses its stdin/stdout;
/// Android embeds libnode in the app process and carries the same
/// newline-delimited JSON protocol over a MethodChannel.
abstract class PiHostProcess {
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  Future<int> get exitCode;

  /// Writes raw protocol bytes; callers include the trailing newline.
  void write(String data);

  /// Stops this transport. Embedded transports detach only: the single
  /// process-wide Node runtime must stay alive because libnode cannot be
  /// started twice in the same process.
  Future<void> kill();

  /// Persistent transports outlive one client (see [kill]) and therefore must
  /// not be awaited through [exitCode] when a session closes.
  bool get persistent => false;
}

/// A normal desktop child process.
class NativePiHostProcess implements PiHostProcess {
  NativePiHostProcess(this._process);

  final Process _process;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  void write(String data) => _process.stdin.write(data);

  @override
  Future<void> kill() async => _process.kill();

  @override
  bool get persistent => false;
}

/// Process-wide embedded Node runtime shared by every Agent client.
///
/// The runtime is started once (libnode cannot be started a second time);
/// `host.mjs` runs in reinit mode on Android, so closing a session only sends
/// `shutdown` and the next client starts with a fresh `init`.
class EmbeddedNodeRuntime {
  EmbeddedNodeRuntime._();

  static final EmbeddedNodeRuntime instance = EmbeddedNodeRuntime._();

  static const _channel = MethodChannel('com.nailauncher/node_runtime');

  final _stdout = StreamController<Uint8List>.broadcast();
  final _stderr = StreamController<Uint8List>.broadcast();
  bool _started = false;
  bool _handlerInstalled = false;

  Stream<Uint8List> get stdout => _stdout.stream;
  Stream<Uint8List> get stderr => _stderr.stream;
  bool get isStarted => _started;

  Future<void> ensureStarted({
    required String hostScript,
    required String workingDirectory,
  }) async {
    _installHandler();
    if (_started) return;
    final started = await _channel.invokeMethod<bool>('start', {
      'scriptPath': hostScript,
      'workingDirectory': workingDirectory,
    });
    if (started != true) {
      throw const FileSystemException('Embedded Node runtime failed to start');
    }
    _started = true;
  }

  void write(String data) {
    unawaited(
      _channel
          .invokeMethod<void>('writeStdin', {'data': data})
          .catchError((Object _) {}),
    );
  }

  void _installHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'event') return null;
      final map = Map<String, dynamic>.from(call.arguments as Map);
      final payload = map['payload'] as String? ?? '';
      final line = Uint8List.fromList('$payload\n'.codeUnits);
      switch (map['type']) {
        case 'stdout':
          _stdout.add(line);
        case 'stderr':
          _stderr.add(line);
        case 'exit':
          _started = false;
          AppLogger.w('Embedded Node runtime exited: $payload', 'Agent');
      }
      return null;
    });
  }
}

/// Embedded transport view for one Agent session.
class EmbeddedNodePiHostProcess implements PiHostProcess {
  EmbeddedNodePiHostProcess._(
    this._runtime,
    this._stdoutController,
    this._stderrController,
  );

  final EmbeddedNodeRuntime _runtime;
  final StreamController<List<int>> _stdoutController;
  final StreamController<List<int>> _stderrController;
  final Completer<int> _exit = Completer<int>();
  StreamSubscription<Uint8List>? _stdoutSubscription;
  StreamSubscription<Uint8List>? _stderrSubscription;
  bool _detached = false;

  static Future<EmbeddedNodePiHostProcess> start({
    required String hostScript,
    required String workingDirectory,
  }) async {
    final runtime = EmbeddedNodeRuntime.instance;
    await runtime.ensureStarted(
      hostScript: hostScript,
      workingDirectory: workingDirectory,
    );
    final process = EmbeddedNodePiHostProcess._(
      runtime,
      StreamController<List<int>>(),
      StreamController<List<int>>(),
    );
    process._stdoutSubscription = runtime.stdout.listen(
      process._stdoutController.add,
    );
    process._stderrSubscription = runtime.stderr.listen(
      process._stderrController.add,
    );
    return process;
  }

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void write(String data) => _runtime.write(data);

  @override
  bool get persistent => true;

  @override
  Future<void> kill() async {
    if (_detached) return;
    _detached = true;
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    if (!_exit.isCompleted) _exit.complete(0);
  }
}
