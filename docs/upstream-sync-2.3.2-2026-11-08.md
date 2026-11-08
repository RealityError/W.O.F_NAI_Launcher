# 上游 2.3.2 同步评估（2026-11-08）

> 用途：给「上游 2.3.2 要不要合、怎么合」做一次可讨论的事实基线。
> 评估方法：`git fetch` + `git merge-tree --write-tree` 离线合并预演 + 手机端可达性/符号引用 grep，**没有改动工作区、没有实际构建**。
> 局限：文本能自动合并 ≠ 能编译 ≠ 行为正确；合并后仍需 `flutter analyze` 与手机端 UI 回归（见 §7）。

---

## 0. 结论速览

| 问题 | 结论 |
|---|---|
| 上游更新了什么 | 2.3.2 一个发布提交承载全部改动，6 组功能，91 文件 +3515/−2371 |
| 会不会影响 Android 构建 | **不会**。`android/`、Gradle、NDK、Manifest、依赖都没动，`pubspec` 只改版本号 |
| 会不会影响 Android 界面 | **会**。24 个共享 UI 文件重叠，手机端布局分支就写在这些文件里 |
| GitHub 上能一键合并吗 | **不能**。1 个 modify/delete 冲突（`channel_overlay.dart`），且按 [AGENTS.md](../AGENTS.md) 约定不应直接 merge/cherry-pick |
| 建议 | 不整包合。只同步「画布 + 图库删除 + 设置提示 + Agent 图标」一组，其余暂缓（**2026-11-09 已按此执行第一组，实际只做画布组 #1+#2+#9，见 §11**） |

---

## 1. 事实基线

| 项 | 值 |
|---|---|
| 真上游 | `z15087716457-stack/W.O.F_NAI_Launcher`（`RealityError/*` 是 fork） |
| 上游 main | `61b0be1e` `release: prepare W.O.F NAI Studio 2.3.2`（2026-11-08，tag `v2.3.2`） |
| 上游基线 | `3ef6476b` `release: prepare W.O.F NAI Studio 2.3.1`（= 我们本地 `main`） |
| 2.3.2 规模 | 91 个文件，+3515 / −2371；`pubspec.yaml` 仅 `2.3.1+89 → 2.3.2+94`，**无依赖变化** |
| 当前分支 | `feat/android-port` @ `dae56dab`，含 12 个上游没有的提交（Android 地基 2 个 + 手机端 10 个） |
| 已合进 fork | `440da91d`、`4f91325e` 已随 PR #1 进入 fork `main`（`fdee992f`）；手机端 10 个提交尚未合 |
| 合并基准 | `git merge-base feat/android-port upstream/main` = `3ef6476b`（2.3.1 发布点） |

---

## 2. 上游 2.3.2 改了什么

| 组 | 内容 | 主要文件 |
|---|---|---|
| A. Agent | 「Anlas 小水滴」像素图标；侧栏/工具栏状态（空闲眨眼、运行跳动、待确认闪橙、结束亮绿）并遵循「减少动态效果」；Windows 侧栏展开/收起重绘修复 | `agent_mark.dart`(新)、`agent_glyphs.dart`(大改)、`agent_header/panel/contract`、`agent_toggle_badge/wiring`、`nai_agent_window_controller`、`win32_window.*` |
| B. 生图画布 | **移除右缘「视觉通道导航尺」与启动主题顺序提示**；自动聚焦按悬浮条实际边界垂直居中 | `channel_overlay.dart`(删 461 行)、`channel_contract/fixture/geometry`、`canvas_channel_provider`、`generation_canvas_view`、`gen_canvas`、`gen_contract`、`docs/guide/*/canvas.md`(5 语言) |
| C. 图库删除 | 统一新确认框；移入删除池只确认一次（注明重启前可恢复）；彻底删除单独确认；删除池改用带图标工具栏并显示数量 | `gallery_delete_dialog.dart`(新)、`gallery_delete_pool_store`、`gallery_trash_provider`、`local_gallery_screen`、`gallery_category_tree_view`、`resource_gallery_viewer` |
| D. 设置 | 保存/撤销提示随浅色深色主题 | `ui_colors`、`settings_personal`、`settings_page`、`settings_intel`、`settings_contract` |
| E. 快捷键 | F1 帮助/快捷键设置补列撤销、重做、画布导航等固定键，支持搜索与按键筛选 | `shortcut_guide.dart`(新)、`shortcut_help_dialog`(重写)、`shortcut_labels`、`settings_shortcuts` |
| F. 桌面杂项 | 查看器删除文案/流程统一（删 `protected` 概念）、Windows 窗口揭示、native 测试、README 截图工具、模型服务商页小改 | `viewer_contract/menus/page`、`image_viewer_wiring`、`windows/runner/*`、`test/native/*`、`tool/*`、`model_providers_page` |

---

## 3. GitHub 上能不能直接合并（预演结果）

预演命令（等价于 GitHub 的服务端合并，只算文本层）：

```powershell
git fetch https://github.com/z15087716457-stack/W.O.F_NAI_Launcher.git main:refs/remotes/upstream/main
git merge-tree --write-tree --name-only feat/android-port upstream/main   # exit 1 = 有冲突
```

### 3.1 硬冲突：1 处

| 文件 | 类型 | 说明 | 处理 |
|---|---|---|---|
| `lib/presentation/ui/channel/channel_overlay.dart` | modify/delete | 上游整文件删除（−461 行）；我们在 `440da91d` 里为手机窄屏改过 +4/−1（主题名最多显示 2 个） | 接受上游删除；我们的 4 行随功能作废 |

### 3.2 其余重叠文件（24 个）自动合并成功

- 叠加改动的重点：`gen_canvas.dart`（上游 140+/27− vs 我们 38+/23−）、`settings_personal.dart`（86+/32− vs 53+/6−）、`settings_page.dart`（13+/20− vs 108+/93−）、`local_gallery_screen.dart`（52+/114− vs 298+/6−）、`gen_prompt.dart`、`viewer_page.dart`、`gallery_timeline_view.dart`、`nai_agent_window_controller`、`image_viewer_wiring`、`nai_agent_generation_host`、`agent_toggle_wiring`、`settings_contract`、`gen_contract`、`pubspec.yaml`、10 个 l10n 文件。
- `pubspec.yaml` 自动合并会保留我们 Android 必需的 `super_clipboard/super_drag_and_drop ^0.9.1`（上游只改版本号行）。

### 3.3 悬空引用核验（合并结果树的 grep 结果）

| 被上游删除的符号 | 合并结果中的残留 |
|---|---|
| `ChannelOverlay` | 只在 `channel_overlay.dart` 自身（待删） |
| `ChannelActions` | 只在 `channel_overlay.dart` 自身（待删） |
| `CanvasChannelEntryNotice` / `canvasChannelEntryNoticeProvider` | 无 |
| `ViewerDeleteDialog`、`ViewerItem.protected` | 无 |
| 13 个 l10n key（`imageViewer_moveToTrash`、`imageViewer_protected*`、`localGallery_confirmBulkDelete*`、`localGallery_protectedDelete*`、`localGallery_deleteForeverConfirm`、`channel_toastTitle`、`channel_scrubWhen` 等） | 无 |
| `AssetProtectionGuard` | 上游保留（用于移动/复制/彻底删除等），合并结果中 8 个文件、19 处引用，正常 |

**结论**：解掉那 1 处冲突后，文本层没有已知的悬空引用；但不能据此断言可编译（见 §4.3、§7）。

### 3.4 为什么「即使能合也不建议一键合」

1. [AGENTS.md](../AGENTS.md) 明令：**不直接 merge 或 cherry-pick 上游提交；先观察差异，再实现所需功能**。
2. 2.3.2 是桌面发布，但改的是共享 UI；手机端受影响面需要逐项取舍（§5）。
3. 3.2 里若干文件是「上游重构 + 我们手机端改写」叠在同一处，文本自动合并的结果需要人读一遍。

---

## 4. 对 Android 的影响分级

### 4.1 不影响（平台/构建层）

- `android/`、Gradle、NDK、Manifest、`file_provider_paths.xml`、签名：上游 **0 改动**。
- 依赖：无新增/删除，仅版本号 `2.3.1+89 → 2.3.2+94`（Android `versionCode` 随之变 94，仍递增）。
- 纯桌面：`windows/runner/win32_window.*`、`test/native/window_reveal_surface_test.cpp`、`tool/readme_shots/*`、`tool/ui_shell/*`。
- **手机端自研文件 0 重叠**：`lib/presentation/mobile/*`、`mobile_local_gallery.dart`、`settings_mobile.dart`、`mobile_gallery_browse_sheet.dart`、`mobile_gallery_filter_sheet.dart`、`mobile_toolbar.dart` 上游都没改。

### 4.2 会影响（共享 UI，手机真会走到）

手机端不是独立页面树，而是同一批组件里用 `usesMobileLayout` 切布局，所以上游改这些文件就会改到手机：

| 上游改动 | 手机端入口 |
|---|---|
| B 画布（导航尺删除、自动聚焦） | `gen_canvas.dart:144`、`gen_page.dart:371`、`generation_canvas_view.dart`（生成页画布两端共用） |
| C 图库删除 | `local_gallery_screen.dart:300` 的 `MobileLocalGallery` 复用同一批 action：`deleteSelected`/`purgeTrashAll` → `_deleteSelectedImages`/`_purgeTrash`；合并后两者都改用新的 `GalleryDeleteDialog` |
| D 设置提示 | `settings_personal.dart:1791`、`settings_kit.dart:1369/1441` 等手机布局分支共用 |
| E 快捷键帮助 | 手机设置 → 快捷键页有「快捷键帮助」按钮（`settings_mobile.dart:530`），能打开重写后的帮助框 |
| A Agent 图标 | 生成页提示词区 `agentToggle`（`gen_prompt.dart:136`）+ `AgentMark` 图标；侧栏状态徽标是桌面语义 |
| F 查看器删除 | `viewer_page.dart:397/431` 手机分支共用，手机上「删除」交互会变 |

### 4.3 已核验的 API 迁移点（合并后仍可编译的依据）

| 变更 | 结论 |
|---|---|
| `AgentMark` 新 API：旧 `{size, color, stroke}` → 新 `{size=18, tileSize}`，类搬到 `agent_mark.dart`，`agent_glyphs.dart` 改为 `export 'agent_mark.dart'` | 旧调用点全部落在上游本次改过的文件里（`agent_glyphs`、`agent_header`、`agent_panel`、`settings_page`、`gen_prompt`），合并结果只剩新 API 调用；手机端没有别处使用 `AgentMark` |
| `UiColors` 构造新增 required `onError`，新增 `agentTile`/`agentPixels` | 构造点只在上游改过的 `ui_colors.dart` 内部 |
| `UiBtnTone.danger` 新增枚举值 | 全部 `switch` 只在上游改过的 `ui_lib_controls.dart`；其他 kit 文件无 `UiBtnTone` 引用 |
| `SettingsShortcut.fixed` 新增可选字段 | 加法变更，构造点兼容 |

---

## 5. 逐功能决策建议（核心讨论项）

| # | 上游功能 | 手机端可见性 | 建议 | 理由 / 注意 |
|---|---|---|---|---|
| 1 | 画布移除「通道导航尺」+ 主题顺序提示 | 可见（且我们为手机专门改过它） | **合** | 顺势解决唯一冲突；少一个手机端专属分支。代价：手机上这个装饰性导航条消失（产品确认） |
| 2 | 画布自动聚焦居中 | 可见 | **合** | 手机底部工具条更高，改动方向对手机有利；需真机验证垂直居中 |
| 3 | 图库删除统一新确认框 + 删除池工具栏/数量 | 可见；手机「移入删除池」和「彻底删除」都会换成新框 | **合，但要手机适配** | 新框是桌面弹层（固定 420 宽，`Dialog(insetPadding:16)`，手机上被压到屏宽）；手机图库里会变成「图片删除用新框、分类/合集删除仍用 `ThemedConfirmDialog`」。`galleryTrashCountProvider` 手机垃圾桶工具栏可直接用 |
| 4 | 查看器删除重构（删 `protected`/`ViewerDeleteDialog`，文案统一「移入删除池」） | 可见 | **跟 #3 绑定一起合** | 手机「受保护图」在移入删除池流程中不再二次确认（仅彻底删除确认）。上游理由是软删可恢复 → 需产品确认 |
| 5 | 设置保存/撤销提示随主题 | 可见 | **合** | 纯视觉、低风险 |
| 6 | Agent 像素图标 + 侧栏状态徽标 | 部分可见（图标可见；徽标是桌面常驻侧栏语义） | **只合图标，徽标单独立项** | `agent_toggle_badge` 重写了 `expanded`/2s 完成清理语义，手机上没有常驻侧栏，需重新设计 |
| 7 | 快捷键帮助重写 + 快捷键设置补键/搜索 | 可见入口，但手机无键盘 | **暂缓 / 不合** | 价值低；合了还要给一堆桌面键补手机标签 |
| 8 | Windows 侧栏重绘、`win32_window`、native 测试、`tool/*`、README 截图 | 不可见 | **不合** | 桌面专属 |
| 9 | `docs/guide/*/canvas.md` 5 语言画布文案 | 文档 | **跟随 #1 一起合** | 与导航尺删除配套 |

### 建议的同步范围（最小集）

- **第一组（建议做）**：#1 + #2 + #3 + #4 + #5 + #9 —— 冲突面只有 `channel_overlay.dart` 一处。
- **第二组（可选）**：#6 的图标部分。
- **暂不做**：#7、#8。

### l10n 说明

- 上游：新增 25 个 key、删除 13 个 key（均为真实 key，不含 `@` 元数据）。
- 我们：新增 3 个 key（`gen_recent`、`gen_recentHint`、`gen_unlockCamera`），与上游**无重名冲突**。
- 合并后必须以 ARB 为唯一源重新 `flutter gen-l10n`，不要手改 `app_localizations*.dart`；`app_zh_TW.arb` / `zh_tw_labels.dart` 走 `tool/l10n` 生成。

---

## 6. 合并方式选项

| 方案 | 做法 | 风险 |
|---|---|---|
| A. 手工移植第一组（**约定推荐**） | 按 diff 逐处改到 `feat/android-port`，不 cherry-pick | 工作量中等；可控，不需要解整包冲突 |
| B. 先试合并再回退 | 临时 worktree 合一次 → `flutter analyze` → 看错误清单 → 再决定 | 只读演练，不动工作区；能拿到真实编译错误 |
| C. 整体合入 | 解冲突后整包接受 2.3.2 | 会把桌面专属改动、桌面语义的 badge/快捷键一起带进手机端，回归面最大 |

版本号：整包合会变 `2.3.2+94`；若手机端要保持独立版本序列，手工移植时不要动版本号行。

---

## 7. 验收 / 回归清单（若决定同步）

1. `flutter analyze`（或 `dart analyze lib`）无新增错误。
2. `flutter gen-l10n` 成功；确认 13 个被删 key 在代码里无引用、3 个新 key 各语言齐全。
   生成源码缺失时构建脚本会直接拒绝，合并后还需按约定跑 `dart run tool/generate.dart`（入口读取 `.devin/codegen.json`）。
3. 手机端 UI 回归（真机）：
   - 生成页：画布（导航尺消失后的布局、自动聚焦居中）、提示词工具菜单、底部生成条；
   - 图库：批量选中删除 → 删除池 → 全部恢复 / 彻底删除（新确认框在窄屏的宽度与按钮换行）；
   - 查看器：删除入口与文案；
   - 设置：保存/撤销提示在浅色深色下、快捷键页帮助按钮。
4. Android 构建 + 安装：`scripts/build_android.ps1 -Mode release`（默认 arm64；模拟器用 `-TargetPlatform android-x64`），确认 APK 可装可启动。注意该脚本的 release 目前仍用 debug 签名，不可发布；Android 构建说明见 [docs/android-port.md](android-port.md)。
5. 桌面端：确认 `usesMobileLayout == false` 路径未被手机端改动污染（启动 + 生成页 + 图库扫一眼即可）。

---

## 8. 未决问题（需要与主 agent 讨论拍板）

1. 手机上「受保护图」在移入删除池时取消二次确认，是否可以接受？
2. 图库新删除确认框在手机上是否要改成底部面板（`mobile_sheet`）风格，还是先沿用整宽弹层？
3. Agent 状态徽标（眨眼/运行/完成 2s 清理）是否跟进？若跟进，手机端语义怎么定义？
4. 快捷键帮助/快捷键设置本次是否合入（手机无键盘，价值低）？
5. 采用哪种合并方式（§6 A/B/C）？是否先跑一次 B 拿真实 analyze 结果？
6. 版本号：跟随 `2.3.2+94`，还是手机端另起？
7. 「视觉通道导航尺」是否确定在手机端也彻底去掉？
8. 是否先把 `feat/android-port` 的 10 个手机端提交合进 fork `main`（这一步是干净可合的），再做上游同步？

---

## 9. 复现命令

```powershell
# 1) 拉上游（不新增 remote 配置）
git fetch https://github.com/z15087716457-stack/W.O.F_NAI_Launcher.git main:refs/remotes/upstream/main

# 2) 看上游本次改了什么
git log --oneline 3ef6476b..upstream/main
git diff --stat 3ef6476b upstream/main

# 3) 预演合并（只算文本，不动工作区；exit 1 表示有冲突）
git merge-tree --write-tree --name-only feat/android-port upstream/main

# 4) 悬空引用核验（把 <tree> 换成上一步输出的 tree id）
git grep -nE "ChannelOverlay|ChannelActions|ViewerDeleteDialog|\.protected|imageViewer_moveToTrash" <tree> -- lib

# 5) l10n key 对比
git diff 3ef6476b upstream/main -- lib/l10n/app_en.arb
```

---

## 10. 参考

- 上游 [CHANGELOG.md](../CHANGELOG.md) 2.3.2 节
- 上游 PR：`z15087716457-stack/W.O.F_NAI_Launcher#19`（2.3.0 整合记录）。上游 PR 列表最新为 #20（已关闭、无 open PR），2.3.2 的发布提交在仓库内无对应 PR 记录
- 手机端适配现状：[docs/mobile-adaptation.md](mobile-adaptation.md)、[docs/android-port.md](android-port.md)
- 约定：[AGENTS.md](../AGENTS.md)

---

## 11. 执行记录（2026-11-09）

用户拍板：**只做画布组**（§5 #1 + #2 + #9），其余暂缓。实现方式按 §6 方案 A（手工移植，不 merge / 不 cherry-pick）。

### 已移植

| 项 | 文件 | 说明 |
|---|---|---|
| 删除通道导航尺 + 进入提示 | `lib/presentation/ui/channel/channel_overlay.dart`（删除）、`channel_contract.dart`、`channel_fixture.dart`、`channel_geometry.dart`、`providers/canvas_channel_provider.dart`、`screens/generation/widgets/canvas/generation_canvas_view.dart`、`wiring/generation_canvas_wiring.dart` | 上游整文件删除 −461 行，其余按 2.3.2 精简（`ChannelActions`、`canvasChannelEntryNoticeProvider` 一并移除） |
| 自动聚焦居中 | `lib/presentation/ui/gen/gen_canvas.dart`、`gen_contract.dart` | 用 `_TopBar/_InfoBar/_ActionBar` 实测悬浮条内侧边界，`focusPaddingOf` 取代固定留白；`_BottomBars.infoOffset` 供占位兜底 |
| 保留手机分支 | `gen_canvas.dart` | 8.8 的 `usesMobileLayout`「工具面板贴底铺宽」分支重新应用；440da91d 在 `channel_overlay.dart` 的窄屏主题名 4→2 行随文件删除作废 |
| 文档 | `docs/guide/{en,ja,ko,zh-CN,zh-TW}/canvas.md` | 跟随上游 |
| 工具/读图脚本 | `tool/readme_shots/*`、`tool/ui_shell/*` | 跟随上游（仅开发工具） |
| 测试 | `test/presentation/ui/channel/*`、`test/presentation/providers/canvas_channel_provider_test.dart`、`test/presentation/wiring/generation_canvas_wiring_test.dart` | 跟随上游 |

### 未移植（维持原状）

- #3 + #4 图库删除确认框 / 删除池 / 查看器删除重构：涉及手机弹层适配与「受保护图」产品决策，待单独排期。
- #5 设置提示配色（`tipInk→ink` 等 token 迁移）、#6 Agent 像素图标：可选，非本轮范围。
- #7 快捷键帮助、#8 Windows/README/native：不合。

### 验证

- `flutter analyze --no-pub`：No issues。
- `flutter test`：channel + 画布接线 183 例；`test/presentation/ui/gen` 374 例；生图接线核心 6 文件 133 例 —— 全通过。
- `dart format`：改动文件 0 changed。
- 版本保持 `2.3.1+89`，未跟随上游 `2.3.2+94`。
- 手机端表现：画布右缘不再有刻度条、启动不再弹「本次通道」主题提示；生成占位/结果按底部工具条实测边界居中（更贴合手机更高的生成条）。
