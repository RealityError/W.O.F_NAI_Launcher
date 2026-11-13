import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../utils/app_logger.dart';

/// Encodes one protocol line for the byte-oriented embedded transport.
///
/// Payloads contain UTF-8 JSON text (Chinese prompts, system prompts), so the
/// string must be encoded as UTF-8. Casting UTF-16 code units to bytes mangles
/// every non-ASCII character and fails the line decoder downstream.
Uint8List encodeHostPayload(String payload) =>
    Uint8List.fromList(utf8.encode('$payload\n'));

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
/// `android-host.mjs` routes each client to an isolated Worker, so closing
/// translation does not reset an active Studio session.
class EmbeddedNodeRuntime {
  EmbeddedNodeRuntime._();

  static final EmbeddedNodeRuntime instance = EmbeddedNodeRuntime._();

  static const _channel = MethodChannel('com.nailauncher/node_runtime');

  final _stdout = StreamController<Uint8List>.broadcast();
  final _stderr = StreamController<Uint8List>.broadcast();
  bool _started = false;
  bool _handlerInstalled = false;
  Future<void>? _starting;

  Stream<Uint8List> get stdout => _stdout.stream;
  Stream<Uint8List> get stderr => _stderr.stream;
  bool get isStarted => _started;

  Future<void> ensureStarted({
    required String hostScript,
    required String workingDirectory,
  }) => _starting ??= _start(hostScript, workingDirectory).whenComplete(() {
    _starting = null;
  });

  Future<void> _start(String hostScript, String workingDirectory) async {
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

  Future<void> write(String data) =>
      _channel.invokeMethod<void>('writeStdin', {'data': data});

  void _installHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'event') return null;
      final map = Map<String, dynamic>.from(call.arguments as Map);
      final payload = map['payload'] as String? ?? '';
      final line = encodeHostPayload(payload);
      switch (map['type']) {
        case 'stdout':
          _stdout.add(line);
        case 'stderr':
          _stderr.add(line);
        case 'exit':
          _started = false;
          _stdout.addError(StateError('Embedded Node runtime exited'));
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
    this._transportId,
  );

  final EmbeddedNodeRuntime _runtime;
  final StreamController<List<int>> _stdoutController;
  final StreamController<List<int>> _stderrController;
  final String _transportId;
  static int _sequence = 0;
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
      'embedded-${++_sequence}',
    );
    process._stdoutSubscription = runtime.stdout.listen(
      process._receive,
      onError: process._stdoutController.addError,
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
  void write(String data) {
    if (_detached) throw StateError('Embedded transport closed');
    final message = (jsonDecode(data) as Map).cast<String, dynamic>();
    unawaited(
      _runtime
          .write('${jsonEncode({...message, 'transportId': _transportId})}\n')
          .catchError((Object error) {
            if (!_detached) _stdoutController.addError(error);
          }),
    );
  }

  void _receive(Uint8List data) {
    if (_detached) return;
    try {
      final message = (jsonDecode(utf8.decode(data)) as Map)
          .cast<String, dynamic>();
      if (message['transportId'] != _transportId) return;
      if (message['type'] == 'transport_closed') {
        _stdoutController.addError(StateError('Embedded session closed'));
        return;
      }
      message.remove('transportId');
      _stdoutController.add(encodeHostPayload(jsonEncode(message)));
    } catch (_) {
      _stdoutController.addError(const FormatException('Invalid host payload'));
    }
  }

  @override
  bool get persistent => true;

  @override
  Future<void> kill() async {
    if (_detached) return;
    _detached = true;
    try {
      await _runtime.write(
        '${jsonEncode({'transportId': _transportId, 'type': 'transport_close'})}\n',
      );
    } catch (_) {
      // The runtime may already have exited.
    }
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    unawaited(_stdoutController.close());
    unawaited(_stderrController.close());
    if (!_exit.isCompleted) _exit.complete(0);
  }
}
