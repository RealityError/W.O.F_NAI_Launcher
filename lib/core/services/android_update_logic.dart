import '../../data/models/version/release_asset_info.dart';
import '../../data/models/version/version_info.dart';

/// Android 应用内 APK 更新的纯逻辑。
///
/// 这里只做版本比较、Release 资产选择和下载 URL 解析，不依赖 Flutter
/// 平台通道或文件系统，便于在 `flutter test` 中直接覆盖。
class AndroidUpdateLogic {
  /// GitHub Release 资产里常见的 Android ABI 标识，按选择优先级排列。
  static const List<String> knownAbis = <String>[
    'arm64-v8a',
    'armeabi-v7a',
    'x86_64',
    'x86',
  ];

  /// 判断 [latest] 是否比 [current] 新（复用桌面更新器的版本比较规则）。
  static bool isNewerVersion(String latest, String current) {
    return VersionInfoComparator.isNewer(latest, current);
  }

  /// 过滤出可安装的 APK 资产（扩展名为 `.apk` 且带下载地址）。
  static List<ReleaseAssetInfo> apkAssets(Iterable<ReleaseAssetInfo> assets) {
    return assets
        .where(
          (asset) =>
              asset.fileName.toLowerCase().endsWith('.apk') &&
              asset.downloadUrl.trim().isNotEmpty,
        )
        .toList(growable: false);
  }

  /// 从 Release 资产中选择适合当前设备 ABI 的 APK。
  ///
  /// 选择顺序：
  /// 1. 按 [supportedAbis] 的顺序匹配文件名中的 ABI；
  /// 2. 没有匹配时退回包含 `universal` 的通用包；
  /// 3. 仍没有时退回第一个可用的 APK（保证旧 release 也能升级）。
  ///
  /// 同一优先级下优先 release 包而不是 debug 包，再按文件名排序保证结果稳定。
  static ReleaseAssetInfo? selectApkAsset(
    Iterable<ReleaseAssetInfo> assets, {
    required List<String> supportedAbis,
  }) {
    final candidates = apkAssets(assets);
    if (candidates.isEmpty) return null;

    final normalizedAbis = supportedAbis
        .map((abi) => abi.trim().toLowerCase())
        .where((abi) => abi.isNotEmpty);
    for (final abi in normalizedAbis) {
      final matches = candidates
          .where((asset) => asset.fileName.toLowerCase().contains(abi))
          .toList(growable: false);
      if (matches.isNotEmpty) return _preferred(matches);
    }

    final universal = candidates
        .where((asset) => asset.fileName.toLowerCase().contains('universal'))
        .toList(growable: false);
    if (universal.isNotEmpty) return _preferred(universal);

    return _preferred(candidates);
  }

  /// 解析 APK 下载地址。
  ///
  /// GitHub 的 `browser_download_url` 正常情况下是 https 直链；若资产里
  /// 没带地址，则从 Release 页面地址拼出标准下载地址。两者都不可用时
  /// 抛 [FormatException]，由调用方转成用户可读的更新错误。
  static String resolveDownloadUrl(ReleaseAssetInfo asset, {String? htmlUrl}) {
    final direct = asset.downloadUrl.trim();
    if (_isHttpsUrl(direct)) return direct;

    final fallback = _releaseDownloadUrl(
      htmlUrl: htmlUrl,
      fileName: asset.fileName,
    );
    if (fallback != null) return fallback;

    throw const FormatException(
      'Android update asset has no usable https download URL',
    );
  }

  static bool _isHttpsUrl(String raw) {
    final uri = Uri.tryParse(raw);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  static String? _releaseDownloadUrl({
    required String? htmlUrl,
    required String fileName,
  }) {
    final releasePage = Uri.tryParse((htmlUrl ?? '').trim());
    if (releasePage == null ||
        releasePage.scheme != 'https' ||
        releasePage.host != 'github.com') {
      return null;
    }
    final segments = releasePage.pathSegments;
    if (segments.length < 5 ||
        segments[2] != 'releases' ||
        segments[3] != 'tag' ||
        fileName.trim().isEmpty) {
      return null;
    }
    final owner = segments[0];
    final repo = segments[1];
    final tag = segments[4];
    if (owner.isEmpty || repo.isEmpty || tag.isEmpty) return null;
    return Uri.https(
      'github.com',
      '/$owner/$repo/releases/download/$tag/${Uri.encodeComponent(fileName)}',
    ).toString();
  }

  static ReleaseAssetInfo _preferred(List<ReleaseAssetInfo> assets) {
    final releaseAssets = assets
        .where((asset) => !asset.fileName.toLowerCase().contains('debug'))
        .toList(growable: false);
    final pool = releaseAssets.isEmpty ? assets : releaseAssets;
    final sorted = [...pool]..sort((a, b) => a.fileName.compareTo(b.fileName));
    return sorted.first;
  }
}
