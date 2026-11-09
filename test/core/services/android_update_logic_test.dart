import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/services/android_update_logic.dart';
import 'package:nai_launcher/data/models/version/release_asset_info.dart';

ReleaseAssetInfo _asset(
  String fileName, {
  String downloadUrl =
      'https://github.com/z15087716457-stack/'
      'W.O.F_NAI_Launcher/releases/download/v2.3.2/app.apk',
  int? size,
  String? sha256,
}) {
  return ReleaseAssetInfo(
    type: ReleaseAssetType.unknown,
    platform: 'unknown',
    fileName: fileName,
    downloadUrl: downloadUrl,
    size: size,
    sha256: sha256,
  );
}

void main() {
  group('AndroidUpdateLogic.isNewerVersion', () {
    test('treats a newer tag as an update', () {
      expect(AndroidUpdateLogic.isNewerVersion('v2.3.2', '2.3.1'), isTrue);
      expect(AndroidUpdateLogic.isNewerVersion('2.10.0', '2.9.9'), isTrue);
    });

    test('ignores same or older versions', () {
      expect(AndroidUpdateLogic.isNewerVersion('2.3.1', '2.3.1'), isFalse);
      expect(AndroidUpdateLogic.isNewerVersion('2.3.0', '2.3.1'), isFalse);
    });

    test('returns false for unparsable versions', () {
      expect(AndroidUpdateLogic.isNewerVersion('latest', '2.3.1'), isFalse);
    });
  });

  group('AndroidUpdateLogic.selectApkAsset', () {
    const arm64 = 'app-arm64-v8a-release.apk';
    const arm32 = 'app-armeabi-v7a-release.apk';
    const x64 = 'app-x86_64-release.apk';
    const universal = 'app-universal-release.apk';

    test('returns null when the release has no APK asset', () {
      final assets = [
        _asset('WOF-Setup-2.3.2.exe'),
        _asset('WOF-macos-2.3.2-portable.zip'),
      ];
      expect(
        AndroidUpdateLogic.selectApkAsset(assets, supportedAbis: const []),
        isNull,
      );
    });

    test('ignores APK assets without a download URL', () {
      final assets = [_asset(arm64, downloadUrl: '')];
      expect(
        AndroidUpdateLogic.selectApkAsset(
          assets,
          supportedAbis: const ['arm64-v8a'],
        ),
        isNull,
      );
    });

    test('picks the ABI the device supports first', () {
      final assets = [_asset(arm32), _asset(x64), _asset(arm64)];

      expect(
        AndroidUpdateLogic.selectApkAsset(
          assets,
          supportedAbis: const ['arm64-v8a', 'armeabi-v7a'],
        )?.fileName,
        arm64,
      );
      expect(
        AndroidUpdateLogic.selectApkAsset(
          assets,
          supportedAbis: const ['x86_64', 'x86'],
        )?.fileName,
        x64,
      );
      expect(
        AndroidUpdateLogic.selectApkAsset(
          assets,
          supportedAbis: const ['armeabi-v7a'],
        )?.fileName,
        arm32,
      );
    });

    test('uses a universal APK when no ABI matches', () {
      final assets = [_asset(arm64), _asset(universal)];
      expect(
        AndroidUpdateLogic.selectApkAsset(
          assets,
          supportedAbis: const ['mips'],
        )?.fileName,
        universal,
      );
    });

    test('prefers release APKs over debug APKs of the same ABI', () {
      final assets = [_asset('app-arm64-v8a-debug.apk'), _asset(arm64)];
      expect(
        AndroidUpdateLogic.selectApkAsset(
          assets,
          supportedAbis: const ['arm64-v8a'],
        )?.fileName,
        arm64,
      );
    });

    test('is deterministic when several APKs share the best match', () {
      final assets = [
        _asset('app-universal-z.apk'),
        _asset('app-universal-a.apk'),
      ];
      expect(
        AndroidUpdateLogic.selectApkAsset(
          assets,
          supportedAbis: const ['arm64-v8a'],
        )?.fileName,
        'app-universal-a.apk',
      );
    });
  });

  group('AndroidUpdateLogic.resolveDownloadUrl', () {
    test('keeps an https download URL untouched', () {
      final asset = _asset('app.apk');
      expect(AndroidUpdateLogic.resolveDownloadUrl(asset), asset.downloadUrl);
    });

    test(
      'falls back to the release download URL when the asset URL is empty',
      () {
        final asset = _asset('app-arm64-v8a-release.apk', downloadUrl: '');
        final url = AndroidUpdateLogic.resolveDownloadUrl(
          asset,
          htmlUrl:
              'https://github.com/z15087716457-stack/'
              'W.O.F_NAI_Launcher/releases/tag/v2.3.2',
        );
        expect(
          url,
          'https://github.com/z15087716457-stack/W.O.F_NAI_Launcher/'
          'releases/download/v2.3.2/app-arm64-v8a-release.apk',
        );
      },
    );

    test('rejects assets without any usable https URL', () {
      final asset = _asset('app.apk', downloadUrl: 'ftp://example.com/app.apk');
      expect(
        () => AndroidUpdateLogic.resolveDownloadUrl(asset),
        throwsFormatException,
      );
      expect(
        () => AndroidUpdateLogic.resolveDownloadUrl(
          asset,
          htmlUrl: 'https://gitlab.com/owner/repo/releases/tag/v1',
        ),
        throwsFormatException,
      );
    });
  });

  test('GitHub 解析出的 APK 资产能被直接选走（识别与选包对齐）', () {
    // 用真实解析路径构造资产：确认新增的 androidApk 类型不会让
    // selectApkAsset 漏掉安装包。
    final assets = [
      ReleaseAssetInfo.fromGitHubAsset({
        'name': 'WOF_NAI_Studio_Windows_2.4.0_Setup.exe',
        'browser_download_url': 'https://example.com/setup.exe',
      }),
      ReleaseAssetInfo.fromGitHubAsset({
        'name': 'app-arm64-v8a-release.apk',
        'browser_download_url': 'https://example.com/app-arm64-v8a-release.apk',
      }),
    ];

    final picked = AndroidUpdateLogic.selectApkAsset(
      assets,
      supportedAbis: const ['arm64-v8a', 'armeabi-v7a'],
    );

    expect(picked, isNotNull);
    expect(picked!.fileName, 'app-arm64-v8a-release.apk');
    expect(picked.type, ReleaseAssetType.androidApk);
    expect(picked.supportsInAppInstall, isTrue);
  });
}
