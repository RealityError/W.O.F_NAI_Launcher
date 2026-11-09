import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:nai_launcher/core/utils/localization_extension.dart';
import 'package:nai_launcher/core/services/app_installation_service.dart';
import 'package:nai_launcher/core/services/update_check_service.dart';
import 'package:nai_launcher/data/datasources/remote/github_api_service.dart';
import 'package:nai_launcher/data/models/version/version_info.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _FakeGitHubApiService extends GitHubApiService {
  _FakeGitHubApiService(this.handler) : super(dio: Dio());

  final Future<VersionInfo> Function(String currentVersion) handler;

  /// 最近一次检查时实际使用的更新源，用于锁定桌面/Android 的仓库选择。
  String? lastOwner;
  String? lastRepo;
  String? lastPlatform;

  @override
  Future<VersionInfo> fetchLatestRelease({
    required String owner,
    required String repo,
    required String currentVersion,
    String platform = 'windows',
    bool includePrerelease = false,
  }) {
    lastOwner = owner;
    lastRepo = repo;
    lastPlatform = platform;
    return handler(currentVersion);
  }
}

class _FakeInstallationService extends AppInstallationService {
  @override
  String getReleaseAssetPreference() => 'windows-portable';
}

class _FakeUpdateStorage implements UpdateCheckStorage {
  DateTime? success;
  DateTime? attempt;
  String? skipped;
  String? known;
  DateTime? remindAfter;
  bool prerelease = false;

  @override
  DateTime? getLastUpdateCheckTime() => success;

  @override
  Future<void> setLastUpdateCheckTime(DateTime? time) async => success = time;

  @override
  DateTime? getLastUpdateCheckAttemptTime() => attempt;

  @override
  Future<void> setLastUpdateCheckAttemptTime(DateTime? time) async =>
      attempt = time;

  @override
  String? getSkippedUpdateVersion() => skipped;

  @override
  Future<void> setSkippedUpdateVersion(String? version) async =>
      skipped = version;

  @override
  String? getLastKnownUpdateVersion() => known;

  @override
  Future<void> setLastKnownUpdateVersion(String? version) async =>
      known = version;

  @override
  DateTime? getUpdateRemindAfter() => remindAfter;

  @override
  Future<void> setUpdateRemindAfter(DateTime? time) async => remindAfter = time;

  @override
  bool getIncludePrereleaseUpdates() => prerelease;

  @override
  Future<void> setIncludePrereleaseUpdates(bool value) async =>
      prerelease = value;
}

void main() {
  late DateTime now;
  late _FakeUpdateStorage storage;

  PackageInfo packageInfo() => PackageInfo(
    appName: 'NAI Launcher',
    packageName: 'nai_launcher',
    version: '1.0.0',
    buildNumber: '1',
  );

  UpdateCheckService buildService(
    Future<VersionInfo> Function(String currentVersion) handler,
  ) {
    return UpdateCheckService(
      gitHubApiService: _FakeGitHubApiService(handler),
      packageInfo: packageInfo(),
      installationService: _FakeInstallationService(),
      checkStorage: storage,
      now: () => now,
    );
  }

  setUp(() {
    now = DateTime.utc(2026, 3, 1, 8);
    storage = _FakeUpdateStorage();
  });

  for (final locale in [
    const Locale('zh'),
    const Locale('zh', 'TW'),
    const Locale('en'),
    const Locale('ja'),
    const Locale('ko'),
  ]) {
    test(
      'check failure has localized HTTP reason and retry time in $locale',
      () async {
        setCurrentL10nLocale(locale);
        addTearDown(() => setCurrentL10nLocale(const Locale('zh')));
        final retryAt = DateTime.utc(2030);
        final service = buildService(
          (_) async => throw GitHubApiException(
            'API rate limit exceeded',
            statusCode: 403,
            rateLimited: true,
            retryAt: retryAt,
            originalError: 'Dio diagnostic fixture',
          ),
        );
        await expectLater(
          service.checkForUpdates(),
          throwsA(
            isA<UpdateCheckException>()
                .having((e) => e.message, 'HTTP status', contains('HTTP 403'))
                .having(
                  (e) => e.message,
                  'server reason',
                  contains('API rate limit exceeded'),
                )
                .having(
                  (e) => e.message,
                  'rate limit',
                  contains(currentL10n.update_errorRateLimited),
                )
                .having(
                  (e) => e.message,
                  'retry time',
                  contains(
                    currentL10n.update_retryAt(
                      DateFormat(
                        'yyyy-MM-dd HH:mm:ss',
                      ).format(retryAt.toLocal()),
                    ),
                  ),
                )
                .having(
                  (e) => e.message,
                  'no raw exception in UI',
                  isNot(contains('Dio diagnostic fixture')),
                )
                .having(
                  (e) => e.toString(),
                  'diagnostic retained',
                  contains('Dio diagnostic fixture'),
                ),
          ),
        );
        expect(storage.success, isNull);
      },
    );
  }

  test('403 without limit evidence is not called rate limiting', () async {
    final service = buildService(
      (_) async =>
          throw GitHubApiException('Access denied by policy', statusCode: 403),
    );
    await expectLater(
      service.checkForUpdates(),
      throwsA(
        isA<UpdateCheckException>()
            .having(
              (e) => e.message,
              'reason',
              contains('Access denied by policy'),
            )
            .having(
              (e) => e.message,
              'not rate limited',
              isNot(contains(currentL10n.update_errorRateLimited)),
            )
            .having(
              (e) => e.message,
              'no invented retry time',
              isNot(contains('2030')),
            ),
      ),
    );
  });

  test(
    'failed checks record only an attempt and retry after 30 minutes',
    () async {
      final service = buildService(
        (_) async => throw GitHubApiException('offline'),
      );

      await expectLater(
        service.checkForUpdates(),
        throwsA(isA<UpdateCheckException>()),
      );

      expect(storage.attempt, now);
      expect(storage.success, isNull);
      expect(await service.shouldCheck(), isFalse);

      now = now.add(const Duration(minutes: 31));
      expect(await service.shouldCheck(), isTrue);
    },
  );

  test('successful checks use the regular 24 hour interval', () async {
    final service = buildService(
      (current) async => VersionInfo(
        version: current,
        currentVersion: current,
        isNewer: false,
      ),
    );

    expect(await service.checkForUpdates(), isNull);
    expect(storage.success, now);
    expect(await service.shouldCheck(), isFalse);

    now = now.add(const Duration(hours: 24));
    expect(await service.shouldCheck(), isTrue);
  });

  test('remind later suppresses a known update until the deadline', () async {
    final service = buildService(
      (current) async =>
          VersionInfo(version: '2.0.0', currentVersion: current, isNewer: true),
    );

    expect(await service.checkForUpdates(), isNotNull);
    await service.remindLater();
    expect(storage.known, '2.0.0');
    expect(await service.shouldCheck(), isFalse);

    now = now.add(const Duration(hours: 4));
    expect(await service.shouldCheck(), isTrue);
  });

  test('manual checks can reveal a previously skipped version', () async {
    final service = buildService(
      (current) async =>
          VersionInfo(version: '2.0.0', currentVersion: current, isNewer: true),
    );
    await service.skipVersion('2.0.0');

    expect(await service.checkForUpdates(), isNull);
    expect(service.hasKnownUpdate, isTrue);
    expect(await service.checkForUpdates(ignoreSkipped: true), isNotNull);
  });

  test('成功检查确认没有新版本后清除旧的已知更新', () async {
    storage.known = '2.0.0';
    final service = buildService(
      (current) async => VersionInfo(version: current),
    );
    expect(service.hasKnownUpdate, isTrue);
    expect(await service.checkForUpdates(), isNull);
    expect(service.hasKnownUpdate, isFalse);
  });

  test('桌面更新源保持上游仓库，Android 走 fork', () {
    expect(UpdateCheckService.ownerFor(android: false), 'z15087716457-stack');
    expect(UpdateCheckService.ownerFor(android: true), 'RealityError');
    // Android 端的 fork 已改名为 *_Android；桌面仍读上游同名仓库。
    expect(UpdateCheckService.repoFor(android: false), 'W.O.F_NAI_Launcher');
    expect(
      UpdateCheckService.repoFor(android: true),
      'W.O.F_NAI_Launcher_Android',
    );
    expect(
      UpdateCheckService.androidOwner,
      isNot(UpdateCheckService.defaultOwner),
    );
    expect(
      UpdateCheckService.androidRepo,
      isNot(UpdateCheckService.defaultRepo),
    );
  });

  test('宿主平台检查更新时带上正确的 owner、repo 与 platform', () async {
    final api = _FakeGitHubApiService(
      (current) async => VersionInfo(version: current, isNewer: false),
    );
    final service = UpdateCheckService(
      gitHubApiService: api,
      packageInfo: packageInfo(),
      installationService: _FakeInstallationService(),
      checkStorage: storage,
      now: () => now,
    );

    await service.checkForUpdates();

    expect(api.lastOwner, UpdateCheckService.owner);
    expect(api.lastOwner, UpdateCheckService.defaultOwner);
    // 桌面宿主必须查上游仓库，不能跟着 Android 改名走。
    expect(api.lastRepo, UpdateCheckService.defaultRepo);
    expect(api.lastRepo, 'W.O.F_NAI_Launcher');
    expect(api.lastPlatform, 'windows-portable');
  });
}
