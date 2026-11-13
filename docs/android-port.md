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
- **Manifest 权限**：`INTERNET`、`ACCESS_NETWORK_STATE`（NovelAI、ComfyUI、第三方桥接均为网络服务）、`POST_NOTIFICATIONS`（后台生成的前台服务进度/完成通知；Android 13+ 第一次开始生成时按需申请运行时权限，见 1.3 与第 5 节）、`REQUEST_INSTALL_PACKAGES`（应用内 APK 更新交给系统安装器）、`FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_DATA_SYNC`（生成中后台保活）、`READ_EXTERNAL_STORAGE`（`maxSdkVersion=32`）、`READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO`（Android 13+ 导入图片/视频）。
- **后台生成前台服务**：`GenerationForegroundService`（`android:foregroundServiceType="dataSync"`、不导出），由 `com.nailauncher/generation` 通道的 `start` / `update` / `stop` 驱动；通知 channel 固定为 `wof_generation`。
- **接收系统分享**：`MainActivity` 增加 `ACTION_SEND` + `image/*` intent-filter（G16），只处理单张图片；收到的图片先拷到 cache 的 `incoming_shares/`，再由 Dart 侧消费并送进图生图。
- **`usesCleartextTraffic="true"`**：允许局域网内的 ComfyUI、自建服务或本地桥接使用 `http://`。这是便利性与安全性的取舍；不要用它访问不可信网络上的明文服务。
- **`largeHeap="true"`**：应用会解码大尺寸图片、加载多个数据库，Android 默认堆上限偏紧。
- **`super_native_extensions` DataProvider**：`authorities="${applicationId}.SuperClipboardDataProvider"`，供 `super_clipboard` / `super_drag_and_drop` 接收其它应用拖放/复制的图片与文件。
- **FileProvider**：`authorities="${applicationId}.fileprovider"` + `res/xml/file_provider_paths.xml`，把应用私有目录/缓存中的文件暴露成其它应用可读的 `content://` URI，用于 `ACTION_VIEW` 打开图片/视频、`ACTION_SEND` 分享，以及应用内更新（G17）把 cache 里的 APK 交给系统安装器。更新下载目录 `cache/nai_launcher_updates/` 已被现有 `<cache-path>` 覆盖，**没有也不需要一个独立的 APK FileProvider**。
- **`<queries>`**：`PROCESS_TEXT`（Flutter 文本处理插件）以及 `VIEW` 图片/视频/任意文件（打开外部查看器）。
- **打包**：`packaging.jniLibs.useLegacyPackaging = true`，`sqlite3_flutter_libs` 与 `super_native_extensions` 的 `.so` 需要从解压后的原生库目录加载。
- **签名占位**：`release` 构建当前复用 `debug` 签名配置（`android/app/build.gradle.kts` 中有 TODO）。**当前 release APK 不能对外发布**，正式签名见第 7 节。

### 1.2 依赖调整：`super_clipboard` / `super_drag_and_drop` 升到 ^0.9.1

0.9.x 修复了 Android 端的 cargokit Gradle 插件探测：旧版只匹配简单类名，新版 Flutter Gradle 插件使用全限定类名 `com.flutter.gradle.FlutterPlugin`，0.8.x 在 Android 上会跳过 Rust 原生库构建，导致 `SuperNativeExtensionsPlugin` 静态加载 `.so` 失败、应用启动崩溃。升级后两个插件在 Android 上正常注册。

其余桌面插件（`window_manager`、`tray_manager`、`screen_retriever`、`desktop_multi_window`、`media_kit_libs_windows_video` / `media_kit_libs_macos_video`、`path_provider_windows`、`url_launcher_windows`、`audioplayers_windows`、`flutter_inappwebview_windows` 等）没有 Android 实现，Flutter 在 Android 上不会注册它们，Dart 侧通过平台能力判断避免调用。

### 1.3 平台能力判断与配套文件

- `lib/core/utils/desktop_platform.dart` 新增 Android 平台与能力 getter（见第 2 节）。
- 桌面专属 service、设置页和入口按能力 getter 做运行时降级或隐藏，不在 Android 上引用桌面插件。
- 文件/图库/剪贴板的 Android 适配：Dart 侧统一走 `PlatformFileChannel`。**手动保存**生成图时额外把副本镜像到系统相册 `Pictures/W.O.F NAI Studio`（MediaStore，Android 10+，原生侧按显示名去重）；**自动保存不会镜像**，避免每张图都进相册。保存失败只记日志，不影响图库保存。
- Android 平台通道（原生实现都在 `android/app/src/main/kotlin/com/wof/nai_launcher/`）：
  - `com.nailauncher/platform`（`MainActivity.kt`）：`openFile` / `shareFile` / `saveImageToMediaStore` / `openDirectory` / `getSystemProxy`，以及分享入站的 `getSharedImage` / `shareImageReceived`；
  - `com.nailauncher/generation`（`MainActivity.kt` → `GenerationForegroundService.kt`）：`start` / `update` / `stop`，通知 channel `wof_generation`；
  - `com.nailauncher/apk_install`（`ApkInstallHelper.kt`）：`supportedAbis` / `installApk` / `canRequestPackageInstalls` / `openUnknownSourcesSettings`；
  - `com.nailauncher/notifications`（`NotificationPermissionHelper.kt`）：`areNotificationsEnabled` / `requestNotifications` / `openNotificationSettings`，Android 13+ 通知运行时权限（API < 33 直接视为已授权；设置页跳转失败退回应用详情页）。
- 分享（G15 / G16）：
  - **出站**：统一走 `AndroidShareService`（有文件路径就分享文件；未保存的生成结果先把内存字节写到 cache 再分享），入口在手机查看器「更多」、画廊长按菜单、生成结果长按菜单；桌面不显示分享行。
  - **入站**：`AndroidShareIntake` 消费 `ACTION_SEND image/*`（单张，拷贝到 cache 的 `incoming_shares/`），启动时轮询、运行中通过 `shareImageReceived` 信号触发，随后打开图生图并提示；桌面无该入口。
- 后台生成（G10）：`GenerationBackgroundSync` 监听生成状态，开始时启动 dataSync 前台服务、按进度节流更新通知，完成 / 失败 / 取消时停止服务并发一条完成通知；桌面平台所有调用 no-op。通知权限由 G18 补充：第一次开始生成时经 `com.nailauncher/notifications` 按需申请（不冷启动弹窗），用户拒绝后不再重复申请，只在首次拒绝后给一次「去设置」引导（`NotificationPermissionService` + `NotificationPermissionWiring`）。
- 应用内更新（G17）：`AndroidUpdateService` 检查 GitHub Release → 按设备 ABI 选 APK → 下载到 cache 的 `nai_launcher_updates/`（`.part` + rename、大小/SHA256 校验；不做断点续传）→ `ApkInstallHelper` 通过现有 `${applicationId}.fileprovider` 拉起系统安装器；桌面更新链路逐字节不变。更新源与桌面共用 `z15087716457-stack/W.O.F_NAI_Launcher`（保留原项目归属说明）。入口在「设置 → 关于」：头部按钮手动检查更新，更新卡片显示版本/大小/notes 与下载进度，有新版本时提供「下载并安装」；发现新版本时底栏「设置」显示红点，Android 上不显示会打开桌面更新对话框的全局横幅。自动检查与桌面共用启动后 3 秒的检查逻辑。
- 手机端布局：`lib/presentation/mobile/` 提供地基；设置页 `settings_mobile.dart`（列表 → 详情）、画廊 `mobile_local_gallery.dart`（长按菜单 / 多选 / 详情弹层）、查看器与编辑器/局部重绘页的移动分支都按 `usesMobileLayout` 进入，桌面布局不变。细节见 `docs/mobile-adaptation.md`。
- 构建工具：`scripts/build_android.ps1`（本地一键构建 + 预检）。
- CI：`.github/workflows/android-build.yml`（Linux 上构建 release APK 并上传）。
- 忽略规则：根 `.gitignore` 增加 `dist/android/`、`*.apk`、`*.aab`、`android/.kotlin/`（`android/.gitignore` 已覆盖 Gradle、`local.properties`、keystore 等，不重复）。
- `analysis_options.yaml`：`flutter pub get` 自动在 `analyzer.exclude` 中加入 `android/**`（Flutter 工具行为）；构建日志里的 "Upgrading gradle.properties" 也只是工具升级提示，都是正常输出，不需要手动改回。

### 1.4 设备端本地放大与 NAI Agent 运行时

这两项是 Android 独有的实现，桌面端原有链路不变。

- **设备端本地放大（ONNX Runtime）**：`lib/data/services/onnx_upscale_engine.dart` 通过
  Dart FFI 调用 `libonnxruntime.so`（1.15.1，取自 Maven `com.microsoft.onnxruntime:onnxruntime-android`
  的 arm64-v8a 库），随包模型见 `onnxUpscaleCatalog`：`animevideov3-256`（2.4 MB，
  固定 256 输入，二次元）与 `realesr-general-x4v3`（4.9 MB，动态输入，通用照片），
  都是 4 倍输出、按 256 分块推理，面板可在两者间切换；不下载外部运行时，也不需要
  可执行位。`supportsOnnxUpscale` 只在 Android 为 true，UI 入口见生成页画布与
  「本地放大」面板、图库长按与图片查看器。输入保留 120 万像素预算，超过时提前提示；
  降低倍率不能解除限制，自动本地增强在生成请求前检查，不自动缩图。手机不提供模型管理。
  更大 ONNX 模型与提速后端的可行性见
  [local-upscale-advanced.md](local-upscale-advanced.md)。
- **NAI Agent 运行时**：`tool/nai_agent`（`host.mjs` + Pi SDK 1.5.0 + 内置 skills）由
  `tool/pack_agent_runtime.ps1` 打包为 `assets/nai_agent/runtime.tar.gz`（约 24.7 MB）。
  `android/app/src/main/cpp/node_runtime_jni.cpp` 把 nodejs-mobile 的 `libnode.so`
  （Node 24.5.0）链进应用进程，`NodeRuntimeChannel.kt` 提供 `com.nailauncher/node_runtime`
  通道（`start` / `writeStdin` / `stop`），Dart 侧 `PiHostClient` 通过 `PiHostProcess`
  抽象在桌面子进程与内嵌运行时之间切换，桌面仍走 `Process.start`。
  - 运行时首次使用解压到 `<app support>/nai_agent/runtime`（流式 gunzip + tar，约 1.67 万个文件 / 16,716 个文件条目）。解压由 `AndroidNodeRuntimeBundle` 完成，`.runtime-version` 标记避免重复解压；
    app 启动后会在后台预热，用户真正打开 Agent 面板时通常已就绪。
  - libnode 在同一进程内只能启动一次，Android 由 `android-host.mjs` 路由 JSONL，
    每个客户端通过独立 Worker 运行 `host.mjs`（Worker 内 `NAI_HOST_REINIT=0`）。
    关闭会话释放自己的 Worker，进程保留；桌面仍使用原来的子进程链路。
  - `jniLibs` 只随包 arm64-v8a（`libnode.so` / `libonnxruntime.so` / `libc++_shared.so`，
    由 Git LFS 管理）；x86_64 仅用于本地模拟器调试，已在 `.gitignore` 排除。
  - 翻译微调已开放，独立 Worker 保留原翻译上下文、只开放译文块读写工具，版本校验与
    撤销沿用现有链路；关闭微调不重置 Agent。Node 合成并发与 Dart 通道路由测试已覆盖，
    Android 真机并发内存和后台存活尚待验证。

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
| `supportsInAppUpdateInstall` | 桌面应用内更新安装（Windows PS1 / macOS Finder；Android 走独立 APK 链路，见下方注意） | ✓ | ✓ | ✗ |
| `supportsSystemFonts` | 列出/安装系统字体（原生 `system_fonts` 通道） | ✓ | ✓ | ✗ |
| `supportsSystemProxy` | 读取系统代理（注册表 / `scutil`） | ✓ | ✓ | ✗ |
| `supportsWindowsProxy` | Windows 注册表代理 | ✓ | ✗ | ✗ |
| `supportsGpuProbe` | GPU 探测（`nvidia-smi`） | ✓ | ✓ | ✗ |
| `supportsLocalRagRuntime` | 本地 RAG Python 运行时（uv + PyTorch） | ✓ | ✓ | ✗ |
| `supportsLocalUpscale` | 随包可执行文件的本地/高级放大（realesrgan / SeedVR2 / RTX Video） | ✓ | ✓ | ✗ |
| `supportsOnnxUpscale` | Android 设备端 ONNX Runtime 本地放大（随包 animevideov3 / general-x4v3 模型） | ✗ | ✗ | ✓ |
| `supportsNaiAgentRuntime` | NAI Agent 的随包 Node 运行时与宿主脚本 | ✓ | ✓ | ✓ |
| `supportsTranslationAdjustment` | 翻译微调（Android 在同一 libnode 内使用独立 Worker） | ✓ | ✓ | ✓ |
| `supportsKritaBridge` | Krita 桥接服务与插件 | ✓ | ✓ | ✗ |
| `supportsNativeTitleBarRegion` | Windows runner 原生标题栏命中区 | ✓ | ✗ | ✗ |
| `supportsWindowBackdropMaterial` | Windows DWM 窗口材质 | ✓ | ✗ | ✗ |
| `supportsWindowManagerEvents` | window_manager 窗口事件（隐藏/最小化） | ✓ | ✗ | ✗ |

> 注意：`supportsInAppUpdateInstall` 的语义是“桌面安装包链路”（Windows 更新脚本 / macOS Finder 核验），Android 上保持 `false`；Android 的应用内更新由 `isAndroidPlatform` 分支单独实现（见 1.3、第 4 节）。设置页更新状态按 `supportsInAppUpdateInstall || isAndroidPlatform` 合并判断，避免把桌面安装器语义套到手机上。

新增平台或功能时：先想清楚"这是能力还是平台"，能落到上面的 getter 就不要写死平台判断；桌面端已有行为用 Android 侧不进入的分支保留。

Android 上的取值口径：`isSupportedDesktop == false`、`isMobilePlatform == true`，上表绝大多数 `supports*` 能力是 `false`；例外是 Android 单独实现的 `supportsOnnxUpscale`、`supportsNaiAgentRuntime` 与 `supportsTranslationAdjustment`（见 1.4）。`supportsExternalProcesses` 的实现是 `!isMobilePlatform`，所以 Windows/macOS 之外、未移植的桌面/Linux 环境仍按原有行为返回 `true`，不改变既有桌面代码。设置页和功能入口统一用这些 getter 隐藏/降级（例如 Android 隐藏设置里的语义检索、网络页，隐藏 Krita 桥接、托盘/多窗口入口），不要在 UI 里散落平台判断。Android 的应用内更新不占用 `supportsInAppUpdateInstall`，它由 `isAndroidPlatform` 分支提供（见上一段注意）。

## 3. 构建

### 3.1 前置条件

- **Flutter 3.47.7**（Dart 3.13.5），以 `tool/flutter-sdk.json` 为准，与 Windows / macOS 构建一致。**不要**使用机器上其它版本的 `flutter`：用 3.41.6 构建会报 `No named parameter with the name 'onReorderItem'`、`SizeTransition.alignment` 之类的 API 不存在错误，因为源码和 Android 模板都是按登记的 3.47.7 写的。
  - 推荐用仓库自带入口：`scripts/flutter_studio.ps1 -SdkRoot <flutter-3.47.7 目录> -FlutterArgs @(...)`；或设置环境变量 `WOF_FLUTTER_SDK_ROOT`。
  - 也可以直接给 `scripts/build_android.ps1` 传 `-FlutterPath`。
  - 如果只能依赖 PATH 上的 `flutter`，先运行 `flutter --version` 确认是 3.47.7 再构建。
- **JDK 17**（AGP 8.11 要求 17+，Gradle 8.14 支持到 24）。PATH 上的 `java` 可能是 11，不要用它；用 `flutter config --jdk-dir="<JDK 17 目录>"` 指定，`scripts/build_android.ps1` 会自动优先读这个配置。
- **Android SDK**：API 36 平台、build-tools 36、**NDK 28.2.13676358**、CMake 3.22.1（部分原生组件需要）。`ANDROID_HOME` / `ANDROID_SDK_ROOT` 指向 SDK，或让 Flutter 生成 `android/local.properties`（该文件不入库）。
- **已接受的 SDK 许可**：`sdkmanager --licenses`。未接受时 Gradle 无法自动补装平台、build-tools 或 NDK。
- **Git LFS**：`assets/databases/`（约 419 MB）与 `android/app/src/main/jniLibs/arm64-v8a/`（libnode / libonnxruntime / libc++_shared，约 165 MB）由 LFS 管理，必须先 `git lfs pull`，否则打包进去的是指针文件或直接构建失败。
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

release（按 ABI 拆分，CI 使用；仓库只随包 arm64-v8a 原生库，因此实际只产出 arm64 包）：

```powershell
flutter build apk --release --split-per-abi --target-platform android-arm64
```

APK 输出目录固定为 `build/app/outputs/flutter-apk/`：

| 构建 | 产物 |
| --- | --- |
| `--debug`（单 ABI） | `app-debug.apk` |
| `--release`（单 ABI） | `app-release.apk` |
| `--release --split-per-abi --target-platform android-arm64` | `app-arm64-v8a-release.apk` |
| `--debug --target-platform android-x64`（模拟器，需自备 `jniLibs/x86_64`） | `app-debug.apk` |

`--split-per-abi` 只拆分原生库，**资源和数据库仍然每个 APK 各带一份**，所以拆包并不会显著减小总体积。`jniLibs` 只提交 arm64-v8a（libnode / libonnxruntime / libc++_shared）；x86_64 调试包需要自己从 nodejs-mobile 与 ONNX Runtime AAR 取库放到 `android/app/src/main/jniLibs/x86_64/`（该目录已在 `.gitignore` 排除）。

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
- 步骤：`lfs: true` 检出 → `flutter pub get` → `flutter gen-l10n` + `dart run tool/generate.dart`（生成文件不入库，CI 必须重新生成）→ `flutter build apk --release --split-per-abi --target-platform android-arm64` → 上传 `android-release-apks`。
- 首次运行会下载 NDK、Android 平台和 Rust 目标，加上 400 MB+ 资产，整条流水线较慢；`timeout-minutes: 120` 是保守值。
- 产物用项目固定的 release 密钥签名（CI 从 Secrets 还原，见 §7.6），可用于覆盖安装；PR 来自 fork 拿不到 secret 时退回 debug 签名（仅供构建验证）。

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

### 3.7 模拟器验证记录

#### 2026-11-08 启动路径

参考环境：MuMu 模拟器，Android 15 / API 36，x86_64，`adb connect 127.0.0.1:16384`；登记的 Flutter 3.47.7 + JDK 17 + Android SDK API 36 / NDK 28.2.13676358 / CMake 3.22.1。以下结论基于重新构建并 `adb install -r -t` 全新安装的 debug 包。

已确认：

- `flutter build apk --debug --target-platform android-x64` 构建成功，首次完整构建约 465 秒（依赖与引擎缓存后会明显更快），产物 `build/app/outputs/flutter-apk/app-debug.apk` 为 313,062,058 字节（Flutter 输出显示 298.6 MB）。
- `adb install -r -t app-debug.apk` 流式安装约 9 秒；冷启动进入登录/品牌页，深色主题与状态栏 inset 正常；点 SKIP 进入主界面。
- 主界面使用移动端底部导航（生成 / 画廊 / 设置）+ 移动端外壳；生成页可看到提示词编辑器、模型栏、参数条和生成按钮；画廊空状态与提示弹窗正常。
- 在登录 → 主界面 → 生成 / 画廊 / 设置之间切换时没有出现 `MissingPluginException`、`ProcessException` 或崩溃；`sqflite` FFI 在 Android 上初始化成功；Hive 数据位于 `/data/user/0/com.wof.nai_launcher/files/hive`，图库根目录为 `/data/user/0/com.wof.nai_launcher/app_flutter/NAI_Launcher/images`。
- 功能入口按能力隐藏（代码与运行界面核对一致）：设置导航只显示 概览 / 账号 / 外观 / 画布与浏览 / 快捷键 / 生成与额度 / 存储与图库 / 词库与缓存 / 模型与接口；Agent、语义检索、本地放大、网络页不出现；Krita 与外部 Agent 设置区隐藏，ComfyUI 保留；Agent 侧栏入口消失；图库/查看器里的放大入口消失。
- 窄屏适配（360dp）：登录/品牌页底部溢出、生成页外层三栏 Row 溢出、图库工具栏溢出已修复；移动端频道装饰主题限制为 2 种。
- 以上修复只作用于移动端分支/运行时判断，桌面布局与行为未变。

当时未验证：该测试环境模拟器没有可用网络（连通性检查超时），也没有提供 NovelAI API Token，所以登录、生图、图片保存等联网链路没有做端到端验证。

#### 2026-11-09 本轮能力与构建

本轮加入 G10（后台生成前台服务）、G15（分享出站）、G16（接收系统分享）、G17（应用内 APK 更新），并完成手机端设置页 / 画廊 / 查看器 / 编辑器（局部重绘）页的移动布局适配。此前 2026-11-08 记录的“设置页仍是桌面双栏布局”“应用内更新检查与安装不可用”等结论已被取代，以本小节和代码为准。

- 最近一次 `flutter build apk --debug --target-platform android-x64` 已通过（产物 `build/app/outputs/flutter-apk/app-debug.apk`，2026-11-09 04:28 生成）。该构建发生在合并 G17 原生改动之后，说明 `ApkInstallHelper.register(...)`、`REQUEST_INSTALL_PACKAGES`、dataSync 前台服务声明与 `ACTION_SEND` intent-filter 的 Kotlin/manifest 可编译。
- 另有同日 02:59 生成的 release split-per-abi 三包（`app-arm64-v8a-release.apk` / `app-armeabi-v7a-release.apk` / `app-x86_64-release.apk`，早于 G17 原生合并），用于确认 release 链路可用；仍为 debug 签名，仅内部测试用。
- 设置页手机端为分组列表 → 详情页（搜索、深链、锚点、撤销浮条、返回确认都复用桌面逻辑），桌面双栏布局不变；画廊手机端有长按菜单 / 多选 / 详情底部弹层；查看器、编辑器 / 局部重绘、导演工具与画布工具面板都有手机布局分支（触控目标收尾见第 5 节）。详见 `docs/mobile-adaptation.md`。
- 功能层面的真机/模拟器手测仍待执行，按 3.9 的清单走一遍。

**仍未验证**：在有网络且提供 NovelAI 凭据的环境做登录、生图、图片保存 / 相册镜像的端到端验证；3.9 列出的更新、分享、后台生成、手机布局手测；release APK 的真机回归。桌面端（Windows/macOS）行为未受本轮改动影响。

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

### 3.9 本轮新增能力的真机手测清单

以下路径在 debug 构建上按顺序走一遍（模拟器/真机均可）。更新项需要先有一个**带 APK 资产**的 GitHub Release，否则只会提示有新版本、没有可安装包。

1. **应用内更新（G17）**：`设置 → 关于` 点页头的「检查更新」→ 有新版本时更新卡片显示最新版本 / 包大小 / release notes → 点「下载并安装」→ 更新卡片显示下载进度（大包耗时较长）→ 若系统尚未允许本应用安装未知应用，会自动跳到本应用的「安装未知应用」系统设置页；打开允许后返回应用，再点一次「下载并安装」→ 系统安装器弹出 → 确认安装后覆盖升级，重启后版本号变化。
   - 失败路径：Release 没有 APK 资产时卡片进入失败状态；日志过滤 `flutter` / `WofApkInstall` / `AndroidRuntime`。
2. **分享出站（G15）**：查看器「更多」、画廊长按菜单、生成结果长按菜单点「分享」→ 系统分享面板出现 → 发送到图片/文件类应用后能被正常打开。
3. **分享入站（G16）**：在系统相册 / 浏览器对一张图片点「分享」选择本应用 → 应用切到生成页且该图已作为图生图输入（提示“已送入图生图”）；再试一次冷启动分享（先杀掉应用再分享）。
4. **后台生成（G10 / G18）**：开始一次生成后按 Home 键 → 已授予通知权限时，通知栏出现「后台生成」进度通知；完成 / 失败 / 取消后收到对应完成通知；回到应用状态与通知一致。Android 13+ 新装后第一次开始生成会弹一次系统通知权限框：允许则通知可见；拒绝则通知不可见但生成继续，且底部只出现一次带「去设置」的 SnackBar（再次生成不会重复弹权限框）。
5. **手机端布局**：设置页列表 → 详情、画廊长按菜单 / 多选 / 详情弹层、查看器手机顶栏 + 底部弹层菜单、编辑器 / 局部重绘页在 360–430dp 宽度下无 overflow、无 hover-only 操作；外接键盘之外的快捷键入口可忽略。
6. **桌面回归**：同一套代码在 Windows/macOS 上确认更新检查/安装与设置/画廊布局与改动前一致（本轮桌面分支未改），且桌面查看器/画廊不出现分享入口。

## 4. 功能矩阵（Android vs 桌面）

| 功能 | 桌面（Windows/macOS） | Android | 说明 |
| --- | --- | --- | --- |
| NovelAI 生图、画布、历史、参数复用 | ✓ | ✓ | 纯网络 + 本地存储 |
| 本地画廊、图库整理 | ✓ | ✓ | 默认图库目录为应用私有目录；"导入"是系统文件选择器多选图片复制进图库，ZIP 导出交给系统分享面板；手动保存生成图会镜像到系统相册（自动保存不会，原生侧按显示名去重）。手机端卡片长按出上下文菜单，inspector 为底部弹层，多选沿用桌面批量条；桌面右键菜单与三栏布局不变 |
| 在线画廊（Danbooru 等） | ✓ | ✓ | 纯网络 |
| ComfyUI 桥接 | ✓ | ✓ | 连接运行 ComfyUI 的局域网/远程机器 |
| 3D 编辑器 | ✓（WebView2） | ✓（Android System WebView） | WebView 不可用/被禁用的设备上会失败 |
| 视频播放 | ✓（media_kit） | ✓（系统原生播放器） | Android 没有 media_kit 原生库，使用 `video_player_android` |
| 标签库 / 标签百科 / 翻译补全 | ✓ | ✓ | SQLite 随包资源 + `sqlite3_flutter_libs` |
| 积木库多预览图画廊 | ✓ | ✓ | 桌面 2.3.4；手机编辑弹窗预览区收成缩略图条 + 全屏预览弹层，详情弹层内直接用同款画廊 |
| 跨行文本选择连续高亮 | ✓ | ✓ | 桌面 2.3.3；`themed_input`、Agent 输入框与翻译微调输入框共用，触屏同样生效 |
| 图库统一删除确认框 | ✓ | ✓ | 桌面 2.3.2；删除池与彻底删除共用 `GalleryDeleteDialog`，删除池节点显示待清理数量 |
| Agent 面板细节（默认收起/缓存保温状态/空回复提示） | ✓ | ✓ | 桌面 2.3.3–2.3.4；手机面板同样生效 |
| 云端放大 | ✓ | ✓ | NovelAI 接口 |
| 本地 / 高级放大（Real-ESRGAN、RTX Video、SeedVR2） | ✓ | ✗ | 依赖随包 `.exe` 和外部进程，Android 上入口隐藏/保持 inert |
| 设备端本地放大（ONNX Runtime，animevideov3 / general-x4v3） | — | ✓ | 随包 2.4 MB + 4.9 MB 模型 + `libonnxruntime.so`（arm64-v8a），Dart FFI 在应用进程内推理；入口在生成页画布与本地放大面板，面板可切换模型，见 1.4 |
| 本地语义检索 RAG（Python 运行时） | ✓ | ✗ | 依赖 Python/uv/PyTorch 外部进程。2026-11-10 决定不在 Android 复刻：运行时数 GB + 模型约 3 GB + 首次建库长时间占满 CPU/GPU，与手机竖屏主场景成本不匹配；入口继续隐藏（见 [mobile-adaptation.md](mobile-adaptation.md) §8.21） |
| NAI Agent（Node 运行时、MCP、Skill） | ✓ | ✓ | 桌面由安装器放置 `tools/nai-agent`；Android 把同一运行时（约 24.7 MB tar.gz）打进 assets，首用解压后由内嵌 libnode 启动。手机端全屏覆盖生成页，关闭会话释放对应 Worker、保留 Node；翻译微调在独立 Worker 中运行，见 1.4 |
| Krita 桥接 | ✓ | ✗ | 本地 WebSocket 服务 + 桌面插件端 |
| 外部桥接客户端（studio-bridge.exe） | ✓ | ✗ | 桌面可执行文件 |
| 应用内更新检查/安装 | ✓ | ✓ | 桌面：Windows 更新脚本 / macOS 核验。Android（G17）：检查 GitHub Release → 按设备 ABI 选 APK → 下载到 cache 并做大小/SHA256 校验 → 系统安装器（`REQUEST_INSTALL_PACKAGES` + 现有 FileProvider cache 路径）；未授权「未知来源」时跳到本应用系统设置页，返回后重试。**Android 读取的是本 fork（`RealityError`）的 Release**，因为上游只发布 Windows/macOS 资产；桌面仍查上游。**Release 必须上传 Flutter split-per-abi 命名的 APK**（`app-arm64-v8a-release.apk` 等），否则会提示有新版本但无包可装 |
| 分享图片到其它应用 | — | ✓ | G15：查看器「更多」、画廊长按菜单、生成结果长按菜单 → 系统分享面板；未保存的生成结果直接分享内存字节。桌面不显示该入口 |
| 接收系统分享进图生图 | — | ✓ | G16：其它应用 `ACTION_SEND image/*`（单张）→ 拷贝到 cache 后自动打开图生图；运行中与冷启动都能收到 |
| 生成中后台运行 / 完成通知 | — | ✓ | G10：`dataSync` 前台服务 + 通知 channel `wof_generation`，进度节流更新，完成/失败/取消各发一条通知；G18：Android 13+ 第一次开始生成时按需申请通知权限，拒绝后不再重复申请、只给一次「去设置」引导，通知仍不可见但生成继续。桌面应用无此机制 |
| 手机端页面布局（设置/画廊/查看器/编辑器） | 桌面布局不变 | ✓ | 按 `usesMobileLayout` 进入移动分支：设置列表→详情、画廊长按菜单/多选/详情弹层、查看器手机顶栏 + 底部弹层菜单、编辑器（局部重绘）底部工具条 + 参数/图层弹层；桌面布局与右键/hover 路径不改 |
| 系统托盘、多窗口/独立资源小窗 | ✓ | ✗ | Android 无对应插件能力 |
| Windows 系统代理 / GPU 诊断 | ✓ | ✗ | 注册表 / `nvidia-smi` 专属 |
| 系统字体列表/安装 | ✓ | ✗ | 原生字体通道仅桌面注册；Android 仍可使用随包字体 |
| 剪贴板与拖放 | ✓ | 部分 | `super_clipboard` / `super_drag_and_drop` 支持 Android；其它应用拖入、剪贴板图片格式与桌面存在差异 |
| 完成提示音 | ✓ | ✓ | `audioplayers` 播放应用内音效；Android 后台生成另有前台服务通知（见上一行），桌面无系统通知栏 |
| 键盘快捷键 | ✓ | 部分 | 触屏为主；外接键盘时部分快捷键可用 |

Android 上隐藏/降级的功能入口按 `desktop_platform.dart` 的能力 getter 判断，不改变桌面实现。

### 4.1 桌面 2.3.2–2.3.4 对齐（2.8.0）

2.8.0 把桌面 2.3.2–2.3.4 剩余的可移植增量补齐；桌面行为与上游一致，手机竖屏逐项验证：

- **积木多预览图画廊（2.3.4）**：积木编辑/检查器改用上游同款画廊组件（`blocks_gallery.dart`），支持多图预览、范围提示、缩放/翻页/重置与多选添加；手机端编辑弹窗把预览区收成 34dp 缩略图条 + 全屏预览弹层，详情弹层内直接用同款画廊。
- **图库统一删除确认框（2.3.2）**：删除池与彻底删除共用 `GalleryDeleteDialog`；桌面右键/查看器/资源窗口与手机长按菜单走同一确认流程，删除池节点显示待清理数量（`galleryTrashCountProvider` 订阅池变更自动刷新）。
- **跨行文本选择连续高亮（2.3.3）**：多行 `ThemedInput`、Agent 输入框与翻译微调输入框改用 `ContinuousTextSelection`，选择高亮不再出现行间细缝。
- **普通增强 64px 对齐（2.3.4）**：`NativeImageEnhance` 按官网 64 像素网格取整（例如 1216×832 @1.5× 变成 1856×1280），画布增强与 Agent 源图请求共用同一投影。
- **Agent 面板细节（2.3.3/2.3.4）**：面板默认收起（不跨启动保留展开状态）、缓存保温状态显示具体原因、空回复/图片超预算错误给出专用文案。
- **登录错误提示**：账号接口返回 404 时不再显示「未知错误」，改为「接口地址不可用」并提示检查 API 地址或改用官方账号登录。
- **Android 安装未知来源**：系统安装器要求授权时，应用内给出明确说明（`update_androidUnknownSources`），不再静默停在设置页。

## 5. 已知限制

1. **APK 很大**：`assets/databases` 约 419 MB，字体约 31 MB，翻译资源约 34 MB，加上其它资源总计约 500 MB。2026-11-08 的 x86_64 debug 包为 313,062,058 字节（Flutter 输出显示 298.6 MB），2026-11-09 本机最新 debug 产物为 **368,226,394 字节（约 351 MB，构建参数/ABI 与插件库集合不同会在该量级浮动）**，其中还带有部分插件的多 ABI 预编译 `.so`（onnxruntime / sqlite3 的 arm64、armeabi-v7a 库随包进入）；安装和首次启动都明显比桌面版慢。后续方向：AAB + Play Asset Delivery、按需下载语言/数据库资产、拆分内置数据；当前分支未做。
2. **签名密钥要保管好**：release 包已用项目专用密钥签名（§7.6），密钥存在 GitHub Secrets。
   2.4.0 及更早的包是临时 debug 签名，升到 2.5.0 需要卸载重装一次；此后同密钥版本可直接覆盖安装。
   换密钥或丢密钥都等于所有用户重装。
3. **没有 iOS 目标**：`ios/` 未生成；`isIOSPlatform` 只是给未来移植留的判断。
4. **存储范围**：Android 上默认图库/数据目录在应用私有空间，不能像桌面那样任意指定磁盘文件夹；导入外部图片走系统文件选择器（SAF）。手动保存生成图时会把副本镜像到系统相册 `Pictures/W.O.F NAI Studio`（MediaStore，Android 10+），自动保存的图片和图库里的其它文件仍只在应用私有目录；卸载应用会删除私有目录数据，重要作品请及时导出。
5. **移动端交互取舍**：桌面右键 / hover / 拖拽 / 快捷键在触屏上的等价入口是长按菜单、底部弹层、选择后操作和可见按钮；图片拖拽排序、框选、部分快捷键在手机上仍没有等价入口。这是移动端 UX 取舍，不是桌面功能回归，桌面代码路径未改。
6. **手机端布局现状**：设置页（列表 → 详情）、画廊（长按菜单 / 多选 / 详情弹层）、查看器、编辑器 / 局部重绘、导演工具与画布工具面板已完成移动分支；生成页范围内的触控目标已统一到 ≥48dp（含全屏提示词编辑器、翻译调整浮窗，见 `docs/mobile-adaptation.md` §8.13），画布底部工具条在手机上合并为单条（§8.16）。桌面布局、hover、右键路径保持不变。
7. **剪贴板/拖放差异**：Android 系统剪贴板与拖放对图片格式、文件 URI 的支持不如 Windows 宽松；Windows 专属的 PowerShell/System.Drawing 剪贴板路径只在桌面使用。
8. **后台限制**：生成中通过 `dataSync` 前台服务降低被系统回收的概率，但厂商省电策略、极端低电量模式或用户手动“强行停止”仍可能中断生成；应用没有托盘常驻，桌面式常驻行为不存在，长时间生成建议保持通知权限开启。
9. **通知权限按需申请、拒绝后不重复打扰**：Android 13+ 的 `POST_NOTIFICATIONS` 在第一次开始生成时经 `com.nailauncher/notifications` 申请（冷启动不弹窗）；拒绝一次后不再重复申请，只在首次拒绝后给一次带「去设置」按钮的 SnackBar，用户仍需在系统设置里手动开启后通知才可见（前台服务与生成本身继续运行）。Android 12 及以下没有该运行时权限，由系统通知开关决定，应用不做额外弹窗。
10. **应用内更新的工程前提**：Android 更新只从 GitHub Release 读取，**发布时必须上传 Flutter split-per-abi 命名的 APK**（当前只发 `app-arm64-v8a-release.apk`；x86_64 / armeabi-v7a 调试包不发布），否则客户端会检查到新版本但报“无可安装包”。Android 的更新源是本 fork `RealityError/W.O.F_NAI_Launcher_Android` 的 Release（上游没有 APK 资产），桌面仍走上游仓库；改名前的老地址由 GitHub 301 到新地址，旧版本客户端不受影响。首次安装更新还需要系统里的“安装未知应用”授权；下载失败后需要重新下载（当前 Android 链路不做断点续传）。当前没有应用商店渠道。
11. **分享入站只处理单张图片**：manifest 只注册了 `ACTION_SEND` + `image/*`，多图 / 非图片文件 / 纯文本分享不会进入应用；收到的图片会先拷到 cache，消费后删除。
12. **未知来源授权提示**：2.8.0 起，未授权“安装未知应用”时应用内会提示 `update_androidUnknownSources`（仍会跳到系统设置页，返回后需再次点「下载并安装」）。
13. **明文 HTTP**：manifest 开启 `usesCleartextTraffic` 以支持局域网 ComfyUI，正式发布前应评估是否收窄。
14. **构建所需外部资源**：首次构建要下载 NDK、Rust 目标、cargokit 预编译/编译产物，离线环境需要提前预热缓存。
15. **运行时验证范围**：2026-11-08 在 MuMu x86_64（API 36）做了启动、导航和功能入口 smoke test；2026-11-09 在本机 MuMu 上补做了登录、生图、画布与手机端布局回归（画布单条工具条实测见 `docs/mobile-adaptation.md` §8.16），全程无崩溃、无 overflow。2.5.0 用 CI 产物的 x86_64 包重装后同样启动正常，设置列表只剩手机端该有的 12 页（无「键盘快捷键」）。2.7.0 在 MuMu 上用 probe 验证了随包运行时解压、libnode 启动、Pi init → shutdown → 再次 init 的完整链路；仍未覆盖：真机（arm64）回归、应用内更新的完整安装闭环（模拟器侧已确认新旧包签名一致、可覆盖安装，尚未在真实网络下走完下载→安装器）、分享出站/入站与后台生成通知的手测。
16. **NAI Agent 运行时限制**：内嵌 libnode 在一个应用进程内只能启动一次，各会话在独立 Worker 中运行；翻译微调已开放。ChatGPT 登录、扩展/包管理、命令/技能清单需要额外 Node 进程或 OAuth 回环，手机端隐藏（`supportsNaiAgentExternalTools`）。MCP 的 stdio 服务器（`npx`）不可用。Agent 运行在应用进程内，进入后台可能被系统回收，长时间任务建议保持前台；并发会话真机内存尚待验证。
17. **NAI Agent 首次解压**：运行时约 24.7 MB / 1.67 万个文件（16,716 个），首次使用解压约 5–6 分钟（模拟器 debug；真机通常更快），app 启动后会在后台预热；解压期间打开 Agent 需要等待，之后走 `.runtime-version` 标记直接复用。
18. **设备端本地放大**：随包两个 ONNX 模型（animevideov3 / general-x4v3，2x/4x 分块，面板可切换），不覆盖桌面 realesrgan / SeedVR2 / RTX Video 的模型与管理界面；不下载外部运行时，桌面链路不变。更大模型与提速后端的可行性见 [local-upscale-advanced.md](local-upscale-advanced.md)。

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

### 6.10 应用内更新：检查到新版本但装不上 / 安装器不弹出

按顺序排查：

1. **Release 有没有 APK 资产**：GitHub Release 的 assets 里必须有 `.apk` 且文件名能看出 ABI（`app-arm64-v8a-release.apk` 等，或含 `universal`）。没有 APK 时客户端选中不到安装包，更新卡片会进入失败状态。Android 看的是 **fork `RealityError/W.O.F_NAI_Launcher_Android`** 的 Release——上游 `z15087716457-stack` 的 Release 只有 Windows/macOS 资产，桌面端才查那边。
2. **`REQUEST_INSTALL_PACKAGES` 是否在 manifest 里**：缺这行时 `canRequestPackageInstalls()` 恒为 false，只会反复跳到系统设置页。
3. **“安装未知应用”是否允许**：`设置 → 应用 → 本应用 → 安装未知应用`；Android 8+ 这个开关是按应用授权的。允许后返回应用，**再点一次「下载并安装」**。
4. **FileProvider 是否可用**：更新包下载在应用 cache 的 `nai_launcher_updates/`，由现有 `${applicationId}.fileprovider` 的 `cache-path` 暴露；不要新增第二个同 authority 的 provider，也不要改 provider authority。
5. **看日志**：`adb logcat -s flutter WofApkInstall AndroidRuntime`；原生安装异常会带 `WofApkInstall` tag。若是下载校验失败（大小/SHA256 不匹配），文件会被删除，重新下载即可；Android 链路没有断点续传。

### 6.11 后台生成通知不显示 / 生成被中断

- **通知不显示**：先确认系统通知权限。Android 13+ 新装后第一次开始生成会弹一次权限框；若当时点了「不允许」，之后不会重复弹框，可点拒绝后出现的那一次「去设置」SnackBar，或到「系统设置 → 应用 → 本应用 → 通知」手动打开（见第 5 节第 9 条）。未开启时前台服务仍运行，只是通知不可见。
- **通知栏有前台服务但生成停止**：检查是否被厂商省电策略/低电量模式限制，Android 14+ 对 `dataSync` 前台服务也有时长与启动时机限制；把应用加入电池优化白名单后重试。
- **日志**：`adb logcat -s flutter WofGenerationService WofNotifications AndroidRuntime`；Dart 侧 channel 失败会在 flutter 日志里出现 `GenerationForegroundService` / `NotificationPermission` 前缀的警告。
- 前台服务通知 channel 固定为 `wof_generation`，标题/文案由 Dart 传入；只改文案不需要动 Kotlin。

### 6.12 分享入口 / 接收分享异常

- **出站没有“分享”**：分享行只在 Android 显示（查看器「更多」、画廊长按菜单、生成结果长按菜单）；桌面视图本来就没有该行。若 Android 上也没有，确认应用是 Android 构建、且查看器动作集里包含 `shareImage`。
- **从其它应用分享进来没反应**：只接收单张 `image/*` 的 `ACTION_SEND`，多图/非图片/文本不支持（见第 5 节第 11 条）。冷启动分享会先落盘到 cache 的 `incoming_shares/`，等 Dart 启动后轮询消费；如果应用还没完成启动，图片会保留到下一次启动再处理。
- **分享失败**：`flutter` 日志里会有 `AndroidShare` 前缀的警告；`shareFile` 失败常见原因是源文件已被删除或 MIME 推断失败。

## 7. 发布签名（已落地，见 §7.6）

`release` 已改用项目专用密钥（不再是 `signingConfig debug` 占位），密钥存 GitHub Secrets，
CI 构建前还原。下面保留最初的方案草稿作为背景，实际配置以 §7.6 为准。

原计划：

1. 生成 keystore（一次性，妥善备份，丢失后无法覆盖升级）：

```powershell
keytool -genkeypair -v -keystore "$env:USERPROFILE\.android-keystores\wof-nai-studio.jks" `
  -alias wof-nai-studio -keyalg RSA -keysize 4096 -validity 10000
```

实际生成的是 RSA 2048 + alias `wof`，文件放在 `android/app/wof-release.jks`。

2. 在 `android/` 下新建 `key.properties`（**不要提交**；`android/.gitignore` 已忽略该文件名和 `*.jks` / `*.keystore`）：

```properties
storeFile=C:/Users/<user>/.android-keystores/wof-nai-studio.jks
storePassword=***
keyAlias=wof-nai-studio
keyPassword=***
```

实际值：`storeFile=app/wof-release.jks`、`keyAlias=wof`（相对 `android/` 目录）。

3. `android/app/build.gradle.kts` 读 `key.properties` 决定签名，缺文件时回退 debug 签名——
   已实现，见 §7.6。

4. 校验：`keytool -list -v -keystore <jks>`，以及 `apksigner verify --print-certs <apk>`。
   证书 SHA-256 应与 CI 日志里 `Verify APK signature` 步骤输出一致。
5. 密钥、口令只放在本机或 CI Secret 中，不写进仓库、提交信息或日志。

## 7.5 发布 Android APK（应用内更新的前提）

Android 客户端只认 fork `RealityError/W.O.F_NAI_Launcher_Android` 的 Release（见第 5 节第 10 条）。

**现在由 CI 自动完成**：`.github/workflows/release.yml` 的 `build-android` job 会在打 `v*` tag
时构建 split-per-abi APK（`--target-platform android-arm64`，只产出 arm64-v8a 包），产物与
Windows 一起进同一个 Release；`generate_release_metadata.ps1` 把 APK 写成 `android-apk` 资产
（带 size 与 SHA256），客户端据此判定「可应用内安装」。

正常发版只有两步：

1. 改 `pubspec.yaml` 的 `version`。**必须动 semver 段**（如 `2.4.0` → `2.5.0`），
   只加 `+build` 号不会触发更新——更新检查比较的是 `versionName`；`+build` 只影响
   `versionCode`（Android 覆盖安装要求递增）。
2. 提交并打 tag：`git tag v2.5.0 && git push origin v2.5.0`。`prepare` job 会校验
   tag 与 pubspec 版本一致，不一致直接失败。

需要人工复核的点：

- **文件名必须保留 ABI 字样**（`arm64-v8a`），`AndroidUpdateLogic.selectApkAsset` 靠文件名
  匹配设备 ABI；CI 直接上传 `flutter build apk --split-per-abi --target-platform android-arm64`
  的原生产物，不要改名。
- Release 起来后核对 `release_manifest.json` 里有一条 `type: "android-apk"`（`arm64-v8a`），
  且 `sha256` 与资产一致。
- 只做构建验证不想发版时，走 `android-build.yml`（PR / push 触发，只产 artifact）。

手工兜底（CI 不可用时）：

```powershell
flutter build apk --release --split-per-abi --target-platform android-arm64
gh release upload v2.5.0 -R RealityError/W.O.F_NAI_Launcher_Android `
  build/app/outputs/flutter-apk/app-*-release.apk --clobber
```

> 2026-11-09 已用应用自身的更新逻辑对线上 Release 做过端到端确认：三个 APK 均识别为
> `android-apk`、`supportsInAppInstall` 为 true、arm64 与 x86_64 分别选到对应包，
> 桌面分支仍选中上游的 Windows 包。2.7.0 起只发布 arm64-v8a 包（内嵌 libnode 与
> ONNX Runtime 只有 arm64 库），arm64 设备仍按文件名选中该资产。

## 7.6 签名密钥（覆盖安装的前提）

Android 只允许「同包名 + 同签名 + 不降 versionCode」的覆盖安装。`release` 构建原本用
`signingConfig debug`，而 CI runner 的 `~/.android/debug.keystore` 每次都是新生成的，
于是 CI 产物的签名和用户已装版本对不上，应用内更新会下载成功、却在安装阶段被系统以
`INSTALL_FAILED_UPDATE_INCOMPATIBLE` 拒绝。

现在的做法：

- 密钥：`android/app/wof-release.jks`（RSA 2048，alias `wof`），**不入库**
  （`android/.gitignore` 已忽略 `**/*.jks` 与 `key.properties`）。
- 库存：GitHub Secrets `ANDROID_KEYSTORE_BASE64`（base64 的 jks）、
  `ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`。
- 构建前由 CI 还原 jks 并写 `android/key.properties`：

```properties
storePassword=...
keyPassword=...
keyAlias=wof
storeFile=app/wof-release.jks
```

- `android/app/build.gradle.kts` 检测到 `key.properties` 就用它，否则回退 debug 签名，
  保证本地 `flutter build apk` 不受影响。`signingReport` 应显示
  `Variant: release → Store: android/app/wof-release.jks, Alias: wof`。
- `release.yml` 缺 secret 时直接失败（不带病发布）；`android-build.yml` 只做构建验证，
  缺 secret 时告警并退回 debug 签名。

轮换密钥要重新生成 jks、更新四个 secret，并让所有已安装用户卸载重装。
本地验证签名：`apksigner verify --print-certs <apk>`，证书 SHA-256 应与
`keytool -list -v -keystore android/app/wof-release.jks` 一致。

## 8. 相关文件与后续

新增/相关文件：

- `android/`：Android 工程；`android/README.md` 是同一目录的简版说明。
- `lib/core/utils/desktop_platform.dart`：平台能力 getter。
- `android/app/src/main/kotlin/com/wof/nai_launcher/`：
  - `MainActivity.kt`：`com.nailauncher/platform` 与 `com.nailauncher/generation` 通道（打开/分享/另存相册/打开目录/系统代理、分享入站、前台服务），并把权限结果转发给通知权限桥；
  - `GenerationForegroundService.kt`：G10 后台生成前台服务与通知（channel `wof_generation`）；
  - `ApkInstallHelper.kt`：G17 APK 安装桥（`com.nailauncher/apk_install`，FileProvider + `ACTION_VIEW` + 未知来源授权）；
  - `NotificationPermissionHelper.kt`：G18 通知权限桥（`com.nailauncher/notifications`，运行时申请 + 通知设置页跳转）。
- `lib/core/services/`：`android_update_service.dart` / `android_update_logic.dart`（G17 下载、校验、选包与版本比较）、`android_share_service.dart` / `android_share_intake.dart`（G15/G16）、`notification_permission_service.dart`（G18 通知权限与拒绝状态落盘）；`lib/core/utils/file_explorer_utils.dart` 里的 `PlatformFileChannel` 是现有 `com.nailauncher/platform` 通道的 Dart 封装。
- `lib/data/services/generation_foreground_service.dart` + `lib/presentation/wiring/generation_background_sync.dart`：G10 Dart 侧前台服务与生成状态联动（生成开始时触发 G18 权限检查）。
- `lib/presentation/wiring/notification_permission_wiring.dart`：G18 通知权限接线与「去设置」SnackBar。
- `lib/presentation/wiring/android_share_wiring.dart`：G16 分享入站接线。
- `lib/presentation/mobile/`、`lib/presentation/ui/settings/settings_mobile.dart`、`lib/presentation/screens/local_gallery/mobile_local_gallery.dart`：手机端布局地基与设置/画廊移动页。
- `scripts/build_android.ps1`：本地构建 + 预检。
- `.github/workflows/android-build.yml`：Linux CI 构建 release APK。
- `docs/android-port.md`：本文；手机端适配细节见 `docs/mobile-adaptation.md`。

后续工作（按优先级）：

1. 正式签名 + 发布流程（第 7 节），并决定分发渠道（GitHub Release APK / 应用商店 AAB）；**Release 必须同时上传 Android APK 资产**（G17 应用内更新的前提，命名按 split-per-abi），具体上传步骤见第 7.5 节；Android 客户端读的是本 fork 的 Release。
2. 资源瘦身与按需资产（AAB + Asset Delivery；数据库/语言包按需下载），控制 APK 体积。
3. Android 端真实设备/模拟器回归：先按 3.9 手测应用内更新、分享出站/入站、后台生成通知、手机端布局；再在**有网络且提供 NovelAI 凭据**的环境补做登录、生图、图片保存/MediaStore 相册镜像的端到端验证，最后覆盖图库导入、ComfyUI 连接、3D 编辑器 WebView、剪贴板/拖放。
4. 移动端交互收尾：生成页范围内的触控目标已统一到 ≥48dp，画布工具条已合并为单条；剩余分类选择 / 批量元数据等次要桌面对话框未做手机重排。`update_androidUnknownSources` 提示文案与 ARB key 一起补。
5. 后台策略与通知：通知权限已在首次生成时按需申请（拒绝后不重复申请，只给一次「去设置」引导）；继续观察前台服务在厂商省电策略下的存活情况。

维护约定：修改 getter 名称或 Android 能力边界时同步更新本文第 2、4 节；改 `android/` 或构建脚本时确认 CI 触发路径仍覆盖。
