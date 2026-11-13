import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/nai_agent/pi_host_process.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'embedded clients route replies and close only their own worker',
    () async {
      const channel = MethodChannel('com.nailauncher/node_runtime');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final writes = <Map<String, dynamic>>[];
      var starts = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'start') {
          starts++;
          return true;
        }
        if (call.method == 'writeStdin') {
          writes.add(
            Map<String, dynamic>.from(
              jsonDecode((call.arguments as Map)['data'] as String) as Map,
            ),
          );
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      Future<void> event(String transport, Map<String, dynamic> fields) async {
        await messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('event', {
              'type': 'stdout',
              'payload': jsonEncode({'transportId': transport, ...fields}),
            }),
          ),
          (_) {},
        );
        await Future<void>.delayed(Duration.zero);
      }

      final clients = await Future.wait([
        EmbeddedNodePiHostProcess.start(
          hostScript: 'android-host.mjs',
          workingDirectory: 'fixture',
        ),
        EmbeddedNodePiHostProcess.start(
          hostScript: 'android-host.mjs',
          workingDirectory: 'fixture',
        ),
      ]);
      addTearDown(() async {
        for (final client in clients) {
          await client.kill();
        }
      });
      final first = <String>[], second = <String>[], errors = <Object>[];
      final a = clients[0].stdout
          .transform(utf8.decoder)
          .listen(first.add, onError: errors.add);
      final b = clients[1].stdout
          .transform(utf8.decoder)
          .listen(second.add, onError: errors.add);
      addTearDown(() async {
        await a.cancel();
        await b.cancel();
      });
      clients[0].write('{"type":"init"}\n');
      clients[1].write('{"type":"init"}\n');
      await Future<void>.delayed(Duration.zero);
      expect(starts, 1);
      final idA = writes[0]['transportId'] as String,
          idB = writes[1]['transportId'] as String;
      expect(idA, isNot(idB));
      await event(idA, {'type': 'ready', 'value': '中文'});
      expect(first.single, contains('中文'));
      expect(first.single, isNot(contains('transportId')));
      expect(second, isEmpty);
      await clients[0].kill();
      expect(writes.last, {'transportId': idA, 'type': 'transport_close'});
      await event(idB, {'type': 'response'});
      expect(second.single, contains('response'));
      await event(idB, {'type': 'transport_closed'});
      expect(errors, hasLength(1));
    },
  );
}
