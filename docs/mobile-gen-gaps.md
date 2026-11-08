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
| G1 | 画布图片长按菜单 | 图片菜单只绑了右键（`onSecondaryTapDown`，[gen_canvas.dart:645](../lib/presentation/ui/gen/gen_canvas.dart#L645-L656)），触屏无入口；菜单动作在 [generation_canvas_menu.dart:80-220](../lib/presentation/wiring/generation_canvas_menu.dart#L80-L220) | 长按图片 → `showMobileContextMenu`，动作与右键一致；补齐**删除单张 / 发送到风格参考 / 发送到精准参考 / 保存到精准参考库**（其余项工具条已有） | `gen_canvas.dart`、`generation_canvas_menu.dart` | S | ⬜ |
| G2 | 历史批次菜单 | 批次菜单只绑右键（[gen_history.dart:616](../lib/presentation/ui/gen/gen_history.dart#L616-L618)） | 长按批次或点批次右上「…」→ 同一套菜单：查看大图、复制、收藏、发送到图生图 / 风格参考 / 精准参考、保存整批 | `gen_history.dart` | S | ⬜ |
| G3 | 批次封面悬停按钮 | 保存 / 复制按钮只在 hover 出现（[gen_history.dart:141-155](../lib/presentation/ui/gen/gen_history.dart#L141-L155)） | 触屏常显或并进 G2 的菜单 | `gen_history.dart` | S | ⬜ |
| G4 | 触控目标 48dp | 历史底部一排图标、画布浮动按钮、头部胶囊、参数条多为 24–32dp | 生成页范围内可点区域 ≥ 48dp（视觉可维持 32dp） | `gen_history.dart`、`gen_canvas.dart`、`gen_params.dart`、`gen_header.dart` | M | ⬜ |
| G5 | 验收已有手机适配 | 提示词全屏编辑器、翻译调整浮层、查看器主界面已有 `usesMobileLayout` 分支，未系统验收 | 360×640 逐项走查无溢出、可操作，补 widget 测试 | `gen_prompt.dart`、`translation_adjust_window.dart`、`viewer_page.dart` | S | ⬜ |

## 2. Android 缺失 / 桌面专属功能（P1–P2）

| ID | 事项 | 现状 | 目标 | 涉及文件 | 量级 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| G6 | 放大面板「本地」卡片 | Android 上 disabled（`enabled: windows`，[tools_generation_wiring.dart:144-158](../lib/presentation/wiring/tools_generation_wiring.dart#L144-L158)） | 手机端直接隐藏本地卡片并提示「可用 NovelAI 云端超分」，避免死按钮 | `tools_generation_wiring.dart`、`tools_sheets.dart` | S | ⬜ |
| G7 | 增强面板「本地」因子 | 已按平台排除（[tools_generation_wiring.dart:59-65](../lib/presentation/wiring/tools_generation_wiring.dart#L59-L65)） | 无需改动，仅记录 | — | — | ✅ |
| G8 | 本地超分引擎（NCNN / SeedVR2 / RTX Video） | 随包 Windows 可执行文件，Android 无实现（另一条产品线，非移植项） | 若要做：Android 侧 ONNX/NCNN 推理或改走 ComfyUI 后端 | 新立项 | L | ⛔ |
| G9 | Krita 桥接 / 打开文件夹 / 发送到 Krita | 桥接图标连本机 socket（[gen_prompt.dart:413-452](../lib/presentation/ui/gen/gen_prompt.dart#L413-L452)）；「打开文件夹」是桌面文件管理 | Android 隐藏这三项，不留必失败入口 | `gen_prompt.dart`、`generation_canvas_menu.dart` | S | ⬜ |
| G10 | 生成中切后台 | 无前台服务/通知，系统回收进程会中断生成 | 前台服务 + 完成通知（可选：保持后台持续生成） | Android 原生 + `image_generation_provider` | M | ⬜ |

## 3. 生成页延伸目标页（P1–P2）

| ID | 事项 | 现状 | 目标 | 涉及文件 | 量级 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| G11 | 浮动资源小窗 | 块库 / 图库 / 风格库 / 精准参考库仍是桌面浮窗（默认 400×360，可拖拽缩放），360dp 上近似满屏但带桌面边框 | 手机端改全屏面板（复用 `_MobileOverlayPanel` 形式），桌面保留浮窗 | `floating_resource_windows_host.dart`、`floating_resource_window.dart` | M | ⬜ |
| G12 | 图片查看器收尾 | 主界面已手机化，底部胶片条 / 更多菜单未适配（更多菜单可复用 `showMobileContextMenu`） | 胶片条横向可滑；更多菜单用底部弹层 | `viewer_page.dart`、`viewer_stage.dart`、`generation_viewer_wiring.dart` | M | ⬜ |
| G13 | 编辑图片页 | `tools_editor.dart` 无手机分支（工具竖栏 + 快捷键提示被裁） | 画布优先 + 底部工具条 + 参数弹层（同导演工具方案 A） | `tools_editor.dart` | L | ⬜ |
| G14 | 局部重绘 / 蒙版页 | 同上，桌面布局 | 同上 | 蒙版编辑页 | L | ⬜ |

## 4. 系统集成（可选项，P2）

| ID | 事项 | 目标 | 量级 | 状态 |
| --- | --- | --- | --- | --- |
| G15 | 分享图片到其他 App | `share_plus` 接入，替代桌面「复制/拖出」 | M | ⬜ |
| G16 | 从系统分享接收图片 | manifest 增加 `ACTION_SEND` + `image/*`，直接进 img2img / 参考图 | M | ⬜ |
| G17 | 应用内 APK 更新 | 桌面更新器不适用，接 APK 下载/安装（当前手动装包） | M | ⬜ |

## 5. 明确不做（桌面专属）

拖拽导入 / 拖出到文件夹、拖拽调栏宽、右键菜单、键盘快捷键（Ctrl+Enter / Ctrl+V / Ctrl+0）、
系统托盘与开机自启、窗口置顶 / 多窗口看图、输出目录与「打开所在文件夹」、
Windows 剪贴板历史粘贴、随包本地超分可执行文件。

## 6. 建议顺序

1. **第一批（S，约 0.5–1 天，建议先做）**：G1 画布长按菜单、G2 历史批次菜单、G3 悬停按钮常显、
   G6 隐藏本地超分卡片、G9 隐藏 Krita 桥接 —— 把「触屏点不出来」和「死按钮」清掉。
2. **第二批（M，约 1–2 天）**：G11 资源小窗手机全屏化、G12 查看器收尾、G4 触控目标、G5 走查验收。
3. **第三批（L）**：G13 编辑图片页手机化、G14 局部重绘页手机化、G10 后台生成、G15–G17 系统集成。
4. **另立项**：G8 本地超分引擎（Android 推理，不是移植工作量级）。

## 7. 验收口径

- `flutter analyze --no-pub` 干净；改动路径补对应 widget 测试（现有 `test/presentation/ui/gen`、`tools`）。
- 360×640 竖屏无 overflow；桌面三栏布局与 golden 不变。
- 真机（MuMu x86_64 / arm64）手测通过后再交付 APK。
