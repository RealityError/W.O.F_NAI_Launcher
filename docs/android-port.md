# Android 移植说明

本分支（`feat/android-port`）为 W.O.F NAI Studio 增加 Android 目标。桌面端（Windows / macOS）仍是主平台，行为不变；Android 是新增的移植目标，**没有 iOS 移植**。

- 适用范围：`android/` 工程、平台能力判断、Android 构建脚本与 CI、以及在 Android 上降级/隐藏的桌面功能。
- 仓库约定、代码分层和测试要求见 [AGENTS.md](../AGENTS.md)；通用构建与 SDK 约定见 [DEVELOPMENT.md](../DEVELOPMENT.md)。
- 本文只描述可复现的构建步骤与当前实现边界；运行时行为以最新代码和真机/模拟器验证为准。

## 1. 这次新增了什么

### 1.1 `android/` 工程

`android/` 由 Flutter Android 模板生成，再按本仓库的需要调整：

| 项 | 值 | 说明 |
| --- | --- | --- |
| `applicationId` / `namespace` | `com.wof.nai_launcher` | 与桌面版品牌一致，独立于桌面安装包 |
| `minSdk` | 24 | `super_native_extensions` 要求 23；24 是当前可维护的下限 |
| `compileSdk` | `flutter.compileSdkVersion` | 由所用 Flutter SDK 决定，当前解析为 36 |
| `targetSdk` | `flutter.targetSdkVersion` | 同上，当前为 36 |
| `ndkVersion` | `28.2.13676358` | 与本地 Android SDK 对齐；避免 Gradle 另下 ~1 GB NDK |
| Gradle / AGP / Kotlin | 8.14（wrapper）/ 8.11.1 / 2.2.20 | Flutter 模板当前组合，兼容 Flutter 3.47.7 |
| Java / Kotlin target | 17 | AGP 8.11 与 Kotlin 2.2 的要求 |

其它 Android 资源：

- **应用身份**：`android:label="W.O.F NAI Studio"`，`MainActivity` 单 `singleTop` 启动、`taskAffinity=""`（不与其它任务混用）、`windowSoftInputMode="adjustResize"`。
- **启动画面**：`LaunchTheme` / `NormalTheme` 使用深色 `#121218` 背景和 `ic_launcher_foreground`，避免 Flutter UI 起来前的白闪；`values-night` 与日间一致维持深色。
- **图标**：mipmap 各密度 PNG + `mipmap-anydpi-v26` 自适应图标，前景/背景取自桌面版品牌图形。
- **Manifest 权限**：`INTERNET`、`ACCESS_NETWORK_STATE`（NovelAI、ComfyUI、第三方桥接均为网络服务）、`POST_NOTIFICATIONS`（已声明；当前完成提示只有应用内音效，没有系统通知栏实现）、`READ_EXTERNAL_STORAGE`（`maxSdkVersion=32`）、`READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO`（Android 13+ 导入图片/视频）。
- **`usesCleartextTraffic="true"`**：允许局域网内的 ComfyUI、自建服务或本地桥接使用 `http://`。这是便利性与安全性的取舍；不要用它访问不可信网络上的明文服务。
- **`largeHeap="true"`**：应用会解码大尺寸图片、加载多个数据库，Android 默认堆上限偏紧。
- **`super_native_extensions` DataProvider**：`authorities="${applicationId}.SuperClipboardDataProvider"`，供 `super_clipboard` / `super_drag_and_drop` 接收其它应用拖放/复制的图片与文件。
- **FileProvider**：`authorities="${applicationId}.fileprovider"` + `res/xml/file_provider_paths.xml`，把应用私有目录/缓存中的文件暴露成其它应用可读的 `content://` URI，用于 `ACTION_VIEW` 打开图片/视频、`ACTION_SEND` 分享。
- **`<queries>`**：`PROCESS_TEXT`（Flutter 文本处理插件）以及 `VIEW` 图片/视频/任意文件（打开外部查看器）。
- **打包**：`packaging.jniLibs.useLegacyPackaging = true`，`sqlite3_flutter_libs` 与 `super_native_extensions` 的 `.so` 需要从解压后的原生库目录加载。
- **签名占位**：`release` 构建当前复用 `debug` 签名配置（`android/app/build.gradle.kts` 中有 TODO）。**当前 release APK 不能对外发布**，正式签名见第 7 节。

### 1.2 依赖调整：`super_clipboard` / `super_drag_and_drop` 升到 ^0.9.1

0.9.x 修复了 Android 端的 cargokit Gradle 插件探测：旧版只匹配简单类名，新版 Flutter Gradle 插件使用全限定类名 `com.flutter.gradle.FlutterPlugin`，0.8.x 在 Android 上会跳过 Rust 原生库构建，导致 `SuperNativeExtensionsPlugin` 静态加载 `.so` 失败、应用启动崩溃。升级后两个插件在 Android 上正常注册。

其余桌面插件（`window_manager`、`tray_manager`、`screen_retriever`、`desktop_multi_window`、`media_kit_libs_windows_video` / `media_kit_libs_macos_video`、`path_provider_windows`、`url_launcher_windows`、`audioplayers_windows`、`flutter_inappwebview_windows` 等）没有 Android 实现，Flutter 在 Android 上不会注册它们，Dart 侧通过平台能力判断避免调用。

### 1.3 平台能力判断与配套文件

- `lib/core/utils/desktop_platform.dart` 新增 Android 平台与能力 getter（见第 2 节）。
- 桌面专属 service、设置页和入口按能力 getter 做运行时降级或隐藏，不在 Android 上引用桌面插件。
- 文件/图库/剪贴板的 Android 适配：`MainActivity.kt` 提供 `com.nailauncher/platform` MethodChannel（`openFile` / `shareFile` / `saveImageToMediaStore` / `openDirectory`），Dart 侧统一走 `PlatformFileChannel`。**手动保存**生成图时额外把副本镜像到系统相册 `Pictures/W.O.F NAI Studio`（MediaStore，Android 10+，原生侧按显示名去重）；**自动保存不会镜像**，避免每张图都进相册。保存失败只记日志，不影响图库保存。
- 构建工具：`scripts/build_android.ps1`（本地一键构建 + 预检）。
- CI：`.github/workflows/android-build.yml`（Linux 上构建 release APK 并上传）。
- 忽略规则：根 `.gitignore` 增加 `dist/android/`、`*.apk`、`*.aab`、`android/.kotlin/`（`android/.gitignore` 已覆盖 Gradle、`local.properties`、keystore 等，不重复）。
- `analysis_options.yaml`：`flutter pub get` 自动在 `analyzer.exclude` 中加入 `android/**`（Flutter 工具行为）；构建日志里的 "Upgrading gradle.properties" 也只是工具升级提示，都是正常输出，不需要手动改回。

## 2. 平台能力模型

原则：

1. `isSupportedDesktop` 语义保持不变，仍只表示 Windows / macOS。Android **不**进入这个判断，桌面代码路径不会因 Android 被改写。
2. 新代码判断能力时使用 `lib/core/utils/desktop_platform.dart` 中的 getter，不散落 `Platform.isWindows` / `Platform.isMacOS`（`usesMacOSConventions` 只用于键盘约定等 macOS 交互差异）。
3. Android 上不可用的能力必须"安静降级"：service 返回空值或 no-op，UI 隐藏入口；不能抛 `MissingPluginException`、`ProcessException`、`FileSystemException`。
4. 桌面行为只做运行时判断，不删除原实现。

当前 getter（名称以源码为准）：

| getter | 含义 | Windows | macOS | Android |
| --- | --- | --- | --- | --- |
| `isAndroidPlatform` | 当前是否 Android | ✗ | ✗ | ✓ |
| `isIOSPlatform` | 当前是否 iOS（未移植） | ✗ | ✗ | ✗ |
| `isMobilePlatform` | Android / iOS | ✗ | ✗ | ✓ |
| `supportsDesktopWindowChrome` | 原生窗口几何/标题栏（window_manager、screen_retriever） | ✓ | ✓ | ✗ |
| `supportsTray` | 系统托盘（tray_manager） | ✓ | ✓ | ✗ |
| `supportsMultiWindow` | 独立资源小窗（desktop_multi_window） | ✓ | ✓ | ✗ |
| `supportsExternalProcesses` | 启动外部进程：`.exe` 工具、Python/uv、Node、PowerShell、`nvidia-smi`、`open` 等 | ✓ | ✓ | ✗ |
| `supportsInAppUpdateInstall` | 应用内更新下载/安装 | ✓ | ✓ | ✗ |
| `supportsSystemFonts` | 列出/安装系统字体（原生 `system_fonts` 通道） | ✓ | ✓ | ✗ |
| `supportsSystemProxy` | 读取系统代理（注册表 / `scutil`） | ✓ | ✓ | ✗ |
| `supportsWindowsProxy` | Windows 注册表代理 | ✓ | ✗ | ✗ |
| `supportsGpuProbe` | GPU 探测（`nvidia-smi`） | ✓ | ✓ | ✗ |
| `supportsLocalRagRuntime` | 本地 RAG Python 运行时（uv + PyTorch） | ✓ | ✓ | ✗ |
| `supportsLocalUpscale` | 随包可执行文件的本地/高级放大 | ✓ | ✓ | ✗ |
| `supportsNaiAgentRuntime` | NAI Agent 的随包 Node 运行时 | ✓ | ✓ | ✗ |
| `supportsKritaBridge` | Krita 桥接服务与插件 | ✓ | ✓ | ✗ |
| `supportsNativeTitleBarRegion` | Windows runner 原生标题栏命中区 | ✓ | ✗ | ✗ |
| `supportsWindowBackdropMaterial` | Windows DWM 窗口材质 | ✓ | ✗ | ✗ |
| `supportsWindowManagerEvents` | window_manager 窗口事件（隐藏/最小化） | ✓ | ✗ | ✗ |

新增平台或功能时：先想清楚"这是能力还是平台"，能落到上面的 getter 就不要写死平台判断；桌面端已有行为用 Android 侧不进入的分支保留。

Android 上的取值口径：`isSupportedDesktop == false`、`isMobilePlatform == true`，上表所有 `supports*` 能力都是 `false`（Android 没有"部分支持"的桌面能力）；`supportsExternalProcesses` 的实现是 `!isMobilePlatform`，所以 Windows/macOS 之外、未移植的桌面/Linux 环境仍按原有行为返回 `true`，不改变既有桌面代码。设置页和功能入口统一用这些 getter 隐藏/降级（例如 Android 隐藏设置里的 Agent、语义检索、放大、网络页，隐藏 Krita 桥接、托盘/多窗口入口），不要在 UI 里散落平台判断。

## 3. 构建

### 3.1 前置条件

- **Flutter 3.47.7**（Dart 3.13.5），以 `tool/flutter-sdk.json` 为准，与 Windows / macOS 构建一致。**不要**使用机器上其它版本的 `flutter`：用 3.41.6 构建会报 `No named parameter with the name 'onReorderItem'`、`SizeTransition.alignment` 之类的 API 不存在错误，因为源码和 Android 模板都是按登记的 3.47.7 写的。
  - 推荐用仓库自带入口：`scripts/flutter_studio.ps1 -SdkRoot <flutter-3.47.7 目录> -FlutterArgs @(...)`；或设置环境变量 `WOF_FLUTTER_SDK_ROOT`。
  - 也可以直接给 `scripts/build_android.ps1` 传 `-FlutterPath`。
  - 如果只能依赖 PATH 上的 `flutter`，先运行 `flutter --version` 确认是 3.47.7 再构建。
- **JDK 17**（AGP 8.11 要求 17+，Gradle 8.14 支持到 24）。PATH 上的 `java` 可能是 11，不要用它；用 `flutter config --jdk-dir="<JDK 17 目录>"` 指定，`scripts/build_android.ps1` 会自动优先读这个配置。
- **Android SDK**：API 36 平台、build-tools 36、**NDK 28.2.13676358**、CMake 3.22.1（部分原生组件需要）。`ANDROID_HOME` / `ANDROID_SDK_ROOT` 指向 SDK，或让 Flutter 生成 `android/local.properties`（该文件不入库）。
- **已接受的 SDK 许可**：`sdkmanager --licenses`。未接受时 Gradle 无法自动补装平台、build-tools 或 NDK。
- **Git LFS**：`assets/databases/`（约 419 MB）由 LFS 管理，必须先 `git lfs pull`，否则打包进去的是指针文件。
- 足够磁盘空间：NDK、Gradle 缓存、Rust 构建产物和数百 MB 资产叠加，首次构建建议预留 10 GB 以上。

### 3.2 首次构建前

Generated Dart 源文件（`*.g.dart` / `*.freezed.dart`）被 `.gitignore` 忽略，新 clone 没有它们；只跑 `flutter build` 会直接编译失败。本机用 3.47.7 跑完这一步生成了 174 个文件，可作为参考。以下命令都用 3.47.7 的 SDK 执行（先把该 SDK 放到 PATH，或用 3.1 的 `flutter_studio.ps1` / `WOF_FLUTTER_SDK_ROOT`）：

```bash
git lfs install && git lfs pull
flutter pub get
dart run tool/generate.dart
flutter gen-l10n
```

之后依赖或生成输入（Riverpod / Freezed / JSON / Hive / 路由 / ARB）变化时，重复对应生成步骤。

### 3.3 构建命令

debug（MuMu 等 x86_64 模拟器必须用 `android-x64`）：

```powershell
flutter build apk --debug --target-platform android-x64
# 产物：build/app/outputs/flutter-apk/app-debug.apk
```

debug（多数真机，arm64）：

```powershell
flutter build apk --debug --target-platform android-arm64
```

release（单个 arm64 APK）：

```powershell
flutter build apk --release --target-platform android-arm64
```

release（按 ABI 拆分为三个 APK，CI 使用）：

```powershell
flutter build apk --release --split-per-abi
```

APK 输出目录固定为 `build/app/outputs/flutter-apk/`：

| 构建 | 产物 |
| --- | --- |
| `--debug`（单 ABI） | `app-debug.apk` |
| `--release`（单 ABI） | `app-release.apk` |
| `--release --split-per-abi` | `app-armeabi-v7a-release.apk`、`app-arm64-v8a-release.apk`、`app-x86_64-release.apk` |
| `--debug --split-per-abi` | 同上，后缀为 `-debug` |

`--split-per-abi` 只拆分原生库，**资源和数据库仍然每个 APK 各带一份**，所以拆包并不会显著减小总体积。

### 3.4 使用 `scripts/build_android.ps1`

脚本在 `flutter build apk` 外面加了本仓库需要的预检：定位登记的 Flutter SDK 并校验版本、定位 JDK 17、定位 Android SDK 和 NDK、检查 LFS 数据库和生成源码、把 APK 复制到输出目录并打印路径。它只调用 `flutter build apk`，不改仓库文件。

```powershell
# debug，arm64，产物默认放到 dist/android/
./scripts/build_android.ps1

# debug，x86_64 模拟器
./scripts/build_android.ps1 -TargetPlatform android-x64

# release，按 ABI 拆分
./scripts/build_android.ps1 -Mode release -SplitAbi

# 只做预检、打印将执行的命令，不构建
./scripts/build_android.ps1 -Mode debug -TargetPlatform android-x64 -DryRun

# 指定 SDK / JDK / 输出目录
./scripts/build_android.ps1 -FlutterPath D:\sdk\flutter-3.47.7 -JavaHome 'C:\Program Files\Eclipse Adoptium\jdk-17.0.18.8-hotspot' -OutputDir D:\apk
```

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `-Mode` | `debug` | `debug` / `release` |
| `-TargetPlatform` | `android-arm64` | `android-arm` / `android-arm64` / `android-x64` |
| `-SplitAbi` | 关闭 | 按 ABI 拆分；未显式传 `-TargetPlatform` 时构建全部三个 ABI |
| `-OutputDir` | `dist/android` | 相对仓库根目录或绝对路径；已被 `.gitignore` 忽略 |
| `-FlutterPath` | 自动检测 | Flutter SDK 目录或 `flutter.bat` |
| `-JavaHome` | 自动检测 | JDK 17–24 目录 |
| `-DryRun` | 关闭 | 只做预检 |

SDK 自动检测顺序：`-FlutterPath` → `WOF_FLUTTER_SDK_ROOT` → `FLUTTER_ROOT` → `tool/flutter-sdk.json` 登记的 SDK 目录 → PATH。检测到版本与 `tool/flutter-sdk.json` 不一致时脚本直接报错退出（这是有意的，避免用错误 SDK 得到难懂的编译错误）。JDK 顺序：`-JavaHome` → `flutter config jdk-dir` → `JAVA_HOME` → 常见安装目录（Adoptium / Java / Microsoft / Android Studio JBR），只接受 17–24。

### 3.5 CI：`.github/workflows/android-build.yml`

- 触发：手动 `workflow_dispatch`；`main` / `feat/android-port` 的 push，以及到 `main` 的 PR，且改动命中 `android/**`、`lib/**`、`assets/**`、`pubspec.yaml`、`pubspec.lock`、`l10n.yaml`、`scripts/build_android.ps1` 或 workflow 自身。
- 环境：`ubuntu-latest`、Temurin JDK 17、`subosito/flutter-action` 固定 **3.47.7**（与 `tool/flutter-sdk.json` 一致）、Gradle 与 pub 缓存。
- 步骤：`lfs: true` 检出 → `flutter pub get` → `flutter gen-l10n` + `dart run tool/generate.dart`（生成文件不入库，CI 必须重新生成）→ `flutter build apk --release --split-per-abi` → 上传 `android-release-apks`。
- 首次运行会下载 NDK、Android 平台和 Rust 目标，加上 400 MB+ 资产，整条流水线较慢；`timeout-minutes: 120` 是保守值。
- 产物用 debug 签名，仅用于内部测试，不要直接对外分发；签名方案见第 7 节。

### 3.6 安装到模拟器 / 真机

`adb` 在 Android SDK 的 `platform-tools` 下（本机没有加入 PATH）：

```powershell
$adb = "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe"

# MuMu 模拟器：先连上 adb（Android 15 / x86_64）
& $adb connect 127.0.0.1:16384
& $adb devices

# 安装（debug 包可直接覆盖安装；-t 允许 test-only 包）
& $adb install -r -t build/app/outputs/flutter-apk/app-debug.apk

# 只看 Flutter 日志
& $adb logcat -s flutter

# 需要全部日志时
& $adb logcat | Select-String -Pattern 'flutter|WofPlatformChannel|AndroidRuntime'
```

真机默认用 `android-arm64`。模拟器如果是 x86_64，必须用 `--target-platform android-x64`，否则装包会出现 `INSTALL_FAILED_NO_MATCHING_ABIS`。

### 3.7 已在模拟器验证的启动路径（2026-11-08）

参考环境：MuMu 模拟器，Android 15 / API 36，x86_64，`adb connect 127.0.0.1:16384`；登记的 Flutter 3.47.7 + JDK 17 + Android SDK API 36 / NDK 28.2.13676358 / CMake 3.22.1。以下结论基于重新构建并 `adb install -r -t` 全新安装的 debug 包。

已确认：

- `flutter build apk --debug --target-platform android-x64` 构建成功，首次完整构建约 465 秒（依赖与引擎缓存后会明显更快），产物 `build/app/outputs/flutter-apk/app-debug.apk` 为 313,062,058 字节（Flutter 输出显示 298.6 MB）。
- `adb install -r -t app-debug.apk` 流式安装约 9 秒；冷启动进入登录/品牌页，深色主题与状态栏 inset 正常；点 SKIP 进入主界面。
- 主界面使用移动端底部导航（生成 / 画廊 / 设置）+ 移动端外壳；生成页可看到提示词编辑器、模型栏、参数条和生成按钮；画廊空状态与提示弹窗正常；设置页可打开（仍是桌面双栏布局）。
- 在登录 → 主界面 → 生成 / 画廊 / 设置之间切换时没有出现 `MissingPluginException`、`ProcessException` 或崩溃；`sqflite` FFI 在 Android 上初始化成功；Hive 数据位于 `/data/user/0/com.wof.nai_launcher/files/hive`，图库根目录为 `/data/user/0/com.wof.nai_launcher/app_flutter/NAI_Launcher/images`。
- 功能入口按能力隐藏（代码与运行界面核对一致）：设置导航只显示 概览 / 账号 / 外观 / 画布与浏览 / 快捷键 / 生成与额度 / 存储与图库 / 词库与缓存 / 模型与接口；Agent、语义检索、本地放大、网络页不出现；Krita 与外部 Agent 设置区隐藏，ComfyUI 保留；Agent 侧栏入口消失；图库/查看器里的放大入口消失；应用内更新检查与安装不可用。
- 窄屏适配（360dp）：登录/品牌页底部溢出、生成页外层三栏 Row 溢出、图库工具栏溢出已修复；移动端频道装饰主题限制为 2 种。**残留**：设置页仍沿用桌面双栏侧栏布局，窄屏下内容区偏挤，debug 构建会打印 RenderFlex overflow 警告（release 构建只裁剪、不画条纹），属移动端 UX 后续项，不是崩溃。
- 以上修复只作用于移动端分支/运行时判断，桌面布局与行为未变。

**未验证**：该测试环境模拟器没有可用网络（连通性检查超时），也没有提供 NovelAI API Token，所以登录、生图、图片保存等联网链路**没有做端到端验证**。这些功能需要在有网络的模拟器/真机 + 账号凭据下另行验证。

### 3.8 网络慢或需要代理

Flutter 与 Gradle 走各自的代理配置：

```powershell
# 当前 PowerShell 会话
$env:HTTP_PROXY  = 'http://127.0.0.1:7897'
$env:HTTPS_PROXY = 'http://127.0.0.1:7897'
```

Gradle 代理写在 `%USERPROFILE%\.gradle\gradle.properties`（不要写进仓库）：

```properties
systemProp.http.proxyHost=127.0.0.1
systemProp.http.proxyPort=7897
systemProp.https.proxyHost=127.0.0.1
systemProp.https.proxyPort=7897
```

首次构建还会下载 NDK、Android 平台、Rust 目标和 cargokit 产物，代理同样适用于这些下载。

## 4. 功能矩阵（Android vs 桌面）

| 功能 | 桌面（Windows/macOS） | Android | 说明 |
| --- | --- | --- | --- |
| NovelAI 生图、画布、历史、参数复用 | ✓ | ✓ | 纯网络 + 本地存储 |
| 本地画廊、图库整理 | ✓ | ✓ | 默认图库目录为应用私有目录；"导入"是系统文件选择器多选图片复制进图库，ZIP 导出交给系统分享面板；手动保存生成图会镜像到系统相册（自动保存不会，原生侧按显示名去重） |
| 在线画廊（Danbooru 等） | ✓ | ✓ | 纯网络 |
| ComfyUI 桥接 | ✓ | ✓ | 连接运行 ComfyUI 的局域网/远程机器 |
| 3D 编辑器 | ✓（WebView2） | ✓（Android System WebView） | WebView 不可用/被禁用的设备上会失败 |
| 视频播放 | ✓（media_kit） | ✓（系统原生播放器） | Android 没有 media_kit 原生库，使用 `video_player_android` |
| 标签库 / 标签百科 / 翻译补全 | ✓ | ✓ | SQLite 随包资源 + `sqlite3_flutter_libs` |
| 云端放大 | ✓ | ✓ | NovelAI 接口 |
| 本地 / 高级放大（Real-ESRGAN、RTX Video、SeedVR2） | ✓ | ✗ | 依赖随包 `.exe` 和外部进程，Android 上入口隐藏/保持 inert；APK 里的 onnxruntime 只有 arm64 / armeabi-v7a 库，x86_64 模拟器没有 |
| 本地语义检索 RAG（Python 运行时） | ✓ | ✗ | 依赖 Python/uv/PyTorch 外部进程 |
| NAI Agent（Node 运行时、MCP、Skill） | ✓ | ✗ | 依赖随包 Node 与进程管理 |
| Krita 桥接 | ✓ | ✗ | 本地 WebSocket 服务 + 桌面插件端 |
| 外部桥接客户端（studio-bridge.exe） | ✓ | ✗ | 桌面可执行文件 |
| 应用内更新检查/安装 | ✓ | ✗ | 桌面安装包链路；Android 更新走应用商店或手动安装 APK |
| 系统托盘、多窗口/独立资源小窗 | ✓ | ✗ | Android 无对应插件能力 |
| Windows 系统代理 / GPU 诊断 | ✓ | ✗ | 注册表 / `nvidia-smi` 专属 |
| 系统字体列表/安装 | ✓ | ✗ | 原生字体通道仅桌面注册；Android 仍可使用随包字体 |
| 剪贴板与拖放 | ✓ | 部分 | `super_clipboard` / `super_drag_and_drop` 支持 Android；其它应用拖入、剪贴板图片格式与桌面存在差异 |
| 完成提示音 | ✓ | ✓ | `audioplayers` 播放应用内音效；不使用系统通知栏 |
| 键盘快捷键 | ✓ | 部分 | 触屏为主；外接键盘时部分快捷键可用 |

Android 上隐藏/降级的功能入口按 `desktop_platform.dart` 的能力 getter 判断，不改变桌面实现。

## 5. 已知限制

1. **APK 很大**：`assets/databases` 约 419 MB，字体约 31 MB，翻译资源约 34 MB，加上其它资源总计约 500 MB。当前 x86_64 debug 包实测 **313,062,058 字节（Flutter 输出显示 298.6 MB）**，其中还带有部分插件的多 ABI 预编译 `.so`（onnxruntime / sqlite3 的 arm64、armeabi-v7a 库随包进入）；安装和首次启动都明显比桌面版慢。后续方向：AAB + Play Asset Delivery、按需下载语言/数据库资产、拆分内置数据；当前分支未做。
2. **release 未正式签名**：当前沿用 debug 签名（见第 7 节），不能发布。
3. **没有 iOS 目标**：`ios/` 未生成；`isIOSPlatform` 只是给未来移植留的判断。
4. **存储范围**：Android 上默认图库/数据目录在应用私有空间，不能像桌面那样任意指定磁盘文件夹；导入外部图片走系统文件选择器（SAF）。手动保存生成图时会把副本镜像到系统相册 `Pictures/W.O.F NAI Studio`（Android 10+），自动保存的图片和图库里的其它文件仍只在应用私有目录；卸载应用会删除私有目录数据，重要作品请及时导出。
5. **移动端图库交互（待补）**：Android 上图片卡片的**长按绑定为多选**，桌面用右键打开的图片上下文菜单（含放大、分享等卡片操作）在触屏上没有入口。这是移动端 UX 待补项，不是桌面功能回归；需要时用图片详情页或后续给卡片加长按菜单。
6. **窄屏布局**：登录/品牌页底部溢出、生成页外层三栏 Row 溢出、图库工具栏溢出已在 2026-11-08 修复并在 360dp 验证；移动端频道装饰主题限制为 2 种。**残留**：设置页仍是桌面双栏侧栏布局，窄屏下内容区偏挤，debug 构建会打印 RenderFlex overflow 警告（release 构建只裁剪、不画条纹）；属于移动端 UX 后续项，不是崩溃，也不影响桌面布局。
7. **剪贴板/拖放差异**：Android 系统剪贴板与拖放对图片格式、文件 URI 的支持不如 Windows 宽松；Windows 专属的 PowerShell/System.Drawing 剪贴板路径只在桌面使用。
8. **后台限制**：没有托盘常驻；应用退到后台后可能被系统回收，长时间生成期间建议保持前台。
9. **明文 HTTP**：manifest 开启 `usesCleartextTraffic` 以支持局域网 ComfyUI，正式发布前应评估是否收窄。
10. **构建所需外部资源**：首次构建要下载 NDK、Rust 目标、cargokit 预编译/编译产物，离线环境需要提前预热缓存。
11. **运行时验证范围**：目前只在 MuMu x86_64（API 36）做了启动、导航和功能入口的 smoke test；登录、生图、图片保存等联网链路尚未端到端验证（测试环境无网络、无 NovelAI Token），release APK 也还没做真机回归。

## 6. 排障

### 6.1 编译报 "No named parameter with the name ..."、`SizeTransition.alignment` 等 API 错误

几乎都是 **Flutter SDK 版本不对**：`PATH` 上是 3.41.6 之类的旧版。Android 模板和源码都按登记的 **3.47.7** 生成。用下面任一方式核对：

```powershell
# 1) 直接看登记 SDK 的版本
& D:\sdk\flutter-3.47.7\bin\flutter.bat --version

# 2) 通过仓库入口指定 SDK
./scripts/flutter_studio.ps1 -SdkRoot D:\sdk\flutter-3.47.7 -FlutterArgs @('--version')

# 3) 给构建脚本指定
./scripts/build_android.ps1 -FlutterPath D:\sdk\flutter-3.47.7 -DryRun
```

`scripts/build_android.ps1` 在检测到版本与 `tool/flutter-sdk.json` 不一致时会直接报错。

### 6.2 Gradle 报 JDK 版本问题

AGP 8.11 / Gradle 8.14 需要 JDK 17–24。若 `java -version` 是 11，用 `flutter config --jdk-dir="<JDK 17>"` 指定；构建脚本也会自动从 Flutter 配置和常见安装目录找 JDK 17，并在 `JAVA_HOME` 上忽略 11。不要改系统全局 `JAVA_HOME` 去凑。

### 6.3 首次构建卡在下载 / NDK 或 Rust 相关失败

- NDK：Android SDK 缺 `28.2.13676358` 时 Gradle 会自动下载（约 1 GB），前提是许可已接受。失败时手动装：`sdkmanager "ndk;28.2.13676358" "platforms;android-36" "build-tools;36.0.0" "cmake;3.22.1"`。
- `super_native_extensions` 的 Rust 库：cargokit 在检测到 rustup 时本地编译（会自动装 Android target），否则从 GitHub 下载预编译二进制；本机 0.9.1 走的是预编译下载。两条路都需要网络；慢网络按 3.8 配置代理。
- 清理重试：`flutter clean` 后重跑；Gradle 侧缓存异常可删除 `android/.gradle/`（已忽略）再试，不要顺手删 `build/` 之外的其它目录。

### 6.4 安装 APK 报 ABI 不匹配

`INSTALL_FAILED_NO_MATCHING_ABIS` / `adb install` 失败：包和设备的 CPU 架构不一致。x86_64 模拟器用 `--target-platform android-x64` 构建；真机用 `android-arm64`；不确定时用 `--split-per-abi` 分别安装。

### 6.5 `MissingPluginException`

表示 Dart 调用的 MethodChannel/插件在 Android 上没有实现。正确处理方式是"能力判断 + 早返回/降级"，而不是捕获异常继续。若出现在新功能上，检查调用点是否漏了 `supportsXxx` 判断；若是 `com.nailauncher/platform` 通道，确认 `MainActivity` 的 `configureFlutterEngine` 注册了该通道、且 APK 是重新构建的（不是旧的缓存包）。

### 6.6 应用启动即崩溃（`SuperNativeExtensionsPlugin` / `.so`）

多半是 `super_clipboard` / `super_drag_and_drop` 仍是 0.8.x，Android 端没有构建 Rust 原生库。确认 `pubspec.yaml` 使用 ^0.9.1，必要时 `flutter clean` 后重建。

### 6.7 只看应用日志

```powershell
& $adb logcat -s flutter
# 需要平台通道/原生崩溃时
& $adb logcat -s flutter WofPlatformChannel AndroidRuntime
```

### 6.8 构建脚本报 Git LFS 指针 / 生成源码缺失

- `assets/databases` 是 LFS 指针：`git lfs install; git lfs pull`。
- `Generated Dart sources are missing`：按 3.2 跑 `flutter pub get` → `dart run tool/generate.dart` → `flutter gen-l10n`。

### 6.9 构建日志里的 Gradle / AGP / Kotlin 版本警告（预期，不阻塞）

用登记的 Flutter 3.47.7 构建当前 `android/` 时，Gradle 会打印版本警告，例如：

- Gradle 8.14 低于 9.1.0 的警告阈值；
- AGP 8.11.1 低于 9.0.1 的警告阈值（AGP 8.11.1 是错误阈值/最低支持版本，不能再低）；
- Kotlin 2.2.20 低于 2.3.20 的警告阈值。

这些警告**不阻塞构建**，而且当前组合是有效的：Gradle 8.14 与 AGP 8.11.1 正是 Flutter 3.47.7 模板的最低支持版本。后续如果整体对齐新版 Flutter 模板，推荐组合是 Gradle 9.3.1 / AGP 9.0.1 / Kotlin 2.4.0；这只是升级建议，**当前没有升级，也不是完成 Android 构建所必需**。不要单独改其中一项版本，升级时要同步改 Gradle wrapper、AGP、Kotlin 并重新验证桌面与 Android 构建。

## 7. 发布签名（TODO）

当前 `android/app/build.gradle.kts` 的 `release` 使用 `signingConfigs.getByName("debug")` 占位，`flutter build apk --release` 能跑通但**产物不可发布**。正式发布前需要：

1. 生成 keystore（一次性，妥善备份，丢失后无法覆盖升级）：

```powershell
keytool -genkeypair -v -keystore "$env:USERPROFILE\.android-keystores\wof-nai-studio.jks" `
  -alias wof-nai-studio -keyalg RSA -keysize 4096 -validity 10000
```

2. 在 `android/` 下新建 `key.properties`（**不要提交**；`android/.gitignore` 已忽略该文件名和 `*.jks` / `*.keystore`）：

```properties
storeFile=C:/Users/<user>/.android-keystores/wof-nai-studio.jks
storePassword=***
keyAlias=wof-nai-studio
keyPassword=***
```

3. 在 `android/app/build.gradle.kts` 里读取 `key.properties` 并替换 release 的 `signingConfig`（这是后续实现项，当前文件仍是占位 TODO）：

```kotlin
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = java.util.Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}
android {
    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }
    buildTypes {
        release {
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}
```

4. 校验：`keytool -list -v -keystore <jks>`，以及 `apksigner verify --print-certs <apk>`。
5. 密钥、口令只放在本机或 CI Secret 中，不写进仓库、提交信息或日志。

## 8. 相关文件与后续

新增/相关文件：

- `android/`：Android 工程；`android/README.md` 是同一目录的简版说明。
- `lib/core/utils/desktop_platform.dart`：平台能力 getter。
- `android/app/src/main/kotlin/com/wof/nai_launcher/MainActivity.kt`：Android 平台通道（打开/分享/另存相册/打开目录）。
- `scripts/build_android.ps1`：本地构建 + 预检。
- `.github/workflows/android-build.yml`：Linux CI 构建 release APK。
- `docs/android-port.md`：本文。

后续工作（按优先级）：

1. 正式签名 + 发布流程（第 7 节），并决定分发渠道（GitHub Release APK / 应用商店 AAB）。
2. 资源瘦身与按需资产（AAB + Asset Delivery；数据库/语言包按需下载），控制 APK 体积。
3. Android 端真实设备/模拟器回归：先在**有网络且提供 NovelAI 凭据**的环境补做登录、生图、图片保存/MediaStore 相册镜像的端到端验证，再覆盖图库导入、ComfyUI 连接、3D 编辑器 WebView、剪贴板/拖放。
4. 移动端交互与布局补齐：图库卡片长按菜单（当前长按是多选，桌面右键菜单在触屏没有入口）、设置页窄屏双栏布局。
5. 视需要处理后台任务与生命周期策略（当前没有托盘常驻，退到后台可能被系统回收）。

维护约定：修改 getter 名称或 Android 能力边界时同步更新本文第 2、4 节；改 `android/` 或构建脚本时确认 CI 触发路径仍覆盖。
