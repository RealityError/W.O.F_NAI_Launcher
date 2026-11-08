import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/models/version/release_asset_info.dart';
import '../../data/models/version/version_info.dart';
import '../utils/localization_extension.dart';
import 'android_update_logic.dart';
import 'update_installer_service.dart';

/// 系统安装器的安装结果。
enum AndroidApkInstallStatus {
  /// 已拉起系统安装界面（用户还需要在系统界面里确认）。
  launched,

  /// 缺少「安装未知应用」授权，已跳到系统设置页。
  permissionRequired,

  /// 平台通道不可用或安装 Intent 启动失败。
  unavailable,
}

/// `com.nailauncher/apk_install` MethodChannel 的 Dart 封装。
///
/// 通道由 `ApkInstallHelper`（android/app/src/main/kotlin/...）在
/// MainActivity 初始化时注册；桌面平台没有实现，所有调用都会安全返回。
class AndroidApkInstallChannel {
  const AndroidApkInstallChannel({
    MethodChannel channel = const MethodChannel(channelName),
  }) : _channel = channel;

  /// 原生通道名（与 ApkInstallHelper.CHANNEL 保持一致）。
  static const String channelName = 'com.nailauncher/apk_install';

  final MethodChannel _channel;

  /// 当前设备支持的 ABI，例如 `[arm64-v8a, armeabi-v7a]`。
  Future<List<String>> supportedAbis() async {
    try {
      final values = await _channel.invokeListMethod<String>('supportedAbis');
      return values ?? const <String>[];
    } on PlatformException {
      return const <String>[];
    } on MissingPluginException {
      return const <String>[];
    }
  }

  /// 让系统安装器打开 [path] 指向的 APK。
  Future<AndroidApkInstallStatus> installApk(String path) async {
    try {
      final result = await _channel.invokeMethod<Object?>(
        'installApk',
        <String, Object?>{'path': path},
      );
      if (result is Map) {
        return switch (result['status']) {
          'launched' => AndroidApkInstallStatus.launched,
          'permission_required' => AndroidApkInstallStatus.permissionRequired,
          _ => AndroidApkInstallStatus.unavailable,
        };
      }
      return AndroidApkInstallStatus.unavailable;
    } on PlatformException {
      return AndroidApkInstallStatus.unavailable;
    } on MissingPluginException {
      return AndroidApkInstallStatus.unavailable;
    }
  }

  /// 是否已允许本应用安装未知来源的 APK（Android 8+）。
  Future<bool> canRequestPackageInstalls() async {
    try {
      return await _channel.invokeMethod<bool>('canRequestPackageInstalls') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 打开本应用的「安装未知应用」系统设置页。
  Future<void> openUnknownSourcesSettings() async {
    try {
      await _channel.invokeMethod<bool>('openUnknownSourcesSettings');
    } on PlatformException {
      // 部分 ROM 没有对应的设置页，交给安装器自身的提示兜底。
    } on MissingPluginException {
      // 桌面平台没有该通道。
    }
  }
}

typedef AndroidUpdateCacheDirectory = Future<Directory> Function();
typedef AndroidDownloadProgressCallback =
    void Function(UpdateDownloadProgress progress);

/// Android 应用内 APK 更新：选包、下载、校验并交给系统安装器。
///
/// 桌面更新链路（`UpdateInstallerService`）保持不变；本服务只在
/// `isAndroidPlatform` 为 true 的分支里使用。下载文件放在应用 cache
/// 目录的 `nai_launcher_updates/` 下，由 manifest 中已有的
/// `${applicationId}.fileprovider`（`cache-path`）暴露给系统安装器。
class AndroidUpdateService {
  AndroidUpdateService({
    required Dio dio,
    AndroidApkInstallChannel channel = const AndroidApkInstallChannel(),
    AndroidUpdateCacheDirectory cacheDirectory = getTemporaryDirectory,
  }) : _dio = dio,
       _channel = channel,
       _cacheDirectory = cacheDirectory;

  /// cache 下的更新包目录名。
  static const String cacheDirectoryName = 'nai_launcher_updates';

  static const Duration _connectTimeout = Duration(seconds: 15);
  static const Duration _receiveTimeout = Duration(seconds: 60);
  static const Duration _progressInterval = Duration(milliseconds: 250);

  final Dio _dio;
  final AndroidApkInstallChannel _channel;
  final AndroidUpdateCacheDirectory _cacheDirectory;

  /// 从 Release 资产里选择当前设备可用的 APK。
  Future<ReleaseAssetInfo?> findApkAsset(VersionInfo versionInfo) async {
    final abis = await _channel.supportedAbis();
    return AndroidUpdateLogic.selectApkAsset(
      versionInfo.assets,
      supportedAbis: abis,
    );
  }

  /// 下载并校验 APK，返回可安装的更新包。
  ///
  /// 已存在且校验通过的完整包会直接复用，避免重复下载。
  Future<DownloadedUpdate> download(
    VersionInfo versionInfo, {
    CancelToken? cancelToken,
    AndroidDownloadProgressCallback? onProgress,
  }) async {
    final asset = await findApkAsset(versionInfo);
    if (asset == null) {
      throw UpdateInstallException(
        currentL10n.update_errorNoInstallablePackage,
      );
    }
    final downloadUrl = AndroidUpdateLogic.resolveDownloadUrl(
      asset,
      htmlUrl: versionInfo.htmlUrl,
    );
    final directory = await _ensureUpdateDirectory();
    final target = File(p.join(directory.path, p.basename(asset.fileName)));

    if (await target.exists()) {
      if (await _isComplete(target, asset)) {
        final length = await target.length();
        onProgress?.call(
          UpdateDownloadProgress(
            receivedBytes: length,
            totalBytes: length,
            progress: 1,
            bytesPerSecond: 0,
          ),
        );
        return DownloadedUpdate(
          file: target,
          asset: asset,
          version: versionInfo.version,
        );
      }
      await _deleteQuietly(target);
    }

    final partial = File('${target.path}.part');
    await _deleteQuietly(partial);
    final expectedBytes = asset.size ?? 0;
    var receivedBytes = 0;
    var lastReportedBytes = 0;
    final stopwatch = Stopwatch()..start();
    var lastReportedAt = 0;

    try {
      final response = await _dio.get<ResponseBody>(
        downloadUrl,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: true,
          maxRedirects: 5,
          connectTimeout: _connectTimeout,
          receiveTimeout: _receiveTimeout,
          headers: const <String, Object>{'Accept-Encoding': 'identity'},
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      );
      final body = response.data;
      if (body == null) {
        throw UpdateInstallException(currentL10n.update_errorEmptyResponse);
      }

      final sink = partial.openWrite();
      try {
        await for (final chunk in body.stream) {
          _throwIfCancelled(cancelToken);
          sink.add(chunk);
          receivedBytes += chunk.length;
          final elapsed = stopwatch.elapsedMilliseconds;
          if (elapsed - lastReportedAt >= _progressInterval.inMilliseconds) {
            final window = elapsed - lastReportedAt;
            final bytesPerSecond = window <= 0
                ? 0
                : (receivedBytes - lastReportedBytes) * 1000 ~/ window;
            lastReportedBytes = receivedBytes;
            lastReportedAt = elapsed;
            onProgress?.call(
              UpdateDownloadProgress(
                receivedBytes: receivedBytes,
                totalBytes: expectedBytes,
                progress: expectedBytes > 0
                    ? (receivedBytes / expectedBytes).clamp(0.0, 0.99)
                    : 0,
                bytesPerSecond: bytesPerSecond,
              ),
            );
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
    } on UpdateDownloadCancelledException {
      await _deleteQuietly(partial);
      rethrow;
    } on DioException catch (error) {
      await _deleteQuietly(partial);
      if (CancelToken.isCancel(error)) {
        throw const UpdateDownloadCancelledException();
      }
      throw UpdateInstallException(
        currentL10n.update_errorDownloadFailed,
        originalError: error,
      );
    } on FileSystemException catch (error) {
      await _deleteQuietly(partial);
      throw UpdateInstallException(
        _diskErrorMessage(error),
        originalError: error,
      );
    }

    _throwIfCancelled(cancelToken);
    await _verifyAndMove(partial, target, asset);
    final length = await target.length();
    onProgress?.call(
      UpdateDownloadProgress(
        receivedBytes: length,
        totalBytes: length,
        progress: 1,
        bytesPerSecond: 0,
      ),
    );
    return DownloadedUpdate(
      file: target,
      asset: asset,
      version: versionInfo.version,
    );
  }

  /// 把已下载的 APK 交给系统安装器。
  Future<AndroidApkInstallStatus> install(DownloadedUpdate downloaded) async {
    final file = downloaded.file;
    if (!await file.exists()) {
      throw UpdateInstallException(currentL10n.update_errorPackageRemoved);
    }
    final status = await _channel.installApk(file.path);
    if (status == AndroidApkInstallStatus.unavailable) {
      throw UpdateInstallException(currentL10n.update_errorInstallFailed);
    }
    return status;
  }

  /// 是否已允许安装未知来源应用。
  Future<bool> canRequestPackageInstalls() =>
      _channel.canRequestPackageInstalls();

  /// 打开「安装未知应用」系统设置。
  Future<void> openUnknownSourcesSettings() =>
      _channel.openUnknownSourcesSettings();

  Future<Directory> _ensureUpdateDirectory() async {
    final cache = await _cacheDirectory();
    final directory = Directory(p.join(cache.path, cacheDirectoryName));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<bool> _isComplete(File file, ReleaseAssetInfo asset) async {
    final length = await file.length();
    if (length <= 0) return false;
    final expectedSize = asset.size ?? 0;
    if (expectedSize > 0 && length != expectedSize) return false;
    final expectedSha = asset.sha256?.trim();
    if (expectedSha == null || expectedSha.isEmpty) return true;
    final actual = await UpdateInstallerService.calculateSha256(file);
    return UpdateInstallerService.equalsSha256(actual, expectedSha);
  }

  Future<void> _verifyAndMove(
    File partial,
    File target,
    ReleaseAssetInfo asset,
  ) async {
    final length = await partial.length();
    if (length <= 0) {
      await _deleteQuietly(partial);
      throw UpdateInstallException(currentL10n.update_errorEmptyResponse);
    }
    final expectedSize = asset.size ?? 0;
    if (expectedSize > 0 && length != expectedSize) {
      await _deleteQuietly(partial);
      throw UpdateInstallException(currentL10n.update_errorSizeMismatch);
    }
    final expectedSha = asset.sha256?.trim();
    if (expectedSha != null && expectedSha.isNotEmpty) {
      final actual = await UpdateInstallerService.calculateSha256(partial);
      if (!UpdateInstallerService.equalsSha256(actual, expectedSha)) {
        await _deleteQuietly(partial);
        throw UpdateInstallException(currentL10n.update_errorChecksumMismatch);
      }
    }
    try {
      await partial.rename(target.path);
    } on FileSystemException catch (error) {
      await _deleteQuietly(partial);
      throw UpdateInstallException(
        _diskErrorMessage(error),
        originalError: error,
      );
    }
  }

  static void _throwIfCancelled(CancelToken? cancelToken) {
    if (cancelToken?.isCancelled ?? false) {
      throw const UpdateDownloadCancelledException();
    }
  }

  static String _diskErrorMessage(FileSystemException error) {
    final code = error.osError?.errorCode;
    if (code == 28 || code == 39 || code == 112) {
      return currentL10n.update_errorDiskFull;
    }
    return currentL10n.update_errorWriteFailed;
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // 清理失败不影响后续错误上报。
    }
  }
}

/// 默认的 Android 更新服务（仅 Android 分支使用）。
final androidUpdateServiceProvider = Provider<AndroidUpdateService>((ref) {
  return AndroidUpdateService(dio: Dio());
});
