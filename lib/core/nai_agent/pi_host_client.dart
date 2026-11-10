import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../utils/app_logger.dart';
import 'agent_tool.dart';
import 'node_runtime_environment.dart';
import 'model_request_gate.dart';
import 'pi_host_process.dart';
import 'vision_access.dart';

/// Owns one official Pi session. It transports events/tools; Pi owns the loop.
/// Desktop starts the bundled Node host as a child process; Android reuses the
/// single embedded libnode runtime.
class PiHostClient {
  PiHostClient._(
    this._process,
    this.workspaceId,
    this.executeTool,
    this._providerId,
    this._requestLimit,
    this._requestAccessToken,
    this.visionAccess,
  ) {
    _stdout = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _receive,
          onError: (Object error) => _lost('stdout_error $error'),
        );
    // Dependency diagnostics may include provider data, so stderr stays hidden
    // in release builds; debug builds log truncated lines to diagnose host
    // failures that otherwise only surface as a generic UI toast.
    _stderr = _process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
          if (!kDebugMode || line.isEmpty) return;
          AppLogger.w(
            'Pi host stderr: '
                '${line.length > 320 ? '${line.substring(0, 320)}…' : line}',
            'Agent',
          );
        }, onError: (_) {});
    if (!_process.persistent) {
      unawaited(_process.exitCode.then((_) => _lost('process_exit')));
    }
  }
  final PiHostProcess _process;
  final String workspaceId;
  final NaiAgentToolExecutor executeTool;
  final String _providerId;
  final int _requestLimit;
  final Future<String> Function()? _requestAccessToken;
  final NaiAgentVisionAccess visionAccess;
  final _extensionEvents = <Map<String, dynamic>>[];
  late final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast(
        onListen: () => scheduleMicrotask(() {
          if (_closed) return;
          final buffered = [..._extensionEvents];
          _extensionEvents.clear();
          for (final event in buffered) {
            _events.add(event);
          }
        }),
      );
  final _requests = <String, Completer<Map<String, dynamic>>>{};
  final _tools = <String, NaiAgentCancellation>{};
  final _permits = <String, NaiAgentCancellation>{};
  final _releases = <String, void Function()>{};
  late final StreamSubscription<String> _stdout;
  late final StreamSubscription<String> _stderr;
  int _sequence = 0;
  String? _sessionId;
  bool _closed = false;
  bool _closing = false;
  Map<String, dynamic> _initialState = {};
  String? get sessionId => _sessionId;
  Stream<Map<String, dynamic>> get events => _events.stream;
  Map<String, dynamic> get initialState => Map.of(_initialState);
  bool get isClosed => _closed;
  bool get hasPendingRequests => _requests.isNotEmpty;
  Future<void> get whenClosed => _process.exitCode.then((_) {});

  static Future<PiHostClient> start({
    String? nodeExecutable,
    String? hostScript,
    PiHostProcessLauncher? launcher,
    required String workspaceId,
    required Directory workspaceDirectory,
    required Directory agentDirectory,
    required String systemPrompt,
    required Map<String, dynamic> privateModelConfig,
    required NaiAgentToolExecutor executeTool,
    Future<String> Function()? requestAccessToken,
    NaiAgentVisionAccess visionAccess = const NaiAgentVisionAccess(),
    Directory? sessionDirectory,
    File? sessionFile,
    String? sessionName,
    String? sessionKind,
    String? seedSystemPrompt,
    List<Map<String, dynamic>> seedMessages = const [],
    List<String> extraToolNames = const [],
    List<String> extensionPaths = const [],
    Map<String, dynamic> mcp = const {},
    Map<String, dynamic> skills = const {},
    Map<String, dynamic> prompts = const {},
    Map<String, dynamic> packages = const {},
  }) async {
    final providerId = privateModelConfig['providerId'];
    if (providerId is! String || providerId.trim().isEmpty) {
      throw const FormatException('Pi provider identity missing');
    }
    final PiHostProcess process;
    if (launcher != null) {
      if (hostScript == null) {
        throw ArgumentError('hostScript is required with a launcher');
      }
      process = await launcher(hostScript: hostScript);
    } else {
      if (nodeExecutable == null || hostScript == null) {
        throw ArgumentError('nodeExecutable and hostScript are required');
      }
      process = NativePiHostProcess(
        await Process.start(
          nodeExecutable,
          [hostScript],
          workingDirectory: File(hostScript).parent.path,
          environment: nodeRuntimeEnvironment(nodeExecutable),
          runInShell: false,
        ),
      );
    }
    final client = PiHostClient._(
      process,
      workspaceId,
      executeTool,
      providerId,
      (privateModelConfig['maxConcurrentRequests'] as int? ?? 1).clamp(1, 20),
      requestAccessToken,
      visionAccess,
    );
    try {
      final ready = await client
          ._request({
            'type': 'init',
            'cwd': workspaceDirectory.absolute.path,
            'agentDir': agentDirectory.absolute.path,
            'systemPrompt': systemPrompt,
            'config': privateModelConfig,
            if (sessionDirectory != null)
              'sessionDirectory': sessionDirectory.absolute.path,
            if (sessionFile != null) 'sessionFile': sessionFile.absolute.path,
            if (sessionName != null) 'sessionName': sessionName,
            if (sessionKind != null) 'sessionKind': sessionKind,
            if (seedSystemPrompt != null) 'seedSystemPrompt': seedSystemPrompt,
            'seedMessages': seedMessages,
            'extraToolNames': extraToolNames,
            'extensionPaths': extensionPaths,
            'mcp': mcp,
            'skills': skills,
            'prompts': prompts,
            'packages': packages,
          })
          .timeout(const Duration(seconds: 30));
      client._sessionId = ready['sessionId'] as String?;
      if (client._sessionId == null) {
        throw const FormatException('Pi session identity missing');
      }
      client._initialState = ready;
      return client;
    } catch (_) {
      await client.close();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> prompt(
    String text, {
    bool steer = false,
    List<Map<String, dynamic>>? images,
    String? queueId,
  }) => _request({
    'type': 'prompt',
    'text': text,
    'behavior': steer ? 'steer' : 'followUp',
    if (images != null) 'images': images,
    if (queueId != null) 'queueId': queueId,
  });

  Future<Map<String, dynamic>> cancelSuggestion() =>
      _request({'type': 'suggestion_cancel'});
  Future<Map<String, dynamic>> state() => _request({'type': 'state'});
  Future<Map<String, dynamic>> setPermissionMode(String mode) =>
      _request({'type': 'permission_mode', 'mode': mode});
  Future<Map<String, dynamic>> mcpCommand(String action, {String? name}) =>
      _request({
        'type': 'mcp_command',
        'action': action,
        if (name != null) 'name': name,
      });
  Future<Map<String, dynamic>> updateSettings({
    String? cacheWarming,
    bool? nextSuggestion,
  }) => _request({
    'type': 'settings',
    if (cacheWarming != null) 'cacheWarming': cacheWarming,
    if (nextSuggestion != null) 'nextSuggestion': nextSuggestion,
  });
  Future<Map<String, dynamic>> sessions() => _request({'type': 'session_list'});
  Future<Map<String, dynamic>> setSystemPrompt(String text) =>
      _request({'type': 'system_prompt', 'text': text});
  Future<Map<String, dynamic>> getSystemPrompt() =>
      _request({'type': 'system_prompt_get'});
  Future<Map<String, dynamic>> rename(String name) =>
      _request({'type': 'rename', 'name': name});
  Future<Map<String, dynamic>> compact([String? instructions]) => _request({
    'type': 'compact',
    if (instructions != null) 'instructions': instructions,
  });
  Future<Map<String, dynamic>> navigate(String entryId) =>
      _request({'type': 'navigate', 'entryId': entryId});
  Future<Map<String, dynamic>> editQueue(
    String queueId, {
    String? text,
    bool remove = false,
    bool steer = false,
  }) => _request({
    'type': 'queue_edit',
    'queueId': queueId,
    if (text != null) 'text': text,
    'remove': remove,
    if (steer) 'behavior': 'steer',
  });

  Future<void> abort() async {
    for (final token in _tools.values) {
      token.cancel();
    }
    for (final token in _permits.values) {
      token.cancel();
    }
    await _request({'type': 'abort'});
  }

  Future<Map<String, dynamic>> _request(Map<String, dynamic> message) {
    if (_closed) {
      return Future.error(
        const NaiAgentToolError('host_closed', 'Pi host closed'),
      );
    }
    final id = (++_sequence).toString();
    final completion = Completer<Map<String, dynamic>>();
    _requests[id] = completion;
    _send({...message, 'id': id});
    return completion.future;
  }

  void _send(Map<String, dynamic> message) {
    if (_closed) return;
    try {
      _process.write(
        '${jsonEncode({'protocol': 1, 'workspaceId': workspaceId, 'sessionId': _sessionId, ...message})}\n',
      );
    } catch (_) {
      _lost('write_failed');
    }
  }

  void _receive(String line) {
    if (_closed) return;
    Map<String, dynamic> message;
    try {
      message = (jsonDecode(line) as Map).cast<String, dynamic>();
    } catch (error) {
      if (kDebugMode) {
        AppLogger.w(
          'Pi host line rejected (${line.length} chars, $error): '
              '${line.length > 240 ? '${line.substring(0, 240)}…' : line}',
          'Agent',
        );
      }
      _lost('invalid_json');
      return;
    }
    if (message['protocol'] != 1 ||
        message['workspaceId'] != workspaceId ||
        (_sessionId != null && message['sessionId'] != _sessionId)) {
      if (kDebugMode) {
        AppLogger.w(
          'Pi host envelope rejected: protocol=${message['protocol']} '
              'workspace=${message['workspaceId']} '
              'session=${message['sessionId']} expected=$workspaceId/$_sessionId',
          'Agent',
        );
      }
      _lost('envelope_mismatch');
      return;
    }
    final type = message['type'];
    // A session_start handler can ask through the UI before ready resolves.
    if (_sessionId == null &&
        type == 'tool_request' &&
        message['sessionId'] is String) {
      _sessionId = message['sessionId'] as String;
    }
    if (type == 'ready' || type == 'response' || type == 'error') {
      final completion = _requests.remove(message['id']);
      if (completion != null) {
        if (type == 'error') {
          completion.completeError(
            NaiAgentToolError(
              message['code'] as String? ?? 'host_error',
              message['message'] as String? ?? 'Pi runtime failure',
            ),
          );
        } else {
          if (type == 'ready') _sessionId = message['sessionId'] as String?;
          completion.complete(message);
        }
      }
    } else if (type == 'tool_request') {
      final id = message['toolCallId'] as String;
      if (_tools.containsKey(id)) {
        _lost('duplicate_tool_request');
        return;
      }
      final token = NaiAgentCancellation();
      _tools[id] = token;
      unawaited(_execute(id, message, token));
    } else if (type == 'tool_cancel') {
      _tools[message['toolCallId']]?.cancel();
    } else if (type == 'request_permit') {
      final id = message['requestId'] as String;
      if (_permits.containsKey(id) || _releases.containsKey(id)) {
        _lost('duplicate_permit');
        return;
      }
      final token = NaiAgentCancellation();
      _permits[id] = token;
      unawaited(_acquirePermit(id, token));
    } else if (type == 'request_cancel') {
      _permits[message['requestId']]?.cancel();
      _releases.remove(message['requestId'])?.call();
    } else if (type == 'request_release') {
      _releases.remove(message['requestId'])?.call();
    }
    if (!_events.hasListener &&
        {'extension_ui', 'extension_error'}.contains(type)) {
      if (_extensionEvents.length == 64) {
        _extensionEvents.removeAt(0);
      }
      _extensionEvents.add(message);
    } else {
      _events.add(message);
    }
  }

  Future<void> _acquirePermit(String id, NaiAgentCancellation token) async {
    try {
      final release = await ModelRequestGates.shared
          .forProvider(_providerId)
          .acquire(
            limit: _requestLimit,
            cancellation: token.whenCancelled,
            isCancelled: () => token.isCancelled,
          );
      if (_closed || token.isCancelled) {
        release();
        return;
      }
      _releases[id] = release;
      String? accessToken;
      if (_requestAccessToken case final request?) {
        try {
          accessToken = await request();
        } catch (_) {
          _releases.remove(id)?.call();
          if (!_closed && !token.isCancelled) {
            _send({
              'type': 'permit_result',
              'requestId': id,
              'error': 'chatgpt',
            });
          }
          return;
        }
        if (_closed || token.isCancelled) {
          _releases.remove(id)?.call();
          return;
        }
      }
      _send({
        'type': 'permit_result',
        'requestId': id,
        if (accessToken != null) 'accessToken': accessToken,
      });
      _events.add({'type': 'request_started', 'requestId': id});
    } on ModelRequestCancelled {
      if (!_closed) {
        _send({'type': 'permit_result', 'requestId': id, 'error': true});
      }
    } finally {
      _permits.remove(id);
    }
  }

  Future<void> _execute(
    String id,
    Map<String, dynamic> message,
    NaiAgentCancellation token,
  ) async {
    Map<String, dynamic> reply;
    try {
      final result = await executeTool(
        message['name'] as String,
        (message['params'] as Map).cast<String, dynamic>(),
        token,
      );
      token.check();
      reply = {'result': result};
    } on NaiAgentToolError catch (error) {
      reply = {'error': error.toJson()};
    } catch (_) {
      reply = {
        'error': const NaiAgentToolError(
          'studio_tool_failed',
          'Studio tool failed; no raw diagnostics were sent',
        ).toJson(),
      };
    } finally {
      _tools.remove(id);
    }
    if (!_closed && !token.isCancelled) {
      _send({'type': 'tool_result', 'toolCallId': id, ...reply});
    }
  }

  void _lost([String reason = 'unknown']) {
    if (_closed) return;
    _closed = true;
    if (kDebugMode) {
      AppLogger.w('Pi host transport lost: $reason', 'Agent');
    }
    for (final token in _tools.values) {
      token.cancel();
    }
    _tools.clear();
    for (final token in _permits.values) {
      token.cancel();
    }
    _permits.clear();
    for (final release in _releases.values) {
      release();
    }
    _releases.clear();
    for (final completion in _requests.values) {
      completion.completeError(
        const NaiAgentToolError('host_closed', 'Pi host closed'),
      );
    }
    _requests.clear();
    if (!_closing) {
      _events.add({
        'type': 'closed',
        'workspaceId': workspaceId,
        'sessionId': _sessionId,
      });
    }
    unawaited(_process.kill()); // Desktop kills its child; embedded detaches.
  }

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    for (final token in _tools.values) {
      token.cancel();
    }
    for (final token in _permits.values) {
      token.cancel();
    }
    if (!_closed && _sessionId != null) {
      try {
        await _request({
          'type': 'shutdown',
        }).timeout(const Duration(seconds: 5));
      } catch (_) {
        await _process.kill();
      }
    } else {
      await _process.kill();
    }
    // The embedded runtime stays alive for the next session; only the child
    // process has a meaningful exit code.
    if (!_process.persistent) {
      try {
        await _process.exitCode.timeout(const Duration(seconds: 5));
      } catch (_) {
        await _process.kill();
      }
    }
    _lost('closed');
    await _stdout.cancel();
    await _stderr.cancel();
    await _events.close();
  }
}
