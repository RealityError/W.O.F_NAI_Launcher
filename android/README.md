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

`local.properties`、Gradle wrapper 可执行文件、keystore 等已由本目录和根目录的 `.gitignore` 忽略；`GeneratedPluginRegistrant.java` 是生成文件，不要手改。

完整的 SDK 版本、能力判断、功能矩阵、CI 和排障见 [docs/android-port.md](../docs/android-port.md)。
