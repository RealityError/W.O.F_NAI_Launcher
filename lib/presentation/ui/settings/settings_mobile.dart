import 'package:flutter/material.dart';

import '../../../core/utils/localization_extension.dart';
import '../../mobile/mobile_breakpoints.dart';
import '../../mobile/mobile_list.dart';
import '../../mobile/mobile_scaffold.dart';
import '../kit/ui_colors.dart';
import 'settings_contract.dart';
import 'settings_format.dart';
import 'settings_kit.dart';
import 'settings_scope.dart';
import 'settings_search.dart';

/// 是否使用手机端设置布局（桌面端恒为 false）。
///
/// Android 上由 [usesMobileLayout] 打开；widget 测试里可用
/// [debugForceMobileSettingsLayout]（定义在 `settings_contract.dart`）强制。
bool get settingsUsesMobileLayout =>
    usesMobileLayout || debugForceMobileSettingsLayout;

/// 手机端设置页：分组列表 → 详情页。
///
/// 桌面端 [SettingsPage] 的双栏布局保持原样；这里只负责手机端外壳：
/// - 列表页：按 [SettingsGroup] 分组的页面列表，每行图标 + 标题 + 说明 + 当前值；
/// - 详情页：`MobilePageScaffold` + 复用桌面页内容（[pageBuilder]），返回键 / 左上返回都回列表；
/// - 搜索：本地复用 [settingsSearch] 索引，命中后进入对应详情并高亮锚点；
/// - 深链：`initialQuery` 直接进入搜索结果，`initialAnchor` 直接打开锚点所在页面；
/// - 未保存草稿：切页 / 返回前复用桌面 [guard] 的确认逻辑。
///
/// 数据、回调、搜索高亮都从祖先 [SettingsScope] 取；页面内容由
/// [SettingsPage] 通过 [pageBuilder] 传入，避免重写各设置页。
class MobileSettingsView extends StatefulWidget {
  const MobileSettingsView({
    super.key,
    required this.data,
    required this.pageBuilder,
    required this.guard,
    this.initialQuery = '',
    this.initialAnchor,
    this.toast,
    this.onDismissToast,
  });

  /// 与 [SettingsScope.data] 相同；单独传入是为了在 [didUpdateWidget] 里
  /// 识别外部（深链 / 账号页请求）切页。
  final SettingsViewData data;

  /// 桌面页内容映射（`SettingsPage._pageOf`），保证手机端复用的是同一套组件。
  final Widget Function(SettingsPageId page) pageBuilder;

  /// 切页 / 返回前的未保存草稿确认，沿用桌面 `SettingsPage._guard`。
  final void Function(VoidCallback go) guard;

  final String initialQuery;
  final String? initialAnchor;

  /// 底部“已保存 · 撤销”浮条（由 [SettingsPage] 的改动计时器驱动）。
  final SettingsChange? toast;
  final VoidCallback? onDismissToast;

  @override
  State<MobileSettingsView> createState() => _MobileSettingsViewState();
}

class _MobileSettingsViewState extends State<MobileSettingsView> {
  /// null = 列表页；否则显示该页详情。
  SettingsPageId? _detail;
  late final TextEditingController _search = TextEditingController(
    text: widget.initialQuery.trim(),
  );
  var _query = '';
  var _initialized = false;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery.trim();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final anchor = widget.initialAnchor?.trim();
    if (anchor != null && anchor.isNotEmpty) {
      final target = _pageForAnchor(context, anchor);
      if (target != null) {
        _detail = target;
      } else {
        // 锚点失效时退回列表（概览是列表根页），不强行打开概览详情。
        final page = settingsAvailablePage(widget.data.page);
        if (page != SettingsPageId.overview) _detail = page;
      }
      return;
    }
    // 外部深链（例如 ?section=account）直接进对应详情；概览作为列表根页。
    if (_query.isEmpty) {
      final page = settingsAvailablePage(widget.data.page);
      if (page != SettingsPageId.overview) _detail = page;
    }
  }

  @override
  void didUpdateWidget(covariant MobileSettingsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 接线方从外部切页（账号 / 桥接打开请求、页面内 jump）时同步详情页；
    // 本组件自己打开详情时已先写好 _detail，这里不会重复。
    if (widget.data.page != oldWidget.data.page) {
      final next = settingsAvailablePage(widget.data.page);
      if (_detail != next) _detail = next;
    }
    if (widget.initialQuery != oldWidget.initialQuery) {
      final query = widget.initialQuery.trim();
      if (query.isNotEmpty && query != _query) {
        _query = query;
        _search.text = query;
      }
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// 深链锚点 → 所属页面：锚点与搜索命中的 anchor 一致，直接复用搜索索引。
  SettingsPageId? _pageForAnchor(BuildContext context, String anchor) {
    for (final hit in settingsIndex(context)) {
      if (hit.anchor == anchor && settingsPageAvailable(hit.page)) {
        return hit.page;
      }
    }
    return null;
  }

  /// 打开详情页：先走桌面同款未保存草稿确认，再同步接线方页面与高亮。
  void _openPage(SettingsScope scope, SettingsPageId page, {String? anchor}) {
    final target = settingsAvailablePage(page);
    widget.guard(() {
      if (!mounted) return;
      setState(() {
        _detail = target;
        _query = '';
        _search.text = '';
      });
      scope.jump(target, anchor: anchor);
    });
  }

  /// 详情页返回列表（同样先确认未保存草稿）。
  void _backToRoot() {
    widget.guard(() {
      if (!mounted) return;
      setState(() => _detail = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = SettingsScope.of(context);
    final page = _detail;
    if (page != null) return _buildDetail(context, scope, page);
    return _buildList(context, scope);
  }

  // ───────────────────────────── 列表页 ─────────────────────────────

  Widget _buildList(BuildContext context, SettingsScope scope) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final searching = _query.trim().isNotEmpty;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: TextField(
            key: const Key('settings-mobile-search-input'),
            controller: _search,
            textInputAction: TextInputAction.search,
            style: theme.textTheme.bodyMedium,
            decoration: InputDecoration(
              hintText: l.set_search,
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      key: const Key('settings-mobile-search-clear'),
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
              isDense: true,
              filled: true,
              fillColor: scheme.surfaceContainerHighest.withValues(alpha: .5),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) => setState(() => _query = value),
            onSubmitted: (_) {
              final hits = settingsSearch(context, _query.trim());
              if (hits.length == 1) {
                _openPage(scope, hits.single.page, anchor: hits.single.anchor);
              }
            },
          ),
        ),
        Expanded(
          child: searching
              ? _buildSearchResults(context, scope)
              : _buildPageList(context, scope),
        ),
      ],
    );
    return MobilePageScaffold(
      title: l.set_title,
      showBack: false,
      child: widget.toast != null && !searching
          ? _withToast(context, scope, widget.toast!, body)
          : body,
    );
  }

  Widget _buildPageList(BuildContext context, SettingsScope scope) {
    final data = widget.data;
    final items = <Widget>[];
    SettingsGroup? last;
    for (final page in SettingsPageId.values.where(settingsPageAvailable)) {
      if (page.group != last && page.group != SettingsGroup.none) {
        items.add(
          MobileSectionHeader(title: SettingsFormat.group(context, page.group)),
        );
      }
      last = page.group;
      items.add(_pageTile(context, scope, page));
    }
    items.add(
      _ListFooter(
        version: data.version,
        updateAvailable: data.about.update == SettingsUpdateState.available,
        onOpenAbout: () => _openPage(scope, SettingsPageId.about),
      ),
    );
    return ListView(
      key: const Key('settings-mobile-list'),
      padding: const EdgeInsets.only(bottom: 24),
      children: items,
    );
  }

  Widget _pageTile(
    BuildContext context,
    SettingsScope scope,
    SettingsPageId page,
  ) {
    return MobileListTile(
      key: Key('settings-mobile-page-${page.name}'),
      icon: _pageIcon(page),
      title: SettingsFormat.page(context, page),
      subtitle: _pageDescription(context, page),
      trailing: _pageMeta(context, page),
      onTap: () => _openPage(scope, page),
    );
  }

  /// 手机列表里的页面图标。桌面目录里少数页面用自绘字形，这里退化为
  /// Material 图标（手机端列表行只接受 [IconData]）。
  IconData _pageIcon(SettingsPageId page) {
    final format = SettingsFormat.icon(page);
    return format.icon ??
        switch (page) {
          SettingsPageId.overview => Icons.dashboard_outlined,
          SettingsPageId.canvas => Icons.crop_free_rounded,
          SettingsPageId.agent => Icons.auto_awesome_outlined,
          SettingsPageId.rag => Icons.hub_outlined,
          SettingsPageId.network => Icons.public_rounded,
          SettingsPageId.backup => Icons.backup_outlined,
          _ => Icons.settings_outlined,
        };
  }

  /// 每个页面的说明文案（复用各页标题下方的描述，不新增文案）。
  String _pageDescription(BuildContext context, SettingsPageId page) {
    final l = context.l10n;
    return switch (page) {
      SettingsPageId.overview => l.set_ovDesc,
      SettingsPageId.account => l.set_accDesc,
      SettingsPageId.appearance => l.set_apDesc,
      SettingsPageId.canvas => l.set_cvDesc,
      SettingsPageId.shortcuts => l.set_scDesc,
      SettingsPageId.generation => l.set_gnDesc,
      SettingsPageId.storage => l.set_stDesc,
      SettingsPageId.dictionaries => l.set_dcDesc,
      SettingsPageId.models => l.set_mdDesc,
      SettingsPageId.agent => l.set_agDesc,
      SettingsPageId.rag => l.set_rgDesc,
      SettingsPageId.upscale => l.set_upDesc,
      SettingsPageId.bridges => l.set_brDesc,
      SettingsPageId.network => l.set_nwDesc,
      SettingsPageId.privacy => l.set_pvDesc,
      SettingsPageId.backup => l.set_bkDesc,
      SettingsPageId.about => l.set_abDesc,
    };
  }

  /// 行尾当前值摘要（延续桌面目录右侧读数/状态点的口径）。
  Widget? _pageMeta(BuildContext context, SettingsPageId page) {
    final l = context.l10n;
    final d = widget.data;
    Widget label(String text) => MobileValueLabel(text: text);
    final Widget? meta = switch (page) {
      SettingsPageId.overview => null,
      SettingsPageId.account => () {
        final current = d.account.current;
        if (current == null) return null;
        final tier = current.tier;
        return label(
          tier == null || tier == SettingsTier.none
              ? current.name
              : SettingsFormat.tier(tier),
        );
      }(),
      SettingsPageId.appearance => label(
        SettingsFormat.choice(
          context,
          SettingKey.themeMode,
          d.values.text(SettingKey.themeMode) ?? 'system',
        ),
      ),
      SettingsPageId.canvas => label(
        SettingsFormat.choice(
          context,
          SettingKey.outputViewer,
          d.values.text(SettingKey.outputViewer) ?? 'canvas',
        ),
      ),
      SettingsPageId.shortcuts =>
        d.shortcuts.shortcuts.isEmpty
            ? null
            : label(SettingsFormat.count(d.shortcuts.shortcuts.length)),
      SettingsPageId.generation =>
        d.generation.estimate == null
            ? null
            : label('${d.generation.estimate!.cost} Anlas'),
      SettingsPageId.storage =>
        d.storage.imageCount == 0
            ? null
            : label(l.set_stCount(SettingsFormat.count(d.storage.imageCount))),
      SettingsPageId.dictionaries =>
        d.dictionaries.tagCount == 0
            ? null
            : label(
                l.set_dcEntries(SettingsFormat.count(d.dictionaries.tagCount)),
              ),
      SettingsPageId.models => () {
        final providers = d.models.providers;
        if (providers.isEmpty) return null;
        final enabled = providers.where((p) => p.enabled).length;
        final hasError = providers.any((p) => p.status == SettingsTone.error);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasError) ...[
              const SettingsDot(SettingsTone.error),
              const SizedBox(width: 6),
            ],
            label(l.set_mdProviderCount('$enabled')),
          ],
        );
      }(),
      SettingsPageId.bridges => () {
        final bridges = d.bridges;
        final comfyDown =
            d.values.flag(SettingKey.comfyEnabled) &&
            bridges.comfyTone == SettingsTone.error;
        if (comfyDown) return const SettingsDot(SettingsTone.warn);
        return bridges.kritaConnected || bridges.agentClients > 0
            ? const SettingsDot(SettingsTone.ok)
            : null;
      }(),
      SettingsPageId.privacy => label(
        '${_privacyEnabledCount(d)}/${_privacyProtectionKeys.length}',
      ),
      SettingsPageId.backup =>
        d.backup.lastImportAt == null
            ? null
            : label(SettingsFormat.ago(context, d.backup.lastImportAt!, d.now)),
      SettingsPageId.about =>
        d.about.update == SettingsUpdateState.available
            ? const SettingsDot(SettingsTone.error)
            : null,
      // 手机端隐藏的页面不会出现在列表里，保留分支保证 switch 完整。
      SettingsPageId.agent ||
      SettingsPageId.rag ||
      SettingsPageId.upscale ||
      SettingsPageId.network => null,
    };
    if (meta == null) return null;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 112),
      child: meta,
    );
  }

  static const _privacyProtectionKeys = [
    SettingKey.stripMetadata,
    SettingKey.confirmExternalSend,
    SettingKey.confirmDangerous,
    SettingKey.noOverwrite,
  ];

  int _privacyEnabledCount(SettingsViewData data) =>
      _privacyProtectionKeys.where(data.values.flag).length;

  /// 搜索结果：复用桌面搜索索引，点一条直接进详情并高亮锚点。
  Widget _buildSearchResults(BuildContext context, SettingsScope scope) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final query = _query.trim();
    final hits = settingsSearch(context, query);
    if (hits.isEmpty) {
      return ListView(
        key: const Key('settings-mobile-search-empty'),
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
        children: [
          Text(
            l.set_searchEmpty(query),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l.set_searchEmptyHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      key: const Key('settings-mobile-search-results'),
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: hits.length,
      itemBuilder: (context, index) {
        final hit = hits[index];
        return MobileListTile(
          key: Key('settings-mobile-hit-${hit.anchor}'),
          title: hit.title,
          subtitle: hit.detail.isEmpty ? hit.section : hit.detail,
          trailingText: SettingsFormat.page(context, hit.page),
          onTap: () => _openPage(scope, hit.page, anchor: hit.anchor),
        );
      },
    );
  }

  // ───────────────────────────── 详情页 ─────────────────────────────

  Widget _buildDetail(
    BuildContext context,
    SettingsScope scope,
    SettingsPageId page,
  ) {
    final content = KeyedSubtree(
      key: ValueKey('settings-mobile-content-${page.name}'),
      child: widget.pageBuilder(page),
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backToRoot();
      },
      child: MobilePageScaffold(
        key: Key('settings-mobile-detail-${page.name}'),
        title: SettingsFormat.page(context, page),
        onBack: _backToRoot,
        actions: _detailActions(context, scope, page),
        child: widget.toast == null
            ? content
            : _withToast(context, scope, widget.toast!, content),
      ),
    );
  }

  /// 详情页右上操作：桌面页头里无法通过内容区触发的操作（手机端行内
  /// 恢复默认只在 hover 时出现，必须在这里给入口）。
  List<Widget> _detailActions(
    BuildContext context,
    SettingsScope scope,
    SettingsPageId page,
  ) {
    final l = context.l10n;
    final actions = scope.actions;
    final changed = widget.data.modified
        .where((key) => SettingSpec.of(key).page == page)
        .length;
    return switch (page) {
      SettingsPageId.appearance ||
      SettingsPageId.canvas ||
      SettingsPageId.generation => [
        if (changed > 0)
          MobileHeaderAction(
            key: const Key('settings-mobile-reset-page'),
            icon: Icons.undo_rounded,
            tooltip: l.set_resetPage,
            onTap: () => _confirmResetPage(context, scope, page, changed),
          ),
      ],
      SettingsPageId.shortcuts => [
        MobileHeaderAction(
          key: const Key('settings-mobile-shortcut-help'),
          icon: Icons.keyboard_outlined,
          tooltip: l.set_scHelp,
          onTap: actions.onShowShortcutHelp,
        ),
      ],
      SettingsPageId.models => [
        MobileHeaderAction(
          key: const Key('settings-mobile-model-import'),
          icon: Icons.file_download_outlined,
          tooltip: l.set_mdImport,
          onTap: actions.onImportModelConfig,
        ),
        MobileHeaderAction(
          key: const Key('settings-mobile-model-add'),
          icon: Icons.add_rounded,
          tooltip: l.set_mdAddProvider,
          onTap: () =>
              scope.jump(SettingsPageId.models, anchor: 'provider-add'),
        ),
        if (widget.data.models.workbench != null)
          MobileHeaderAction(
            key: const Key('settings-mobile-model-copy'),
            icon: Icons.copy_rounded,
            tooltip: l.set_bkCopyConfig,
            onTap: actions.onCopyModelConfig,
          ),
      ],
      SettingsPageId.about => [
        MobileHeaderAction(
          key: const Key('settings-mobile-check-update'),
          icon: Icons.refresh_rounded,
          tooltip: l.set_abCheck,
          onTap: widget.data.about.update == SettingsUpdateState.checking
              ? null
              : actions.onCheckUpdate,
        ),
      ],
      _ => const <Widget>[],
    };
  }

  void _confirmResetPage(
    BuildContext context,
    SettingsScope scope,
    SettingsPageId page,
    int changed,
  ) {
    final l = context.l10n;
    scope.confirm(
      title: l.set_resetPageTitle(SettingsFormat.page(context, page)),
      body: l.set_resetPageBody('$changed'),
      confirm: l.set_resetDefault,
      danger: true,
      onConfirm: () => scope.actions.onResetPage(page),
    );
  }

  // ───────────────────────────── 浮条 ─────────────────────────────

  /// 底部“已保存 · 撤销”（手机端去掉 Ctrl+Z 键帽提示）。
  Widget _withToast(
    BuildContext context,
    SettingsScope scope,
    SettingsChange change,
    Widget child,
  ) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: _MobileSavedDock(
            key: const Key('settings-mobile-toast'),
            change: change,
            onUndo: () {
              scope.actions.onUndo(change.id);
              widget.onDismissToast?.call();
            },
          ),
        ),
      ],
    );
  }
}

/// 设置页列表底部的版本文案；有新版本时可直接进入“关于”。
class _ListFooter extends StatelessWidget {
  const _ListFooter({
    required this.version,
    required this.updateAvailable,
    required this.onOpenAbout,
  });

  final String version;
  final bool updateAvailable;
  final VoidCallback onOpenAbout;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Column(
        children: [
          Text(
            version,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (updateAvailable)
            InkWell(
              key: const Key('settings-mobile-update-badge'),
              onTap: onOpenAbout,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  child: Text(
                    l.set_hasUpdate,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 手机端“已保存 · 撤销”浮条。
class _MobileSavedDock extends StatelessWidget {
  const _MobileSavedDock({
    super.key,
    required this.change,
    required this.onUndo,
  });

  final SettingsChange change;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.ui;
    final theme = Theme.of(context);
    return Material(
      color: c.tipBg,
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        child: Row(
          children: [
            Icon(Icons.check_rounded, size: 18, color: c.ok),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l.set_savedChange(change.title, change.from, change.to),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: c.tipInk),
              ),
            ),
            if (change.undoable)
              InkWell(
                key: Key('settings-mobile-undo-${change.id}'),
                borderRadius: BorderRadius.circular(8),
                onTap: onUndo,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 44,
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        l.set_undo,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: c.tipInk,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
