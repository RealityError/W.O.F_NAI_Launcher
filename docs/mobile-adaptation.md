# 手机端适配方案（第一阶段：地基 + P0 三页）

本文档是 Android 手机端适配的执行方案。目标平台：**Android 手机竖屏（360–430dp）**，桌面端（Windows / macOS）行为保持不变。

## 1. 为什么这样做

现状：

- 应用本身是桌面优先：生成页三栏、设置页双栏、大量 hover / 右键 / 快捷键 / 拖拽交互；
- 已有的移动基础：`MobileShell` 底部导航、窗口 chrome 抽象（`WindowChromeScope`）、`design_tokens.dart` 里的 600/900/1200 断点（但未被统一使用）、Android 平台能力 getter（`isMobilePlatform` / `supports*`）、Android 文件/图库/分享通道；
- 直接改桌面布局风险大：桌面有 900+ 测试文件与 Windows 打包 CI，视觉回归成本高。

因此采用 **"桌面路径不动 + 移动端独立布局分支 + 内容/状态复用"** 的策略。

## 2. 三条硬约束

1. **桌面代码路径不动**：移动端布局通过 `if (usesMobileLayout) → MobileXxxLayout` 分支进入；现有桌面布局与视觉不改。桌面窗口最小宽度 800，`usesMobileLayout` 仅由平台判定（Android=true），不按窗口宽度改变桌面行为。
2. **复用业务层**：Provider / Service / 状态 / 数据模型 / 大部分内容 widget 不改；只新增布局外壳与触屏交互。
3. **交互双入口**：桌面右键 ↔ 手机长按；桌面 hover ↔ 手机 pressed；桌面拖拽 ↔ 手机"选择后操作/系统选择器"；快捷键入口在移动端隐藏，操作改为可见按钮。

## 3. 移动端地基（`lib/presentation/mobile/`）

### 3.1 断点与平台

`mobile_breakpoints.dart`

```dart
const double kMobileBreakpoint = 600;   // 与 design_tokens.breakpointMobile 对齐
const double kTabletBreakpoint = 900;   // 与 design_tokens.breakpointTablet 对齐
bool get usesMobileLayout => isMobilePlatform; // Android = true，桌面恒 false
FormFactor formFactorOf(BuildContext context); // phone / tablet / desktop（按宽度）
```

### 3.2 页面骨架

`mobile_scaffold.dart`

```dart
class MobilePageScaffold extends StatelessWidget {
  const MobilePageScaffold({
    required this.title,
    required this.child,
    this.actions,        // 右上操作按钮
    this.bottomBar,      // 底部固定操作区（自动处理安全区）
    this.onBack,         // 默认 Navigator.maybePop
    this.showBack = true,
    this.padding,
  });
}
```

- 顶部 56dp 标题栏 + 状态栏 SafeArea，返回按钮，标题与操作位；
- `bottomBar` 自动包 SafeArea + 键盘 inset（`viewInsets.bottom`）；
- 统一 `PopScope`（Android 返回键 = 页面返回）。

### 3.3 底部弹层

`mobile_sheet.dart`

```dart
Future<T?> showMobileSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  double heightFactor = 0.9,   // 占屏高比例
  bool dismissible = true,
});
```

- 圆角顶部 + 拖拽手柄 + 安全区；`isScrollControlled = true`；
- 用于：设置项编辑、生成页参数/提示词编辑器、图库筛选、上下文菜单。

### 3.4 上下文菜单（右键/长按统一）

`mobile_context_menu.dart`

```dart
class MobileMenuItem {
  const MobileMenuItem({required this.label, this.icon, this.onTap, this.destructive = false});
}

Future<void> showMobileContextMenu(BuildContext context, {String? title, required List<MobileMenuItem> items});

class MobileContextMenuRegion extends StatelessWidget {
  const MobileContextMenuRegion({required this.child, required this.items, this.title});
}
```

- 移动端：长按弹出 bottom sheet 菜单；
- 桌面端：不改变现有右键菜单（`MobileContextMenuRegion` 只在移动分支使用）。

### 3.5 触屏提示与反馈

- `Tooltip`：移动端统一改为长按触发（在 `app.dart` 的移动主题里设置 `TooltipThemeData(triggerMode: TooltipTriggerMode.longPress)`），覆盖现有 293 处 Tooltip，不改调用点；
- `mobile_touch.dart`：`TouchTapCard`（点击态反馈）、`minimumTouchTarget` 常量（≥48dp）、`hapticTap()`。

### 3.6 列表/设置行

`mobile_list.dart`

```dart
class MobileSectionHeader;         // 分组标题（个人/创作/智能…）
class MobileListTile;              // 图标 + 标题 + 副标题 + 右侧箭头/值
```

## 4. P0 三页方案

### 4.1 设置页（`lib/presentation/ui/settings/`）

现状：双栏（230dp 侧边栏 + 内容区）。手机目标：

- 拆为 **导航页 → 详情页**：
  - 导航页：按分组（个人 / 创作 / 智能 / 关于）列出 `SettingsPageId` 各项（图标+标题+副标题+当前值），顶部提供搜索入口；
  - 点击 → `Navigator.push` 详情页：`MobilePageScaffold(title: 页面标题)` + 原有内容区（复用 `SettingsViewData.page` 与 `SettingsActions`）；
  - 搜索命中 → 直接进入对应详情页并高亮/滚动到目标项（复用现有 search hits 数据）。
- 手机隐藏项继续沿用 capability 判断（Agent/RAG/本地放大/网络等），不重复实现。
- 桌面 `SettingsPage` 双栏保持原样。

### 4.2 生成页（`lib/presentation/ui/gen/`）

现状：左栏（提示词/参数/生成条）+ 画布 + 历史栏三栏。手机目标：

- **画布优先**：
  - 顶部紧凑 `GenHeader`（模型/配额）保持单行；编辑提示词、最近生成入口在底部生成条两侧（不再占顶栏）；
  - 「解除相机锁定」仅在锁定状态临时出现在顶栏；
  - 主体 = 画布（`GenCanvas`，含空白欢迎态）；
  - 底部固定：`GenParamStrip`（参数摘要，点开参数抽屉）+ `GenGenerateBar`（`leading` = 提示词编辑、`trailing` = 最近生成）；
  - 编辑提示词 / 最近生成都在 **页面内全屏浮层**：内容是 `GenEditorColumn(collapsible: false)` / `GenHistoryPanel`；不用 Navigator overlay，避免丢失 `GenScope`；
  - 画布手势：单指拖拽平移、双指缩放；「锁定画布相机」开启时所有手动相机输入被禁用（桌面同一设置），此时顶栏会出现解锁按钮。
- 复用 `GenHost` / `GenScope` / `GenActions` / 所有模块 widget，不改状态逻辑；
- 桌面 `_GenLayoutRow` 三栏与拖拽改宽保持原样。

### 4.3 画廊（`lib/presentation/screens/local_gallery/` + `lib/presentation/widgets/gallery/`）

现状：工具栏已做窄屏修复，但卡片交互是桌面右键、inspector 是固定侧栏。手机目标：

- 网格/列表切换保留；筛选栏折叠为可横向滚动的 chips；
- 卡片：点击=查看（现有 viewer），**长按=上下文菜单**（详情信息、复制 prompt/seed、分享、保存到相册、删除、上移/下移等，复用现有 action），多选模式保留（工具栏按钮进入，选择态底部操作条）；
- inspector（详情面板）→ 右侧抽屉或底部弹层，内容复用现有 inspector；
- 导入图片 / 打开文件夹 / 分享使用已有 Android 通道；空态与错误态沿用现有文案。

## 5. 验收标准（每页）

1. 360dp 竖屏 debug 模式 **0 个 RenderFlex overflow**；
2. 可返回（返回键 + 左上返回），无死路；
3. 滚动正常，键盘弹出不遮挡输入；
4. 所有可点击元素 ≥ 44dp，无 hover-only 操作、无必须右键才能触发的功能；
5. 桌面端 `flutter analyze` 无新增问题，现有测试通过（桌面布局代码零改动或仅新增分支）；
6. CI：新增 360dp widget smoke test；PR 的 Windows 全量测试保持通过。

## 6. 后续阶段（本阶段之后）

- **Phase 1（本阶段）**：地基 + 设置 / 生成 / 画廊；
- **Phase 2 浏览类页面**：在线画廊、标签 Wiki、提示词块库、Vibe 库、精准参考库、统计、模型与接口、风格探索、标签库——统一"列表→详情"模式；
- **Phase 3 编辑器类**（可行性已评估，全部可移植）：
  - 图像编辑器（1.56 万行，自绘画布已支持 `onScale` 手势，难度中，3–5 天）；
  - 画布/Director（0.68 万行，侧栏改抽屉 + pinch 缩放，难度中，2–4 天）；
  - 3D 编辑器（WebView + three.js OrbitControls，触摸原生可用，难度易，1–2 天）；
  - Agent 面板（全屏页/抽屉，难度中，2–3 天）；
  - 图片查看器/对比/幻灯片（手势缩放 + 滑动翻页，难度易，1–2 天）；
- **Phase 4 收尾**：全量走查、性能/内存、横竖屏、返回栈、文档与 CI 固化。

## 7. 风险与取舍

- 移动端接受交互简化（右键→长按、拖拽→选择后操作、多栏→单列/抽屉），功能入口与数据保持一致；
- 平板/横屏不在本阶段验收范围，不锁死方向（避免折叠屏/平板异常）；
- 设置页/生成页属于高耦合页面，改造时以"新增移动布局 + 复用内容组件"为准，禁止重写业务状态。

## 8. 第一阶段实现状态（已完成）

### 8.1 已落地

| 模块 | 文件 | 说明 |
| --- | --- | --- |
| 移动端地基 | `lib/presentation/mobile/` | `mobile_breakpoints`（usesMobileLayout）、`MobilePageScaffold`、`showMobileSheet`、`MobileContextMenuRegion`/`showMobileContextMenu`、`MobileSectionHeader`/`MobileListTile`、`MobileTapCard`、`mobileAdaptiveTheme`（Tooltip 长按） |
| 生成页 | `lib/presentation/ui/gen/gen_page.dart`、`gen_generate.dart` | `usesMobileLayout` → `_GenMobileLayout`：单行顶栏 + 画布优先 + 参数条 + 生成条；编辑提示词 / 最近生成锚定在生成条两侧，内容为页面内浮层；桌面三栏 `_GenLayoutRow` 原样保留 |
| 导演工具 | `lib/presentation/ui/tools/tools_director.dart` | `_MobileDirectorLayout`：不经过 `WindowHeader` 的紧凑顶栏（返回/标题/面板/Anlas）+ 横向滚动的舞台 + 右栏浮层；桌面三栏原样保留 |
| 设置页 | `lib/presentation/ui/settings/settings_mobile.dart` + 内容页窄屏分支 | 分组列表 → 详情页（复用桌面 `_pageOf` 内容）、搜索/深链/锚点、撤销浮条、详情页操作位；桌面双栏原样保留 |
| 画廊 | `lib/presentation/screens/local_gallery/mobile_local_gallery.dart` + 画廊组件移动分支 | 移动工具栏/范围浏览/筛选/排序弹层、卡片长按动作菜单（bottom sheet）、inspector bottom sheet、多选批量条、回收站操作；桌面三栏与右键菜单原样保留 |
| 主题 | `lib/app.dart`、`splash/app_bootstrap.dart` | 移动端套用 `mobileAdaptiveTheme`（Tooltip 长按、触摸目标）；桌面主题不变 |
| Android 系统代理 | `lib/core/network/android_system_proxy.dart`、`proxy_service.dart`、`main.dart` + `MainActivity.kt#getSystemProxy` | 启动时读取 Android 全局 `http_proxy` 并注入 `HttpOverrides`；回环/局域网地址直连。解决模拟器/真机在需要代理的网络下登录、生图超时 |
| 文档 | 本文 | 方案、组件 API、验收标准、后续阶段 |

### 8.2 验证结果

- `dart analyze lib`：No issues；
- 新增移动测试：
  - `test/presentation/mobile/mobile_components_test.dart` 4 例（360dp 骨架/弹层/长按菜单/断点常量）；
  - `test/presentation/ui/gen/gen_mobile_layout_test.dart` 5 例（画布优先且入口不在顶栏、编辑浮层开关、最近生成浮层标题/副标题、锁相机时顶栏出现解锁入口、未锁定不显示）；
  - `test/presentation/ui/tools/tools_director_mobile_test.dart` 2 例（360dp 不溢出且右栏不内联、右栏浮层开关）；
  - `test/presentation/ui/settings/mobile/` 16 例（列表/详情/返回/搜索锚点/深链/撤销/13 页滚动无 overflow）；
  - `test/presentation/widgets/gallery/mobile/` 9 例（长按菜单/多选/详情面板/筛选排序弹层/时间线语义）；
- 生成页 UI 回归：`test/presentation/ui/gen` 376 例全部通过（测试宿主统一注入锁相机替身，不依赖 Hive）；导演工具 `test/presentation/ui/tools` 159 例（含 golden）通过；
- 桌面回归：设置页 380 例、画廊 224 例全部通过；桌面布局代码路径未改动；
- MuMu x86_64（Android 15，360dp 宽）实机验证：登录 → 生成页手机布局（画布/顶栏编辑与历史入口/参数条/生成条）→ 长按画廊卡片弹出动作菜单 → 设置列表 → 概览详情页返回，全程无 overflow / 崩溃；Android 系统代理生效后网络检查与登录成功。

### 8.4 首轮反馈修复

1. **画布被遮挡**：编辑提示词 / 历史记录原本是悬浮在画布上的圆形按钮，会压住画布工具条与图片；先收进头部 `Wrap`，再按二轮反馈下移到生成条两侧，顶栏恢复单行（见 8.5）。桌面端不传 `actions` / `leading` / `trailing`，行为不变。
2. **导演工具 24px overflow**：右栏固定 320dp 宽度在 360dp 手机上把舞台挤到负宽；新增 `_MobileDirectorLayout`，右栏改为浮层，舞台独立横向滚动（内容最小 520dp），顶栏不再预留桌面窗口按钮的 138dp。
3. **「多余的东西」= 导演工具右栏的解锁浮钮**：无说明的浮动圆钮已删除，改成顶栏带文字的「面板」按钮（`tools-director-mobile-side`），打开/关闭同一右栏浮层，返回键可先关浮层。
4. **画布图片流「不能滑动」**：`canvas_lock_camera`（锁定画布相机）开启时会禁用拖拽平移与双指缩放——这是桌面原有设置，触屏上没有替代手势，表现就是画布冻结。移动端保持该设置语义不变，但锁定时在生成页顶栏显示「解除画布相机锁定」按钮（`gen-mobile-unlock-camera`），点一下即恢复手势浏览；同时在 `test/presentation/ui/gen/gen_test_harness.dart` 注入可控替身，避免测试依赖真实 Hive 设置。

### 8.5 二轮反馈：顶栏精简 + 「最近生成」

1. **顶栏单行**：手机端 `GenHeader` 不再承载编辑/历史入口，只留模型胶囊 + 配额胶囊（解锁相机按钮仅在锁定状态临时出现）。360dp 下常态顶栏保持 37dp 一行，把高度让给画布。
2. **入口下移**：`GenGenerateBar` 新增可选 `leading` / `trailing`（桌面不传，布局等价），手机端传入两个 44×40 描边按钮——左「编辑提示词」（`gen-mobile-editor`）、右「最近生成」（`gen-mobile-history`），中间生成按钮自适应撑开，未新增任何行。
3. **历史改称「最近生成」**：入口 tooltip、浮层标题改为 `gen_recent`，浮层副标题 `gen_recentHint` 说明「本次运行的结果；长期保存的图片在图库」。`GenHistoryPanel` 新增 `compactHeader`（默认 false，桌面不变）：手机浮层内不再重复渲染桌面收起按钮与「历史记录」标题，只保留计数 / 钉图 / 多选。功能不变：批次回填画布、双击开大图、批次菜单、钉图 Pins、保存全部、清空、锁定滚动。
4. **与画廊的分工**：历史 = 本次运行内的生成结果与批次（内存态，重启清空，可回填/重抽）；画廊 = 落盘后的长期图库（自动保存默认开启，支持搜索/筛选/元数据/回收站）。手机端不合并两者，只在文案上区分，避免入口重复感。

### 8.6 三轮反馈：调试模式 / 移动浮层 / 查看器

1. **调试模式（无订阅也能讨论 UI）**：新增 `lib/presentation/dev/demo_fixtures.dart`，`--dart-define=NAI_DEMO=1`（或 `true`）构建时，启动后在延迟启动步骤里读本地 `assets/images/demo-sample.jpg`，用 `GeneratedImage.create` 造一张图并调用 `ImageGenerationNotifier.adoptDemoImages`——走的是和真实生成结果相同的状态结构（`currentImages` / `history` / `displayImages` / `generationRunId` / 批次宽高），画布、最近生成、查看器、导演工具都能照常打开，不请求接口也不扣费。默认关闭，桌面端与发布构建行为不变；构建命令：
   `flutter build apk --debug --target-platform android-x64 --dart-define=NAI_DEMO=1`
2. **弹层统一改成底部面板**：`UiPopover` 新增手机分支（`_MobilePopoverSheet`）——不再贴锚点定位，而是全宽（左右 8dp）+ 底部安全边距浮起的面板，带半透明遮罩（点遮罩收起）、180ms 上滑淡入、内部滚动、键盘弹起时贴键盘上沿；高度按弹层宿主 Overlay 的实际可用区域计算（内嵌 Navigator 的 Overlay 可能比整屏矮，按 `MediaQuery` 算会让顶边跑出屏幕）。桌面端仍按锚点定位，代码路径不变。`UiMenuItem` 在手机上把行高从 34 提到 46、字号 13→14、图标与内边距同步放大；提示词工具栏的「模块与开关」菜单（`_ToolsMenu`）行高 46、分节标题更大，且「资源小窗」二级菜单在手机上改成点开同一位置的新面板（桌面仍是悬停二级菜单）。
3. **查看器手机适配**：桌面顶栏 61dp 里塞了返回文字 + Esc 帽 + 缩放 −/+/1:1/全屏/信息，360dp 下溢出 97–107px——调试构建里表现为右上角黄黑斜纹 + 竖排「RIGHT OVERFLOWED BY …」条。手机端顶栏改为 52dp：返回只留箭头（文字进 tooltip）、生成模式只显示保存状态、画廊模式只显示位置、缩放收成「适应 · 78% ▾」胶囊（点开同一套比例菜单，放大用双指）、右侧全屏/信息两个 40dp 图标。信息栏（`ViewerInfoPanel`）在手机上是整屏抽屉（全宽、顶部圆角、位于手机顶栏之下），不再固定 340dp。
4. **验证**：新增 `test/presentation/providers/generation/demo_fixtures_test.dart`（示例图注入后画布/历史/目录/运行号/批次尺寸一致）、`test/presentation/ui/kit/ui_popover_mobile_test.dart`（手机弹层贴底且撑满宽度、点遮罩收起）；`test/presentation/ui/viewer` 105 例、`test/presentation/ui/gen` + `tools` + `kit` 回归全部通过；MuMu x86_64（360dp）实机确认生成页出现示例图、工具菜单为底部面板、查看器顶栏无溢出、信息抽屉整屏可读。

### 8.7 导演工具手机布局（方案 A）

按讨论选定的 A 方案重排手机端导演工具（桌面三栏布局不动）：

1. **画布优先**：去掉左侧 56dp 工具竖栏与右侧 320dp 参数栏，画布独占整行；上条只留「输入 1/2 ▾」（点开输入队列弹层）和「适应 / 100%」。
2. **底部工具条**：7 个工具（背景移除 / 杂线清理 / 线稿提取 / 草图化 / 上色 / 表情修复 / 像素对齐）以图标 + 名称排在底部，360dp 一屏放得下、不用横滑；选中项强调色描边。点工具**只切换选中项**，不再弹参数面板，运行按钮和介绍跟着变；工具条始终可见。
3. **常驻运行条**：画布和工具条之间固定一条 89 高的运行条——上面一行是「工具名 · 一句话介绍」（功能介绍和画布同页，不用点进弹层才看得到），有可调选项的工具（上色 / 表情修复 / 像素对齐）右侧给「选项」入口，有结果时再给「结果 n」；下面一行是 44 高主按钮「运行{工具}」+ 价格（本机免费 / Anlas，运行中转圈），和主页面「生成」按钮同一主按钮样式。没有可调选项的工具（背景移除 / 杂线清理 / 线稿提取 / 草图化）直接点运行就能跑。
4. **参数弹层（仅「选项」）**：带选项的工具点「选项」才打开底部弹层，右栏内容（表情网格、提示词、强度、调色板等）原样复用 `ToolsDirectorSide`（顶部圆角、抓手 + 关闭、点遮罩收起、返回键先关弹层）；运行按钮不放在弹层里，弹层只调参数。手机上不显示 Ctrl+↵ 键帽。`ToolsDirectorSide` 新增 `showBorder` / `mobileSheet`（默认 false，桌面行为不变）。
5. **对比方式胶囊**：并排 / 滑动对比 / 只看结果从桌面舞台条的三段控件改成画布右上角胶囊，点开底部弹层选择（复用 `UiPopover` 的手机分支）。
6. **输入队列弹层**：底部队列条收进弹层，从「输入 n/N」胶囊进入；手机版只留「输入队列 · n 张」标题 + 缩略图 + 加号并横滑浏览（`_Queue(compact:)`；桌面仍是 92 高的整条）。
7. **结果列表弹层**：运行条上的「结果 n」胶囊打开独立的结果弹层（复用右栏结果列表 `ToolsDirectorResults`），不再把结果塞进参数弹层的滚动区、避免半截标题被裁。
8. **结果操作**：`_ResultActions` 的窄屏换行逻辑保留；手机端还没有结果时整块不渲染（含「用作图生图底图」主按钮），把高度让给画布。
9. **验证**：`tools_director_mobile_test.dart` 4 例（进入即有运行条 + 介绍、点工具只切换 / 有选项才给「选项」且点开/关闭弹层、输入胶囊开/关队列弹层、结果胶囊开/关结果弹层）；tools 全量测试（含 golden）通过；MuMu 360dp 实机确认画布、运行条、底部工具条、参数弹层、队列弹层、对比菜单、结果弹层均正常且无 overflow。

### 8.8 画布工具面板（增强 / 放大）手机适配

桌面上「增强」「放大」是画布工具条按钮下方落下的定宽卡片（620 / 520，带尖角、限高滚动）；358dp 宽的手机放不下，出现 `RIGHT/BOTTOM OVERFLOWED` 黄条。处理：

1. **面板外框**（`ToolsSheetFrame`）：手机端铺满画布宽度、贴画布底部（`gen_canvas.dart` 手机分支改 `Positioned` + `Align(bottomCenter)`，不再对齐按钮、不画尖角）；头固定、内容区单独滚动（`tools-sheet-body-scroll`）、底栏常驻；取消按钮去掉 Esc 键帽。
2. **行内字段**（`ToolsFieldRow`）新增 `stack` 参数（默认 false）：手机端标签单独一行、内容用 `Wrap` 折行，只给增强 / 放大两个面板的手机分支启用，桌面与其它页面行为不变。
3. **放大设置**：后端卡手机端竖排；放大方式 / 模型 / 倍数三行改折行布局；高级设置每项标签在上、控件在下。
4. **验证**：`tools_sheets_test.dart` 新增手机 3 例（增强、增强自定义强度、放大含高级设置），共 14 例通过；桌面「面板落在工具条下面、尖角指着按钮」用例仍通过。

### 8.3 本阶段遗留（后续处理）

1. 复用桌面内容页后，个别行内小按钮（24–32dp）未达 44dp 触摸目标，需真机走查后统一包触摸区；
2. "保存到相册"沿用现有 l10n `common_export`（"导出"）文案，精确文案需补 ARB key；
3. 分类选择/批量元数据等次要桌面对话框未做手机重排；日期选择沿用现有日历（日期格 36dp）；
4. 生成请求在代理链路上偶发 `HandshakeException`（代理节点对 image.novelai.net 不稳定），属环境网络问题，非 App 逻辑；首次冷启动自动登录失败时点"一键登录"可重试成功；
5. 平板/横屏、Phase 2（浏览类页面）与 Phase 3（编辑器）尚未开始。

> 生成页与桌面版的逐项差距、优先级和可复用工具，见 [mobile-gen-gaps.md](mobile-gen-gaps.md)。

