import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/services/android_update_service.dart';
import 'package:nai_launcher/core/services/update_installer_service.dart';
import 'package:nai_launcher/data/models/version/release_asset_info.dart';
import 'package:nai_launcher/data/models/version/version_info.dart';

ReleaseAssetInfo _apk(String fileName) {
  return ReleaseAssetInfo(
    type: ReleaseAssetType.unknown,
    platform: 'unknown',
    fileName: fileName,
    downloadUrl:
        'https://github.com/owner/repo/releases/download/'
        'v2.3.2/$fileName',
    size: 1024,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(AndroidApkInstallChannel.channelName);

  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall call) handler;

  setUp(() {
    calls = [];
    handler = (call) async => null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('AndroidApkInstallChannel', () {
    test('reads the device ABI list from the platform channel', () async {
      handler = (call) async => call.method == 'supportedAbis'
          ? <String>['arm64-v8a', 'armeabi-v7a']
          : null;

      await expectLater(
        const AndroidApkInstallChannel().supportedAbis(),
        completion(<String>['arm64-v8a', 'armeabi-v7a']),
      );
    });

    test('returns an empty ABI list when the channel is unavailable', () async {
      handler = (call) async => throw MissingPluginException(
        'No implementation found for ${call.method}',
      );

      expect(await const AndroidApkInstallChannel().supportedAbis(), isEmpty);
    });

    test('launches the system installer with the APK path', () async {
      handler = (call) async => <String, Object?>{'status': 'launched'};

      final status = await const AndroidApkInstallChannel().installApk(
        '/data/user/0/com.wof.nai_launcher/cache/nai_launcher_updates/app.apk',
      );

      expect(status, AndroidApkInstallStatus.launched);
      expect(calls.single.method, 'installApk');
      expect(calls.single.arguments, <String, Object?>{
        'path':
            '/data/user/0/com.wof.nai_launcher/cache/nai_launcher_updates/'
            'app.apk',
      });
    });

    test('reports the unknown-sources permission prompt', () async {
      handler = (call) async => <String, Object?>{
        'status': 'permission_required',
      };

      expect(
        await const AndroidApkInstallChannel().installApk('/cache/app.apk'),
        AndroidApkInstallStatus.permissionRequired,
      );
    });

    test('maps platform failures to unavailable', () async {
      handler = (call) async => throw PlatformException(
        code: 'install_failed',
        message: 'Activity not found',
      );

      expect(
        await const AndroidApkInstallChannel().installApk('/cache/app.apk'),
        AndroidApkInstallStatus.unavailable,
      );
    });

    test('reads and opens the unknown-sources settings', () async {
      handler = (call) async => switch (call.method) {
        'canRequestPackageInstalls' => false,
        'openUnknownSourcesSettings' => true,
        _ => null,
      };

      const wrapper = AndroidApkInstallChannel();
      expect(await wrapper.canRequestPackageInstalls(), isFalse);
      await wrapper.openUnknownSourcesSettings();
      expect(calls.map((call) => call.method), [
        'canRequestPackageInstalls',
        'openUnknownSourcesSettings',
      ]);
    });
  });

  group('AndroidUpdateService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nai_android_update_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('selects the APK matching the device ABI', () async {
      handler = (call) async =>
          call.method == 'supportedAbis' ? <String>['x86_64'] : null;
      final service = AndroidUpdateService(
        dio: Dio(),
        cacheDirectory: () async => tempDir,
      );
      final info = VersionInfo(
        version: '2.3.2',
        assets: [
          _apk('app-arm64-v8a-release.apk'),
          _apk('app-x86_64-release.apk'),
        ],
      );

      final asset = await service.findApkAsset(info);
      expect(asset?.fileName, 'app-x86_64-release.apk');
    });

    test('returns no APK asset when the release has none', () async {
      handler = (call) async => <String>[];
      final service = AndroidUpdateService(
        dio: Dio(),
        cacheDirectory: () async => tempDir,
      );

      await expectLater(
        service.findApkAsset(
          VersionInfo(version: '2.3.2', assets: [_apk('WOF-Setup-2.3.2.exe')]),
        ),
        completion(isNull),
      );
    });

    test('launches the installer for a downloaded APK', () async {
      handler = (call) async => <String, Object?>{'status': 'launched'};
      final file = File('${tempDir.path}/app.apk');
      await file.writeAsBytes([1, 2, 3]);
      final service = AndroidUpdateService(
        dio: Dio(),
        cacheDirectory: () async => tempDir,
      );

      final status = await service.install(
        DownloadedUpdate(file: file, asset: _apk('app.apk'), version: '2.3.2'),
      );

      expect(status, AndroidApkInstallStatus.launched);
      expect(calls.single.arguments, {'path': file.path});
    });

    test('fails before the channel when the APK disappeared', () async {
      final service = AndroidUpdateService(
        dio: Dio(),
        cacheDirectory: () async => tempDir,
      );
      final missing = File('${tempDir.path}/missing.apk');

      await expectLater(
        service.install(
          DownloadedUpdate(
            file: missing,
            asset: _apk('missing.apk'),
            version: '2.3.2',
          ),
        ),
        throwsA(isA<UpdateInstallException>()),
      );
      expect(calls, isEmpty);
    });
  });
}
