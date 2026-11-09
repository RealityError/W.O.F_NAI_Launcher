# 生成页（Android）与桌面版差距清单

基线：桌面版「生成」页与手机端共用同一份 UI 代码，手机端只是另一套布局
（`_GenMobileLayout`，[gen_page.dart:383](../lib/presentation/ui/gen/gen_page.dart#L383-L466)）。
所以本清单不是「功能被删」，而是**触屏没有入口的桌面交互**和**依赖本机算力/本机软件的桌面功能**。

状态：⬜ 未做 · 🟡 进行中 · ✅ 完成 · ⛔ 不做（桌面专属）
量级：S ≤ 0.5 天 · M ≈ 1–2 天 · L ≥ 3 天

## 0. 现成可复用（决定成本的关键）

- 手机上下文菜单工具已存在：`showMobileContextMenu` / `MobileContextMenuRegion`
  （[mobile_context_menu.dart](../lib/presentation/mobile/mobile_context_menu.dart)），
  图库已经在用长按 → 底部菜单（[local_image_context_menu.dart:180](../lib/presentation/widgets/gallery/local_image_context_menu.dart#L180-L230)）。
  生成页的右键菜单只要把同样的动作拍平成 `MobileMenuItem` 即可，桌面右键路径不动。
- 触控目标常量 `kMobileMinTouchTarget = 48`
  （[mobile_touch.dart](../lib/presentation/mobile/mobile_touch.dart)）、按压态 `MobileTapCard`、
  `mobile_sheet.dart` 底部弹层、`_MobileOverlayPanel`（生成页浮层）都可直接复用。

## 1. 生成页：触屏入口缺失（P0）

| ID | 事项 | 现状 | 目标 | 涉及文件 | 量级 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| G1 | 画布图片长按菜单 | 图片菜单只绑了右键（`onSecondaryTapDown`，[gen_canvas.dart:645](../lib/presentation/ui/gen/gen_canvas.dart#L645-L656)），触屏无入口；菜单动作在 [generation_canvas_menu.dart:80-220](../lib/presentation/wiring/generation_canvas_menu.dart#L80-L220) | 长按图片 → `showMobileContextMenu`，动作与右键一致；补齐**删除单张 / 发送到风格参考 / 发送到精准参考 / 保存到精准参考库**（其余项工具条已有） | `gen_canvas.dart`、`generation_canvas_menu.dart` | S | ✅ |
| G2 | 历史批次菜单 | 批次菜单只绑右键（[gen_history.dart:616](../lib/presentation/ui/gen/gen_history.dart#L616-L618)） | 长按批次或点批次右上「…」→ 同一套菜单：查看大图、复制、收藏、发送到图生图 / 风格参考 / 精准参考、保存整批 | `gen_history.dart` | S | ✅（长按） |
| G3 | 批次封面悬停按钮 | 复核后：批次封面没有 hover 专属操作按钮，hover 只改透明度（[gen_history.dart:639-643](../lib/presentation/ui/gen/gen_history.dart#L639-L643)）；原清单引用的 `141-155` 行其实是右键菜单项 | 无需常显按钮；保存 / 复制等动作走 G2 长按菜单 | — | S | ✅（复核为不适用） |
| G4 | 触控目标 48dp | 历史底部一排图标、画布浮动按钮、头部胶囊、参数条多为 24–32dp | 生成页范围内可点区域 ≥ 48dp（视觉可维持 32dp） | `gen_history.dart`、`gen_canvas.dart`、`gen_params.dart`、`gen_header.dart` | M | ✅（见 §8 第二批） |
| G5 | 验收已有手机适配 | 提示词全屏编辑器、翻译调整浮层、查看器主界面已有 `usesMobileLayout` 分支，未系统验收 | 360×640 逐项走查无溢出、可操作，补 widget 测试 | `gen_prompt.dart`、`translation_adjust_window.dart`、`viewer_page.dart` | S | ✅ |

## 2. Android 缺失 / 桌面专属功能（P1–P2）

| ID | 事项 | 现状 | 目标 | 涉及文件 | 量级 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| G6 | 放大面板「本地」卡片 | Android 上 disabled（`enabled: windows`，[tools_generation_wiring.dart:144-158](../lib/presentation/wiring/tools_generation_wiring.dart#L144-L158)） | 手机端直接隐藏本地卡片并提示「可用 NovelAI 云端超分」，避免死按钮 | `tools_generation_wiring.dart`、`tools_sheets.dart` | S | ✅ |
| G7 | 增强面板「本地」因子 | 已按平台排除（[tools_generation_wiring.dart:59-65](../lib/presentation/wiring/tools_generation_wiring.dart#L59-L65)） | 无需改动，仅记录 | — | — | ✅ |
| G8 | 本地超分引擎（NCNN / SeedVR2 / RTX Video） | 随包 Windows 可执行文件，Android 无实现（另一条产品线，非移植项） | 若要做：Android 侧 ONNX/NCNN 推理或改走 ComfyUI 后端 | 新立项 | L | ⛔ |
| G9 | Krita 桥接 / 打开文件夹 / 发送到 Krita | 桥接图标连本机 socket（[gen_prompt.dart:413-452](../lib/presentation/ui/gen/gen_prompt.dart#L413-L452)）；「打开文件夹」是桌面文件管理 | Android 隐藏这三项，不留必失败入口 | `gen_prompt.dart`、`generation_canvas_menu.dart` | S | ✅ |
| G10 | 生成中切后台 | 无前台服务/通知，系统回收进程会中断生成 | 前台服务 + 完成通知（可选：保持后台持续生成） | Android 原生 + `image_generation_provider` | M | ✅ |

## 3. 生成页延伸目标页（P1–P2）

| ID | 事项 | 现状 | 目标 | 涉及文件 | 量级 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| G11 | 资源库入口 + 全屏化（原「浮动资源小窗」） | 复核：手机端曾无独立入口，入口藏在编辑浮层里，点开是**桌面式浮窗**（可拖拽/缩放、桌面边框）。现已按方案 A 完成：编辑浮层标题栏新增「库」按钮（图库 / 块库 / 风格库 / 精准参考库），前三者推出手机全屏库页（搜索 + 44dp 点按行，点块插入当前提示词、点缩略图加入生图页），图库直接跳现有图库页；桌面浮窗路径完全未改动 | `resource_window_wiring.dart`、`mobile_resource_library.dart`、`floating_resource_window.dart`、`gen_page.dart` | A≈M | ✅ |
| G12 | 图片查看器收尾 | 主界面已手机化，底部胶片条 / 更多菜单未适配（更多菜单可复用 `showMobileContextMenu`） | 胶片条横向可滑；更多菜单用底部弹层 | `viewer_page.dart`、`viewer_stage.dart`、`generation_viewer_wiring.dart` | M | ✅ |
| G13 | 编辑图片页 | `tools_editor.dart` 无手机分支（工具竖栏 + 快捷键提示被裁） | 画布优先 + 底部工具条 + 参数弹层（同导演工具方案 A） | `tools_editor.dart` | L | ✅ |
| G14 | 局部重绘 / 蒙版页 | 同上，桌面布局 | 同上 | 蒙版编辑页（`tools_editor.dart` 共用手机布局 + `image_editor_screen` 接线） | L | ✅ |

## 4. 系统集成（可选项，P2）

| ID | 事项 | 目标 | 量级 | 状态 |
| --- | --- | --- | --- | --- |
| G15 | 分享图片到其他 App | 已用原生 `ACTION_SEND`（`AndroidShareService` / `PlatformFileChannel.shareFile`），入口：查看器「更多」、画廊长按、生成结果长按，替代桌面「复制/拖出」 | M | ✅ |
| G16 | 从系统分享接收图片 | manifest 增加 `ACTION_SEND` + `image/*`，直接进 img2img / 参考图 | M | ✅ |
| G17 | 应用内 APK 更新 | Android 独立链路：GitHub Release 选包 → cache 下载+SHA256 → `FileProvider` + 系统安装器；桌面更新器原样 | M | ✅ |

## 5. 明确不做（桌面专属）

拖拽导入 / 拖出到文件夹、拖拽调栏宽、右键菜单、键盘快捷键（Ctrl+Enter / Ctrl+V / Ctrl+0）、
系统托盘与开机自启、窗口置顶 / 多窗口看图、输出目录与「打开所在文件夹」、
Windows 剪贴板历史粘贴、随包本地超分可执行文件。

## 6. 建议顺序

1. **第一批（S，约 0.5–1 天，建议先做）**：G1 画布长按菜单、G2 历史批次菜单、G3 悬停按钮常显、
   G6 隐藏本地超分卡片、G9 隐藏 Krita 桥接 —— 把「触屏点不出来」和「死按钮」清掉。✅ 已完成（见 §8）
2. **第二批（M，约 1–2 天）**：G12 查看器收尾、G4 触控目标、G5 走查验收（G11 已提前完成，见 §8）。✅ 已完成
3. **第三批（L）**：G13 编辑图片页手机化、G14 局部重绘页手机化、G10 后台生成、G15–G17 系统集成。✅ 已完成（G17 见 [android-port.md](android-port.md)）
4. **另立项**：G8 本地超分引擎（Android 推理，不是移植工作量级）。

## 7. 验收口径

- `flutter analyze --no-pub` 干净；改动路径补对应 widget 测试（现有 `test/presentation/ui/gen`、`tools`）。
- 360×640 竖屏无 overflow；桌面三栏布局与 golden 不变。
- 真机（MuMu x86_64 / arm64）手测通过后再交付 APK。

## 8. 执行记录

### 2026-11-09 · 第一批（G1 / G2 / G3 / G6 / G9）

- **G1 画布图片长按菜单**：`GenCanvasMenuScope` 增加 `onOpenMobile`（[gen_canvas.dart](../lib/presentation/ui/gen/gen_canvas.dart)），
  图块在手机布局下长按触发；接线方 `openGenerationCanvasMenuMobile`
  （[generation_canvas_menu.dart](../lib/presentation/wiring/generation_canvas_menu.dart)）用 `showMobileContextMenu`
  拍平右键动作：保存 / 复制 / 详情 / 删除 / 发送到图生图 / 风格参考 / 精准参考 / 保存到精准参考库；
  「在资源管理器中显示」等桌面文件管理项不出现。桌面右键路径未改动。
- **G2 历史批次长按菜单**：`_BatchItem` 增加 `onLongPress`（仅手机布局传入），`_menuMobile`
  复用桌面右键同源动作（查看大图 / 保存整批 / 复制 / 收藏 / 发送到图生图 / 风格参考 / 精准参考 / 删除）；
  桌面仍是右键。
- **G3 复核为不适用**：批次封面没有 hover 专属按钮，hover 只改透明度；保存 / 复制走 G2 长按菜单。
- **G6 放大面板隐藏「本地」**：`toolsUpscaleView` 在 Android/iOS 固定云端后端并只渲染 NovelAI 卡片
  （纯函数 `toolsUpscaleBackends`，桌面仍双卡片）；打开放大面板时把后端固定回 `novelai`，
  避免桌面遗留的 `local` 设置直接命中「平台不支持」。
- **G9 Krita / 打开文件夹**：复核确认桥接图标只存在于桌面提示词模块（`GenPromptModule` 仅桌面左栏挂载，
  手机端不渲染），仍加 `usesMobileLayout` 守卫防未来复用；「打开文件夹 / 发送到 Krita」只在桌面右键菜单，
  手机长按菜单不包含。

验证：`flutter analyze --no-pub` 干净；新增 `test/presentation/ui/gen/gen_mobile_layout_test.dart`
（画布长按入口、批次长按菜单、手机不渲染桥接图标）与 `test/presentation/wiring/tools_upscale_mobile_test.dart`
（后端卡片按平台取舍）；`test/presentation/ui/gen` + `test/presentation/ui/tools` 541 项全过；
生成接线核心回归 7 个文件全过。

### 2026-11-09 · G11 手机资源库（方案 A）

- **入口**：编辑浮层标题栏（`_MobileOverlayPanel`）新增「库」按钮，底部菜单列四类资源；
  桌面三栏没有该按钮，原有「资源窗口」工具栏按钮/快捷键照旧开桌面浮窗。
- **全屏页**：`ResourceWindowOpener.open` 在 `usesMobileLayout` 下不再走浮窗——块库/风格库/精准参考库
  开一个**不落盘**的临时窗口（`open(persist: false)`），用 `showGeneralDialog` 推出
  `MobileResourceLibraryPage`（[mobile_resource_library.dart](../lib/presentation/wiring/mobile_resource_library.dart)）；
  系统返回键/关闭按钮退出，退出即回收临时窗口。图库类直接 `go(localGallery)`。
- **手机外观与操作**：`FloatingResourceWindow` 增加手机分支——关闭按钮 + 标题 + 数量 + 「轻点即插入」提示、
  42dp 搜索框、块行 44dp、参考图网格 120dp；点块走 `BlocksActions.insert`（插入当前提示词），
  点缩略图走 `refsEntryDropActionsProvider.drop`（加入生图页）。手机页不渲染拖拽源和右下缩放角。
- **桌面不变**：浮窗宿主在手机布局下直接返回空（窗口只由全屏页渲染），桌面分支代码原样保留。
- 新增文案 `floating_mobileTapHint`（zh/en/ja/ko，zh_TW 由 `tool/l10n` 重新生成）。

验证：`flutter analyze --no-pub` 干净；`test/presentation/ui/gen`、浮窗宿主/数据源/资源窗口
与生成接线回归共 600+ 项全过；新增 `test/presentation/wiring/mobile_resource_library_test.dart`
（全屏外观、无缩放角/拖拽、44dp 点按行）、浮动窗口 provider 的「临时窗口不落盘」用例、
`gen_mobile_layout_test.dart` 的「库入口 + 四类资源菜单」用例、宿主「手机不画浮窗」用例。

### 2026-11-09 · 第二批（G12 / G4 / G5）

- **G12 查看器收尾**：手机全屏 chrome 不再自动隐藏（否则没有退出入口），点画面切换 chrome；
  底部胶片条手机端横向可滑、淡出边收窄到 24dp；长按图片取代右键（更多菜单走底部弹层）；
  菜单行高 48dp、手机不画键帽；全屏信息条改用手机版（信息 / 退出两个 44dp 图标）。
  桌面 popover、键帽、悬停胶片条与窗口按钮避让一行未改。
- **G4 触控目标 48dp**：新增 `GenTouchTarget`（桌面直接返回 child，无额外 RenderObject），
  生成页 `GenIb` / `GenFloatButton` / `GenTab` / `GenSliderRow`、历史栏（40→56，图标 48）、
  头部胶囊（手机外框 50、描边内 48）、参数条（种子行 56、下拉 48、抽屉标题 56）、
  提示词工具条（28→48）、生成按钮（40→48）全部 ≥48；手机顶栏隐藏 "Model" 小标签恢复单行
  （实测 59dp，改前 113dp），Turbo 命中区 48×48（视觉 22）；全屏提示词编辑器头部手机端改两行
  （关闭 / 清除 48×48，正负向切换加 48 高透明命中层）；翻译调整浮窗的收起 / 关闭 / 发送 /
  快捷 chip / 引用清除 / undo 全部 ≥48。桌面尺寸由测试守卫用例锁定不变。
- **G5 360×640 走查**：新增生成页手机走查 4 例（主页、编辑浮层→工具菜单→全屏编辑器、
  历史浮层 + 长按菜单、参数抽屉滚动）、翻译浮窗 3 例、查看器 360×640 1 例，
  全程 `takeException() == null`，未发现 overflow。

验证：`flutter analyze --no-pub` 干净；`test/presentation/ui/gen` 393 项、tools 171 项、
viewer 全目录通过；桌面 golden 与尺寸守卫用例（header 37、gen-pin 32×30、无 gen-mobile-editor 等）不变。

### 2026-11-09 · 第三批（G13 / G14 / G10 / G15 / G16 / G17）

- **G13 编辑图片页**：`tools_editor.dart` 新增手机布局（方案 A）——顶栏返回/标题/撤销/重做/下载，
  画布优先，底部应用条（参数、面板、应用），底部横滑工具条（点一下直接切工具，快捷键字母帽不出现），
  参数与图层面板改为底部弹层（工具条在弹层下保持可点）；`ToolsEditorSide` 支持整宽无左边框。
  桌面三栏布局原样（新增手机测试 7 例，tools 全目录 171 项全过）。
- **G14 局部重绘 / 蒙版页**：复用同一手机布局；参数弹层含笔刷大小、方笔、蒙版外观
  （颜色 / 不透明度 / 图案），图层面板含重绘强度、输出设置、图层；应用下拉在手机上是底部弹层
  （仅应用 / 应用并生成）。真实 `ImageEditorScreen(inpaint)` 手机 5 例（含手指在画布上涂蒙版）。
- **G10 后台生成**：Dart `GenerationBackgroundSync` 监听生成状态 → `com.nailauncher/generation`
  通道；Kotlin `GenerationForegroundService` 用 dataSync 前台服务保持进程，通知栏显示文案/进度，
  完成 / 失败 / 取消各发一条通知（点按回 App），通知权限被拒也不崩；6 例状态迁移测试。
- **G15 分享出站**：查看器「更多」、手机画廊长按菜单、生成结果长按菜单
  → 系统分享面板（`AndroidShareService` / `PlatformFileChannel.shareFile`，Android-only 动作集合，
  UI 不 import wiring）；桌面不出现分享动作。
- **G16 接收系统分享**：MainActivity 处理 `ACTION_SEND image/*`（onCreate + onNewIntent，
  content:// 拷到 cache），`getSharedImage` 拉取 + `shareImageReceived` 前台信号；
  Dart 复用 `ImageWorkflowLauncher.openImageToImage` 直接进 img2img；12 例 channel mock 测试。
- **G17 应用内 APK 更新**：Android 独立链路——GitHub Release 选 ABI 匹配 APK → cache 下载
  （`.part` + rename、大小/SHA256 校验）→ `FileProvider` + 系统安装器；未授权「安装未知应用」
  时跳系统设置页，返回后重试；桌面更新器行为不变；22 例纯逻辑 / 通道 mock 测试。

验证：`flutter analyze --no-pub` 全项目干净；全量 `flutter test --no-pub` 通过（最终验收记录见
[android-port.md](android-port.md)）；`flutter build apk --debug --target-platform android-x64`
编译通过（Kotlin + manifest 校验）。真机手测项（更新 / 分享 / 后台生成）见 android-port.md。
