import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/services/android_share_intake.dart';
import 'package:nai_launcher/core/utils/file_explorer_utils.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'com.nailauncher/platform';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final intake = AndroidShareIntake.instance;
  late Directory tempDir;
  late List<MethodCall> calls;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('android_share_intake_');
    calls = <MethodCall>[];
    AndroidShareIntake.debugForceSupported = true;
  });

  tearDown(() async {
    await intake.detach();
    AndroidShareIntake.debugForceSupported = null;
    messenger.setMockMethodCallHandler(PlatformFileChannel.channel, null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  File createSharedFile(String name) {
    final file = File(p.join(tempDir.path, name));
    file.writeAsBytesSync([1, 2, 3]);
    return file;
  }

  /// Mocks `getSharedImage`; each call returns the next pending path (then null).
  void mockPendingImages(List<String?> pending) {
    var index = 0;
    messenger.setMockMethodCallHandler(PlatformFileChannel.channel, (
      call,
    ) async {
      calls.add(call);
      if (call.method != AndroidShareIntake.takeSharedImageMethod) {
        return null;
      }
      if (index >= pending.length) return null;
      return pending[index++];
    });
  }

  Future<void> waitFor(bool Function() condition) async {
    for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test(
    'desktop stays inert: attach/setHandler never touch the channel',
    () async {
      AndroidShareIntake.debugForceSupported = false;
      messenger.setMockMethodCallHandler(PlatformFileChannel.channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });

      await intake.attach();
      intake.setHandler((path) async {});
      await intake.poll();

      expect(calls, isEmpty);
    },
  );

  test('startup poll consumes a pending shared image exactly once', () async {
    final shared = createSharedFile('shared.png');
    mockPendingImages([shared.path]);

    final delivered = <String>[];
    await intake.attach();
    intake.setHandler((path) async => delivered.add(path));
    await waitFor(() => delivered.isNotEmpty);

    expect(delivered, [shared.path]);
    await intake.poll();
    await intake.poll();
    expect(delivered, [shared.path]);
  });

  test('foreground shareImageReceived signal pulls the next image', () async {
    final first = createSharedFile('first.png');
    final second = createSharedFile('second.jpg');
    mockPendingImages([first.path, second.path]);

    final delivered = <String>[];
    await intake.attach();
    intake.setHandler((path) async => delivered.add(path));
    await waitFor(() => delivered.isNotEmpty);
    expect(delivered, [first.path]);

    messenger.handlePlatformMessage(
      channelName,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall(AndroidShareIntake.shareReceivedSignal),
      ),
      (_) {},
    );
    await waitFor(() => delivered.length == 2);

    expect(delivered, [first.path, second.path]);
  });

  test('missing plugin / platform errors never throw', () async {
    messenger.setMockMethodCallHandler(PlatformFileChannel.channel, (call) {
      throw MissingPluginException();
    });
    await intake.attach();
    intake.setHandler((path) async {});
    await expectLater(intake.poll(), completes);

    messenger.setMockMethodCallHandler(PlatformFileChannel.channel, (call) {
      throw PlatformException(code: 'boom');
    });
    await expectLater(intake.poll(), completes);
  });

  test('detach stops delivery', () async {
    final shared = createSharedFile('after_detach.png');
    mockPendingImages([shared.path]);
    final delivered = <String>[];
    await intake.attach();
    intake.setHandler((path) async => delivered.add(path));
    await intake.detach();
    await intake.poll();
    expect(delivered, isEmpty);
  });

  test('channel method names match MainActivity.kt', () {
    expect(AndroidShareIntake.takeSharedImageMethod, 'getSharedImage');
    expect(AndroidShareIntake.shareReceivedSignal, 'shareImageReceived');
  });
}
