# android/ · W.O.F NAI Studio Android 工程

这是 Flutter Android 目标工程，由 Flutter 3.47.7 模板生成后按本仓库需要调整；桌面端（Windows/macOS）构建不受影响。**当前分支的 Android 支持仍在移植验证中，iOS 未移植。**

常用构建（在仓库根目录执行）：

```powershell
# MuMu 等 x86_64 模拟器（debug）
flutter build apk --debug --target-platform android-x64

# arm64 真机（debug）
flutter build apk --debug --target-platform android-arm64

# 发布构建按 ABI 拆分
flutter build apk --release --split-per-abi
```

产物在 `build/app/outputs/flutter-apk/`。仓库根目录的 `scripts/build_android.ps1` 会做 SDK/JDK/NDK、LFS 数据库和生成源码预检，并把 APK 复制到 `dist/android/`：

```powershell
./scripts/build_android.ps1 -Mode debug -TargetPlatform android-x64
```

关键配置：

- `applicationId` / `namespace`：`com.wof.nai_launcher`
- `minSdk` 24；`compileSdk` / `targetSdk` 由 Flutter SDK 常量决定（当前 36）
- `ndkVersion` 固定 `28.2.13676358`（`super_native_extensions` 的 Android 原生库需要 NDK）
- release 当前复用 debug 签名，**产物不能发布**；正式签名流程见 `docs/android-port.md` 第 7 节
- 新 clone 构建前先跑：`flutter pub get` → `dart run tool/generate.dart` → `flutter gen-l10n`

Android 侧能力与权限（2026-11-09 起）：

- 权限：`INTERNET` / `ACCESS_NETWORK_STATE`；`POST_NOTIFICATIONS`（后台生成通知，Android 13+ 首次开始时按需申请）；`REQUEST_INSTALL_PACKAGES`（应用内 APK 更新）；`FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_DATA_SYNC`（生成中 dataSync 前台服务）；`READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` 等图库导入权限。
- 平台通道：`com.nailauncher/platform`（打开/分享/另存相册/打开目录/系统代理/分享入站）、`com.nailauncher/generation`（后台生成前台服务）、`com.nailauncher/apk_install`（APK 安装器桥）、`com.nailauncher/notifications`（通知运行时权限与通知设置页跳转）。
- 应用内更新（G17）：检查 GitHub Release → 下载 APK 到 cache → 系统安装器。**Release 必须上传 Flutter split-per-abi 命名的 APK**（`app-arm64-v8a-release.apk` 等），否则会提示有新版本但无包可装；首次安装更新需要允许“安装未知应用”，未授权时会跳到本应用的系统设置页。
- 后台生成（G10/G18）：dataSync 前台服务 + 通知 channel `wof_generation`；Android 13+ 第一次开始生成时弹一次通知权限框，拒绝后不再重复申请、只给一次「去设置」引导，通知不可见但生成继续。
- 分享（G15/G16）：查看器「更多」/ 画廊长按菜单 / 生成结果长按菜单可分享到系统面板；其它应用 `ACTION_SEND image/*`（单张）进来会拷贝到 cache 并打开图生图。
- 应用内更新、分享、后台生成的真机手测清单见 [docs/android-port.md](../docs/android-port.md) 第 3.9 节。

`local.properties`、Gradle wrapper 可执行文件、keystore 等已由本目录和根目录的 `.gitignore` 忽略；`GeneratedPluginRegistrant.java` 是生成文件，不要手改。

完整的 SDK 版本、能力判断、功能矩阵、CI 和排障见 [docs/android-port.md](../docs/android-port.md)。
