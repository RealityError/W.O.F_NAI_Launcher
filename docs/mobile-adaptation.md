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

### 8.9 画布：同步上游 2.3.2「移除视觉通道导航尺 + 自动聚焦居中」

上游 2.3.2 的画布组改动对手机是净收益（画布右缘那条装饰性刻度尺不再占地方），按 `docs/upstream-sync-2.3.2-2026-11-08.md` 的结论手工移植，不整包合并：

1. **移除导航尺/进入提示**：删除 `lib/presentation/ui/channel/channel_overlay.dart` 与 `ChannelActions`、`canvasChannelEntryNoticeProvider`；`channel_contract/fixture/geometry`、`canvas_channel_provider`、`generation_canvas_view`、`generation_canvas_wiring` 按上游新版精简。440da91d 为窄屏把主题名从 4 个改成 2 个的那行随文件删除作废（该提示整体移除）。
2. **自动聚焦居中**：`GenCanvas` 用 `_TopBar/_InfoBar/_ActionBar` 的 GlobalKey 实测悬浮条内侧边界，`focusPaddingOf` 取代固定留白 `40/50/40/70`；手机底部工具条更高，生成占位/结果不再被压。`_BottomBars` 增加 `infoOffset`，`<360` 时仍上下叠放。
3. **保留手机分支**：`gen_canvas.dart` 里 8.8 的「工具面板贴底铺宽」`usesMobileLayout` 分支重新应用到上游新版之上。
4. **验证**：`flutter analyze` 无问题；channel + 画布接线 183 例、`test/presentation/ui/gen` 374 例、生图接线核心 133 例全部通过；`dart format` 无改动；桌面 `scope.slots.canvas == null` 的测试舞台保留旧构图，golden 不变。

### 8.10 生成页触屏入口第一批（长按菜单 / 隐藏桌面专属）

按 [mobile-gen-gaps.md](mobile-gen-gaps.md) 第一批落地，桌面交互一行不改：

1. **画布图片长按**（G1）：`GenCanvasMenuScope` 新增 `onOpenMobile`，手机布局下图块 `onLongPress` 触发；`openGenerationCanvasMenuMobile` 把右键菜单拍平成底部弹层（保存 / 复制 / 详情 / 删除 / 发送到图生图 / 风格参考 / 精准参考 / 保存到精准参考库），桌面右键路径与菜单内容不变。
2. **历史批次长按**（G2）：`_BatchItem` 接收 `onLongPress`（仅手机布局传入），弹出与桌面右键同源的批次动作；不另加「…」悬浮按钮，避免遮挡封面。
3. **放大面板**（G6）：`toolsUpscaleView` 在 Android 固定云端后端、隐藏「本地」卡片（纯函数 `toolsUpscaleBackends` 便于回归）；打开面板时把后端固定回 `novelai`，桌面残留的 `local` 设置不会再触发「平台不支持」。
4. **Krita / 打开文件夹**（G9）：桥接图标只在桌面提示词模块出现（手机不渲染该模块），仍加 `usesMobileLayout` 守卫；桌面右键里的「在资源管理器中显示 / 发送到 Krita」不进手机长按菜单。
5. **验证**：`flutter analyze` 干净；`gen_mobile_layout_test` 新增 3 例（画布长按入口、批次长按菜单、手机无桥接图标），`tools_upscale_mobile_test` 新增 3 例；`test/presentation/ui/gen` + `test/presentation/ui/tools` 541 例、生成接线核心回归 7 文件全过；桌面 golden 不变。

### 8.11 生成页资源库手机化（G11 方案 A）

把桌面「资源小窗」里的块库 / 风格库 / 精准参考库搬到手机上，改成全屏页 + 点按插入；桌面浮窗一行不动：

1. **入口**：编辑提示词浮层标题栏新增「库」按钮（`gen-mobile-libraries`），底部弹层列图库 / 块库 / 风格库 / 精准参考库；桌面三栏没有这个按钮，原工具栏入口与快捷键照旧。
2. **打开方式**：`ResourceWindowOpener.open` 在移动布局下分流——图库直接 `go(localGallery)`；其余三类开一个**不落盘**的临时窗口（`FloatingResourceWindows.open(persist: false)`），用 `showGeneralDialog` 推出 `MobileResourceLibraryPage`（220ms 上滑），关闭/返回键退出时回收临时窗口。手机不渲染桌面浮窗宿主（`FloatingResourceWindowsHost` 移动分支直接返回空），桌面渲染逻辑不变。
3. **外观与操作**：`FloatingResourceWindow` 新增手机分支——关闭按钮 + 标题 + 数量 + 「轻点即插入」提示、42dp 搜索框、块行 44dp、参考图网格 120dp；点块走 `BlocksActions.insert` 插入当前提示词，点缩略图走 `refsEntryDropActionsProvider.drop` 加入生图页；手机页不启用拖拽、不画右下缩放角。
4. **文案**：新增 `floating_mobileTapHint`（zh/en/ja/ko；zh_TW 由 `tool/l10n` 重新生成，不手改）。
5. **验证**：`flutter analyze` 干净；`test/presentation/ui/gen`（390 例）、浮窗宿主 / 数据源 / 资源窗口页与生成接线回归（103 例）全过；新增 `mobile_resource_library_test`（手机全屏外观、无缩放角/拖拽、44dp 点按行）、provider「临时窗口不落盘」、`gen_mobile_layout_test`「库入口与四类资源菜单」、宿主「手机不画浮窗」用例。

### 8.12 图片查看器手机收尾（G12）

1. **全屏 chrome 常驻**：手机全屏下不做空闲自动隐藏（否则没有退出入口），点画面切换 chrome；
   顶部信息条改用手机版（信息 / 退出两个 44dp 图标），全屏底部出现横向胶片条。
2. **胶片条**：手机端左右留白 8、淡出边 24dp（桌面 14 / 60），可横向拖动；点缩略图切图。
3. **菜单**：长按图片取代右键（打开「更多」底部面板）；菜单行高 48dp、手机不画快捷键帽；
   「加入收藏集」在手机上直接切到收藏集面板，不做向左展开的子菜单。
4. **桌面不变**：popover、键帽、悬停胶片条、窗口按钮避让逻辑一行未改。
5. **验证**：新增 `viewer_mobile_test.dart`（6 例：顶栏、胶片条拖动、缩略图选中、长按更多面板、
   信息抽屉、全屏 chrome 常驻与退出）+ 360×640 追加用例；`test/presentation/ui/viewer` 全目录通过。

### 8.13 触控目标 48dp 与 360×640 走查（G4 / G5）

1. **共享命中区**：新增 `GenTouchTarget`（手机端包 48×48 命中区，桌面直接返回 child，
   不增加 RenderObject），应用到 `GenIb` / `GenFloatButton` / `GenTab` / `GenSliderRow` 等。
2. **生成页**：历史底栏 40→56（图标命中 48）、头部胶囊外框 50（描边内 48）、参数条种子行 56 /
   下拉 48 / 抽屉标题 56、提示词工具条 28→48、生成按钮 40→48；手机顶栏隐藏 "Model" 小标签
   回到单行（59dp，改前 113dp），Turbo 命中区 48×48（视觉 22）。
3. **全屏编辑器 / 翻译浮层**：手机端全屏头部改两行（关闭 / 清除 48×48，正负向切换加 48 高
   透明命中层；360dp 下标题保留）；翻译浮窗收起 / 关闭 / 发送 / 快捷 chip / 引用清除 / undo
   全部 ≥48。桌面尺寸由测试守卫用例锁定（30×30、28 高、11×11、38×16 等原样）。
4. **走查**：新增生成页手机走查 4 例、翻译浮窗 3 例、查看器 360×640 1 例，全程无 overflow；
   桌面 golden 与尺寸守卫用例不变。

### 8.14 编辑图片 / 局部重绘页手机化（G13 / G14）

桌面编辑器是三栏（左 56 工具竖栏 + 画布 + 右 280 面板），360dp 下工具与面板互相挤。手机端
复用「导演工具方案 A」：

1. **布局**：`ToolsEditorPage` 增加 `usesMobileLayout` 分支——顶栏（返回 / 标题+尺寸 /
   撤销 / 重做 / 下载，图标 48）、画布优先、底部应用条（参数、面板、应用 / 应用下拉）、
   底部横滑工具条（点一下直接切工具，不显示快捷键字母帽）。桌面三栏代码原样。
2. **弹层**：参数（当前工具的笔刷大小、方笔、蒙版外观颜色/不透明度/图案、缩放）与图层面板
   从底部升起，工具条保持可点；系统返回键先关弹层。局部重绘的「应用蒙版」分成
   「仅应用 / 应用并生成」两段，手机端下拉是底部弹层。
3. **接线**：`image_editor_screen` 仍复用同一 `ToolsEditorPage`（`tools_editor_wiring`），
   无需单独一套布局；`ToolsEditorSide` 增加整宽 / 无边框参数供手机面板使用。
4. **验证**：新增 `tools_editor_mobile_test.dart`（7 例：布局、工具条切工具、参数弹层、
   图层面板、弹层下切工具、局部重绘工具与应用分段、应用/下载动作）；
   `image_editor_mobile_test.dart`（5 例：真实 `ImageEditorScreen(inpaint)` 手机布局、
   参数弹层、图层面板、手指涂蒙版、应用下拉）；桌面 `test/presentation/ui/tools` 171 项全过。

### 8.15 系统集成：后台生成 / 分享 / 应用内更新（G10 / G15–G17）

1. **后台生成（G10）**：`GenerationBackgroundSync` 在 `_AppBootstrapEffectsState` 里挂
   `imageGenerationNotifierProvider` listener，生成开始 / 进度 / 完成 / 失败 / 取消分别走
   `com.nailauncher/generation` 的 `start` / `update` / `stop`；Kotlin
   `GenerationForegroundService` 用 dataSync 前台服务保持进程并显示进度通知，停止后发完成通知
   （点按回 App）。通知权限被拒时不崩，仅通知不可见。6 例状态迁移测试。
2. **分享出站（G15）**：查看器「更多」、手机画廊长按、生成结果长按 → 系统分享面板；
   Android-only 动作集合（桌面 action 列表 remove），UI 层不 import wiring。
3. **接收分享（G16）**：MainActivity 处理 `ACTION_SEND image/*`，把 content:// 拷到
   `cacheDir/incoming_shares/`；`getSharedImage` 拉取 + `shareImageReceived` 前台信号，
   Dart 复用 `ImageWorkflowLauncher.openImageToImage` 进 img2img 并 toast。12 例通道 mock 测试。
4. **应用内 APK 更新（G17）**：Android 独立链路（GitHub Release 选 ABI 匹配 APK → cache 下载 +
   SHA256 校验 → `FileProvider` + 系统安装器；「安装未知应用」跳系统设置页，返回后重试），
   设置页「关于/更新」卡片跟随 `UpdateState`；桌面更新器不变。22 例纯逻辑 / 通道 mock 测试。
   注意：GitHub Release 需上传 `app-<abi>-release.apk` 命名的资产，否则只提示有新版本、无法装包。

### 8.16 画布底部工具条合并为一条（360dp 画布空间回收）

360×640 下画布可用高度只有约 356dp。第二批统一 48dp 命中区后，信息条和动作条在手机上
上下叠放，两条浮条连同留白吃掉约 130dp，图片只剩 ~99×144dp（用户反馈「好挤」）。
按用户选择的「精简成一条动作条、保留随机通道背景」方案处理：

1. **单条动作条**：手机端 `_BottomBars` 不再渲染 `_InfoBar`，改为一条 `_MobileBar`——
   显示设置（`gen-display`）+ 分隔线 + OLD（有原图时）+ 钉住 / 复制 / 保存 / 查看大图，
   全部落在同一条 48dp 命中区里。桌面两条浮条、`gen-bar-info` / `gen-bar-actions` 键位与
   悬停行为一行未改（窄窗口 <360 仍叠放）。
2. **尺寸 / 种子入口**：`832 × 1216` 与种子胶囊（点开「使用 / 复制种子」）移到显示设置
   弹层顶部（仅 `usesMobileLayout` 显示），不再单独占一条；种子为 null 时不显示，与桌面一致。
3. **聚焦留白**：`_scheduleFocusMeasurement` 允许没有信息条——手机端信息条缺失时用动作条
   兜底计算底部内边界，`focusInsets` 按实际单条高度收，图片既不被压也不多留一条的空隙。
4. **实测（MuMu 360×640，非 demo 构建）**：图片可视高度 144 → 203dp（+41%，面积约 2 倍）；底部只剩
   一条动作条，`832 × 1216` 出现在显示弹层顶部。`gen_mobile_small_test` 增加「只有
   `gen-bar-mobile`、显示设置与图片动作同排、图块高度 > 320dp」断言，`gen_mobile_touch_test`
   改为在显示弹层里检查种子胶囊 48dp；`test/presentation/ui/gen` + `test/presentation/ui/channel`
   共 465 例、画布接线与生成页 176 例全过，桌面 golden 不变。

### 8.17 应用内更新链路打通（Android 读 fork 的 Release）

复查发现 Android 的应用内更新**从来走不到系统安装器**：`ReleaseAssetInfo.inferType`
只认 Windows/macOS 文件名，`.apk` 一律落到 `unknown`，于是
`supportsInAppInstall` 恒为 false，更新卡片只会显示「前往下载」——即使 Release 里
真的放了 APK，用户也永远点不到安装。

1. **资产类型**：新增 `ReleaseAssetType.androidApk`（`typeId` = `android-apk`，
   `platform` = `android`，label「Android 安装包」）。`inferType` 先判 `.apk` 再走
   桌面的文件名启发式，避免 Android 包名里出现 `windows` 之类字样时误判；
   `parseType` 同时认 manifest 里的 `android-apk`。
2. **平台选包**：`_findPlatformAsset` 补 `android` 分支，只返回 APK 类型候选，
   不会把 Windows/macOS 资产当安装包；ABI 匹配仍交给
   `AndroidUpdateLogic.selectApkAsset`（拿到设备 ABI 后按 arm64-v8a / armeabi-v7a /
   x86_64 顺序挑，找不到再退回 `universal` 或第一个包）。
3. **更新源**：上游 `z15087716457-stack` 的 Release 只有 Windows/macOS 资产，
   Android 改读 fork `RealityError/W.O.F_NAI_Launcher_Android`（`UpdateCheckService.owner`
   与 `repoFor(android:)`，纯函数便于测试）。**桌面仍查上游，行为不变**；更新说明里的
   相对链接与「查看更新日志」入口跟着实际更新源走。
4. **验证**：`flutter analyze --no-pub` 干净；`test/core/services`、`test/data/models/version`、
   `test/data/datasources/remote` 与 4 个更新 UI 测试文件共 387 例通过（仅
   `windows_update_launch_test` 两个已知的环境性失败，与本次改动无关）。
   新增用例覆盖「APK 被认成可安装」「android 平台只选 APK」「owner 按平台切换」。

### 8.18 手机端设置裁剪（2.5.0）

首个可分发版本前，把「点了必然失败」或「触屏无意义」的设置入口从手机端隐掉。
判定口径仍是 `settingsPageAvailable`（`lib/presentation/ui/settings/settings_contract.dart`），
桌面端不受影响，页面主体仍可被深链/搜索命中。

| 隐藏项 | 原因 |
| --- | --- |
| Agent 页 | 随包 Node 运行时只在桌面存在 |
| 语义检索（RAG）页 | Python + uv + PyTorch 运行时只在桌面存在 |
| 放大页 | 本地/高级放大依赖随包可执行文件；云端放大属生成动作，不在此页 |
| 网络页 | 手动代理未在 Android 实现（只能跟随系统 Wi-Fi 代理） |
| 键盘快捷键页 | 触屏没有物理键盘，快捷键录制无意义 |
| 存储页「打开文件夹」 | Android 是应用私有目录，没有「在资源管理器中打开」 |
| 「添加服务商」里的 ChatGPT 套餐 | 登录走随包 Node，Android 上必然报「操作失败」（原为死入口） |

后两项不是整页隐藏，分别用 `isMobilePlatform` 与 `supportsNaiAgentRuntime` 做局部门控。
`settings_mobile_page_test` 的可见页清单改为按生产口径过滤，避免手写清单与实现漂移。

### 8.19 手机端桌面残留清理（2.6.0）

2.5.0 发布后用户走查发现三类「手机上看得到、但属于桌面」的残留，一并清掉。

**1）小贴士按平台分池**
`Tip` 新增 `desktopOnly` / `mobileOnly`（`lib/presentation/providers/tips_provider.dart`），
`TipDeck.tipAt(..., mobile:)` 按平台过滤，`mobile` 缺省取 `isMobilePlatform`（测试可注入）。
生成页空画布欢迎页（`TipSurface.studio`）原来 8 条里 4 条讲键盘/鼠标：

| 桌面专属（手机不再出现） | 原因 |
| --- | --- |
| `tips_studio_guide_1` | Ctrl+Enter 生成、中键平移、Ctrl+滚轮缩放、WASD |
| `tips_studio_guide_4` | 「把一张图拖进窗口」 |
| `tips_studio_guide_6` | Alt+滚轮调权重 |
| `tips_studio_guide_7` | F1 快捷键帮助、Ctrl+1/2/3 切页、Ctrl+, 设置 |

手机补 3 条触屏说明 `tips_studio_mobile_1..3`（底部工具条改参数、长按画布图片的菜单、
提示词浮层右上角资源库图标），与桌面池互不串台（`tips_provider_test` 有专门断言）。

**2）其它残留快捷键文案**

| 位置 | 桌面键 | 手机键 |
| --- | --- | --- |
| 提示词搜索「全部替换」tooltip | `prompt_replaceAll` | `prompt_replaceAllMobile` |
| 设置 · 自动补全「关联标签」副标题 | `autocomplete_relatedTagsSubtitle` | `autocomplete_relatedTagsSubtitleMobile` |
| 提示词菜单「共现推荐」副标题 | `prompt_cooccurrenceRecommendationSubtitle` | `prompt_cooccurrenceRecommendationSubtitleMobile` |
| 设置 · 输出查看器「画布」说明（卡片与选择对话框两处） | `settings_outputViewer_canvasDescription` | `settings_outputViewer_canvasDescriptionMobile` |

**3）设置行尾部状态标签**
`MobileListTile.trailingText` 限宽 120dp、单行省略、右对齐（`lib/presentation/mobile/mobile_list.dart`）。
360dp 下不再与标题/副标题抢宽度，也不再顶出行尾；`mobile_components_test` 用超长状态文案压测。

**4）仿制图章在手机上不可用（顺手修）**
源点只能 Alt+点击设置，手机没有硬件 Alt，等于工具点了没反应。改为手机端设置面板给一个
「取源点」按钮（`clone-stamp-pick-source`）：按下进入取点态，再点画布设定源点；
桌面仍走 Alt+点击（`handlesAltKey` 未变）。

**5）相册顺序（触屏没有拖拽）**
手机图库「浏览范围」弹层里每个相册/收藏夹行尾加「⋯」菜单，提供「上移 / 下移」
（`common_moveUp` / `common_moveDown`），复用桌面拖拽同一个 `CollectionNotifier.reorder`；
桌面侧栏的拖拽排序一行未改。

### 8.20 次级页面手机竖屏布局（2.6.0）

判定方式统一为 `usesMobileLayout`（测试用 `debugForceMobileLayout = true`），桌面分支保持原渲染。

| 页面 | 手机形态 | 关键改动 |
| --- | --- | --- |
| 统计 | 单列滚动、KPI 两列窄卡、日历点格 ≥44dp | `ui/statistics/*`；EN 下隐藏图例避免溢出 |
| 在线画廊 | 单列（工具栏 + 横向滚动筛选 chip + 墙） | `ui/online/*`；左栏/检查器进底部弹层，卡片操作条常显，多选条整宽图标化，全选/反选进「更多」 |
| 标签 Wiki | 单栏列表默认不落正文 | `screens/tag_wiki/*`；行内书签常显、行高 ≥44、文章全屏、目录弹层 |
| 块库 | 单列墙 + 手机工具栏 | `ui/blocks/*`；导航/详情进弹层，长按=右键菜单，筛选行横向滚动 |
| 精准参考库 | 单列墙 + 手机工具栏 | `ui/refs/*`；左栏/检查器弹层、hover 操作条常显、tray 手机整行 |
| 风格探索 | 编辑/结果分段切换 + 单列 | `ui/explore/*`；结果工具栏精简、页签与筛选胶囊合并横向滚动、检查器整宽覆盖 |
| 次要对话框 | 分类选择整屏、日期格 36→48dp、批量元数据全宽 82vh | `widgets/gallery/category_picker_dialog.dart`、`date_range_picker_dialog.dart`、`widgets/bulk_metadata_edit_dialog.dart` |

360dp 回归测试在 `test/presentation/ui/{statistics,online,blocks,refs,explore}/*_mobile_test.dart`、
`test/presentation/screens/tag_wiki_mobile_test.dart`（每页都有无异常 + 关键入口可点断言），
桌面 golden（online/explore/blocks/refs、`settings_golden_test`）保持通过。

设置详情两页：

- **模型与接口**：手机端不再叠桌面浮层（`settings_models.dart` 一行门控），改为服务商列表
  （`MobileSectionHeader` + 48dp 添加按钮，行高 ≥60dp）→ 点行推全屏编辑页（单列滚动 +
  底部 48dp 保存条）→ 点模型行弹底部参数 sheet；模型行内「上移 / 下移」48×48 按钮复用
  `ProvidersActions.onReorderModels`（服务商级排序线上无 reorder 契约，未做）。
  新增文件 `ui/model_providers/model_providers_mobile.dart`；360dp 四处 overflow 消除。
- **桥接与集成**：状态卡置顶 → Krita → 外部 Agent → ComfyUI（地址整宽、测试按钮下一行），
  桌面仍走右侧 aside；Krita 段保持 `supportsKritaBridge` 门控。

Android 13+ 通知权限（首次生成时申请、拒绝后只引导一次、不影响生成本身）见
[android-port.md](android-port.md) §1.1/§1.3(G18)/§6.11。

### 8.21 本地 RAG 语义检索不复刻（2026-11-10 决定）

第 5 项讨论后决定：Android **不**移植桌面 RAG（Python + uv + PyTorch + `google/embeddinggemma-2` 1.49 GB + `Qwen/Qwen3-Reranker-0.6B`）。手机端继续保持现状——`supportsLocalRagRuntime == false`，设置「语义检索」页、提示词补全的语义召回、Wiki/块库语义搜索、图库 RAG 徽标/菜单与 Agent `studio_search` 均不出现，`RagClient.start` 在 Android 提前抛 `unsupported_platform`，不会把异常抛给 UI。

理由：运行时数 GB、模型约 3 GB、首次建库长时间占满 CPU/GPU，且建库与生成/放大互斥；这套成本与手机竖屏主场景不匹配。桌面端实现与行为不变。

若以后重新考虑，按成本从低到高排序：

1. **远程 embedding**：复用现有 AI 服务商接口，零本地运行时，但每次检索走网络、依赖服务商；
2. **ONNX Runtime Mobile + 量化小 embedding 模型**（100–200 MB）：先只做提示词标签推荐与 Wiki/块文本检索，reranker 用轻量 cross-encoder 或「语义分 + 共现 + 词法」加权替代；图像通道（图库以图搜图）后置；
3. 完整复刻 Python 链：不推荐。

### 8.3 本阶段遗留（后续处理）

1. 手机端生成页 / 全屏编辑器 / 翻译浮层 / 查看器 / 编辑器范围内的触控目标已统一到 ≥48dp；
   次级页面里个别次级图标仍是 32–40dp（如风格探索舞台内的小图标），未逐一抬到 48；
2. "保存到相册"沿用现有 l10n `common_export`（"导出"）文案，精确文案需补 ARB key；
3. 分类选择 / 日期选择 / 批量元数据对话框已做手机布局（2.6.0），但只有桌面回归测试，
   没有 360dp 专用 widget 测试；批量元数据对话框内的英文硬编码文案属既有问题，未国际化；
4. 生成请求在代理链路上偶发 `HandshakeException`（代理节点对 image.novelai.net 不稳定），属环境网络问题，非 App 逻辑；首次冷启动自动登录失败时点"一键登录"可重试成功；
5. 平板/横屏与桌面端未适配的次要页面（如部分管理类对话框）仍未开始；手机竖屏为主场景；
6. 鼠标/键盘修饰键在触屏的等价入口仍未覆盖（Alt 取色、Shift 约束角度、Ctrl 权重滚轮），
   2.6.0 只补了仿制图章的「取源点」按钮，其余工具仍是桌面手势。
5. 平板/横屏与桌面端未适配的次要页面（如部分管理类对话框）仍未开始；手机竖屏为主场景。

> 生成页与桌面版的逐项差距、优先级和可复用工具，见 [mobile-gen-gaps.md](mobile-gen-gaps.md)。
> Android 平台能力、构建与已知限制见 [android-port.md](android-port.md)。

