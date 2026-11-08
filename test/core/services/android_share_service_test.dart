import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/services/android_share_service.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const platformChannel = MethodChannel('com.nailauncher/platform');
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('android_share_service_');
    AndroidShareService.debugForceSupported = true;
  });

  tearDown(() async {
    AndroidShareService.debugForceSupported = null;
    messenger.setMockMethodCallHandler(platformChannel, null);
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('desktop stays inert: no channel call, share returns false', () async {
    AndroidShareService.debugForceSupported = false;
    var called = false;
    messenger.setMockMethodCallHandler(platformChannel, (call) async {
      called = true;
      return true;
    });

    expect(await AndroidShareService.shareFile('/tmp/missing.png'), isFalse);
    expect(
      await AndroidShareService.shareBytes(Uint8List.fromList([1])),
      isFalse,
    );
    expect(called, isFalse);
  });

  test('shareFile forwards path + mime type to the platform channel', () async {
    final file = File(p.join(tempDir.path, 'sample.png'));
    await file.writeAsBytes([1, 2, 3]);

    MethodCall? received;
    messenger.setMockMethodCallHandler(platformChannel, (call) async {
      received = call;
      return true;
    });

    expect(await AndroidShareService.shareFile(file.path), isTrue);
    expect(received?.method, 'shareFile');
    expect(received?.arguments, {'path': file.path, 'mimeType': 'image/png'});
  });

  test(
    'shareFile reports missing files without touching the channel',
    () async {
      var called = false;
      messenger.setMockMethodCallHandler(platformChannel, (call) async {
        called = true;
        return true;
      });

      expect(
        await AndroidShareService.shareFile(p.join(tempDir.path, 'nope.png')),
        isFalse,
      );
      expect(called, isFalse);
    },
  );

  test('shareFile survives a missing platform plugin', () async {
    final file = File(p.join(tempDir.path, 'no_plugin.jpg'));
    await file.writeAsBytes([1]);
    messenger.setMockMethodCallHandler(platformChannel, (call) async {
      throw MissingPluginException();
    });

    expect(await AndroidShareService.shareFile(file.path), isFalse);
  });

  test('shareBytes writes a cache file and shares it by path', () async {
    final cacheRoot = Directory(p.join(tempDir.path, 'cache'));
    await cacheRoot.create(recursive: true);
    messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getTemporaryDirectory') return cacheRoot.path;
      throw MissingPluginException();
    });

    MethodCall? received;
    messenger.setMockMethodCallHandler(platformChannel, (call) async {
      received = call;
      return true;
    });

    final bytes = Uint8List.fromList([137, 80, 78, 71]);
    expect(
      await AndroidShareService.shareBytes(
        bytes,
        fileName: 'unsaved generation',
      ),
      isTrue,
    );

    final arguments = received!.arguments! as Map<Object?, Object?>;
    final sharedPath = arguments['path']! as String;
    expect(sharedPath, contains('outgoing_shares'));
    expect(p.basename(sharedPath), endsWith('_unsaved generation.png'));
    expect(await File(sharedPath).readAsBytes(), bytes);
    expect(arguments['mimeType'], 'image/png');
  });

  test('shareTempFileName keeps a timestamp prefix and safe extension', () {
    final name = AndroidShareService.shareTempFileName(
      r'C:\images\..\shot.PNG',
      now: DateTime.fromMillisecondsSinceEpoch(42),
    );
    expect(name, '42_shot.PNG');
    expect(AndroidShareService.shareTempFileName('a/b/c'), endsWith('_c.png'));
    expect(AndroidShareService.safeShareFileName('  '), 'image.png');
    expect(
      AndroidShareService.safeShareFileName('bad:name?.webp'),
      'bad_name_.webp',
    );
  });
}
