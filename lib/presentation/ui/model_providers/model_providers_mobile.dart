part of 'model_providers_page.dart';

// ───────────────────────── 手机端服务商工作台 ─────────────────────────
//
// 三栏工作台在 360dp 放不下：手机端改成
//   服务商列表（本文件）→ 全屏编辑页（连接 / 请求 / 模型列表）→ 模型参数底部弹层。
// 桌面端继续走 model_providers_page.dart 里的三栏布局，互不影响。

/// 手机端服务商页：列表 + 添加入口；点一项推入全屏编辑页。
class _MobileProvidersView extends StatefulWidget {
  const _MobileProvidersView({required this.panel});

  final ModelProvidersPanelState panel;

  @override
  State<_MobileProvidersView> createState() => _MobileProvidersViewState();
}

class _MobileProvidersViewState extends State<_MobileProvidersView> {
  ModelProvidersPanelState get panel => widget.panel;
  ProvidersController get ctrl => panel.ctrl;

  /// 正在推“添加服务商”全屏页，避免重复 push。
  var _opening = false;

  /// 搜索跳转的 `provider-<id>` 只打开一次。
  String? _openedProvider;

  @override
  void initState() {
    super.initState();
    ctrl.addListener(_changed);
  }

  @override
  void dispose() {
    ctrl.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (ctrl.pickerOpen && !_opening) {
      _opening = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _openPicker());
    }
  }

  Future<void> _openEditor(String providerId) async {
    ctrl.select(providerId);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            _MobileProviderEditorPage(panel: panel, providerId: providerId),
      ),
    );
  }

  Future<void> _openPicker() async {
    if (!mounted) {
      _opening = false;
      return;
    }
    final actions = panel.widget.actions;
    final picker = ProvidersPicker(
      mobile: true,
      presets: panel.widget.data.presets,
      existing: {
        for (final x in panel.widget.data.providers)
          if (x.presetId != null) x.presetId!,
      },
      onClose: () => _closePicker(),
      onCancelSignIn: actions.onCancelAccountSignIn,
      onPick: (id, {required waitForSignIn}) async {
        if (!waitForSignIn) _closePicker();
        final created = await actions.onCreate(id);
        if (created == null) return false;
        ctrl.select(created);
        if (waitForSignIn) _closePicker();
        return true;
      },
    );
    // 消费深链请求，关闭后不会再次弹出。
    ctrl.pickerOpen = false;
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => picker));
    _opening = false;
  }

  void _closePicker() {
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final data = panel.widget.data;
    // 搜索跳转 `provider-<id>`：直接打开对应服务商的编辑页（只在搜索高亮期间触发一次）。
    final target = panel.widget.selectedId;
    final highlight = SettingsScope.maybeOf(context)?.highlight;
    if (target != null &&
        target != _openedProvider &&
        highlight == 'provider-$target') {
      _openedProvider = target;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && data.providers.any((p) => p.id == target)) {
          _openEditor(target);
        }
      });
    }
    if (data.providers.isEmpty) {
      return _Empty(
        onAdd: () {
          if (_opening) return;
          _opening = true;
          _openPicker();
        },
      );
    }
    final selected = ctrl.selectedOf(data);
    return Column(
      key: const Key('mp-mobile'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MobileSectionHeader(
          title: l.set_mdProviders,
          trailing: _MobileAddButton(
            key: const Key('mp-mobile-add'),
            tooltip: l.mp_pickerTitle,
            onTap: () {
              if (_opening) return;
              _opening = true;
              _openPicker();
            },
          ),
        ),
        for (final p in data.providers)
          _MobileProviderTile(
            key: Key('mp-provider-${p.id}'),
            item: p,
            changes: ctrl.changes(p),
            selected: selected?.id == p.id,
            onTap: () => _openEditor(p.id),
          ),
        const SizedBox(height: 14),
      ],
    );
  }
}

/// 手机端服务商行：48dp 以上触摸目标，带品牌图标、模型数和未保存圆点。
class _MobileProviderTile extends StatelessWidget {
  const _MobileProviderTile({
    super.key,
    required this.item,
    required this.changes,
    required this.selected,
    required this.onTap,
  });

  final ProviderItem item;
  final int changes;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ui;
    final l = context.l10n;
    final settings = item.settings;
    final subtitle = !item.enabled
        ? l.set_mdDisabled
        : l.set_mdModelCount('${settings.models.length}');
    return Material(
      color: selected ? c.accent.withValues(alpha: .06) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Row(
              spacing: 12,
              children: [
                ProviderLogo.of(item, size: 30),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        settings.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: UiText.sans(
                          13.5,
                          weight: FontWeight.w500,
                          color: c.ink,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: UiText.sans(11.5, color: c.muted),
                      ),
                    ],
                  ),
                ),
                if (changes > 0)
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: c.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                Icon(Icons.chevron_right_rounded, size: 22, color: c.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 手机端“添加服务商”入口：48dp 触摸目标。
class _MobileAddButton extends StatelessWidget {
  const _MobileAddButton({
    super.key,
    required this.tooltip,
    required this.onTap,
  });

  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ui;
    return Tooltip(
      message: tooltip,
      child: UiPressable(
        onTap: onTap,
        builder: (context, hover) => Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: hover ? c.hover : c.card,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: c.border),
            ),
            child: UiGlyph(UiGlyphs.plus, size: 15, color: c.ink),
          ),
        ),
      ),
    );
  }
}

/// 手机端服务商全屏编辑页：连接 / 请求 / 模型列表 + 底部保存条。
class _MobileProviderEditorPage extends StatefulWidget {
  const _MobileProviderEditorPage({
    required this.panel,
    required this.providerId,
  });

  final ModelProvidersPanelState panel;
  final String providerId;

  @override
  State<_MobileProviderEditorPage> createState() =>
      _MobileProviderEditorPageState();
}

class _MobileProviderEditorPageState extends State<_MobileProviderEditorPage> {
  ModelProvidersPanelState get panel => widget.panel;
  ProvidersController get ctrl => panel.ctrl;

  ProviderItem? get _item => panel.widget.data.providers
      .where((p) => p.id == widget.providerId)
      .firstOrNull;

  @override
  Widget build(BuildContext context) {
    final c = context.ui;
    final item = _item;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: c.rowLine),
        ),
        title: Text(
          item?.settings.name ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: UiText.sans(16, weight: FontWeight.w600, color: c.ink),
        ),
      ),
      body: SafeArea(
        top: false,
        child: item == null
            ? const SizedBox.shrink()
            : ListenableBuilder(
                listenable: Listenable.merge([ctrl, panel.dataRevision]),
                builder: (context, _) {
                  final cur = _item;
                  if (cur == null) {
                    _popNextFrame(context);
                    return const SizedBox.shrink();
                  }
                  final actions = panel.widget.actions;
                  final changes = ctrl.changes(cur);
                  final showDock =
                      changes > 0 || ctrl.draft(cur.id)?.result != null;
                  // 目录模式：桌面端靠右栏勾选面板提交，手机端没有右栏，
                  // 底部必须常驻「添加 N 个模型」条，否则勾选后无法提交。
                  final picking =
                      ctrl.mode(cur.id) == ProvidersListMode.catalog;
                  final picks = ctrl.picks(cur.id).toList();
                  return Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          key: const Key('mp-mobile-editor-scroll'),
                          padding: const EdgeInsets.only(bottom: 24),
                          child: cur.managedAccount
                              ? _AccountDetails(item: cur, actions: actions)
                              : _Middle(
                                  key: const Key('mp-mobile-middle'),
                                  panel: panel,
                                  item: cur,
                                  inlineInspector: false,
                                  onModelTap: (m) =>
                                      _openModelInspector(context, cur, m),
                                  onDeleteProvider: () =>
                                      _confirmDeleteProvider(cur),
                                ),
                        ),
                      ),
                      if (showDock)
                        _SaveDock(
                          item: cur,
                          ctrl: ctrl,
                          compact: true,
                          onSave: () => ctrl.save(cur, actions),
                        ),
                      if (picking)
                        _MobileCatalogDock(
                          item: cur,
                          ctrl: ctrl,
                          picks: picks,
                          onAdd: () {
                            final ids = List<String>.of(picks);
                            actions.onAddModels(cur.id, ids);
                            ctrl
                              ..clearPicks(cur.id)
                              ..setMode(cur.id, ProvidersListMode.added);
                            if (ids.isNotEmpty) {
                              ctrl.selectModel(cur.id, ids.first);
                            }
                          },
                        ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  void _popNextFrame(BuildContext context) {
    final nav = Navigator.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && nav.canPop()) nav.pop();
    });
  }

  /// 移除模型：编辑页是独立路由，设置页内的确认层被它盖住，必须用本地对话框。
  Future<void> _confirmRemoveModel(
    BuildContext sheetContext,
    ProviderItem item,
    ProviderModelSettings model,
  ) async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: SettingsConfirmDialog(
          title: l.mp_removeTitle(model.id),
          body: l.mp_removeBody,
          confirm: l.mp_removeModel,
          danger: true,
        ),
      ),
    );
    if (ok != true) return;
    panel.widget.actions.onRemoveModel(item.id, model.id);
    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
  }

  /// 删除服务商：同上，确认框必须留在编辑页自己的路由里。
  Future<void> _confirmDeleteProvider(ProviderItem item) async {
    final l = context.l10n;
    final name = ctrl.display(item).name;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: SettingsConfirmDialog(
          title: l.set_mdDeleteTitle(name),
          body: l.set_mdDeleteBody,
          confirm: l.set_delete,
          danger: true,
        ),
      ),
    );
    if (ok != true) return;
    ctrl.discard(item.id);
    panel.widget.actions.onDelete(item.id);
  }

  /// 模型参数：从底部弹出，复用桌面右栏的检查器。
  Future<void> _openModelInspector(
    BuildContext context,
    ProviderItem item,
    ProviderModelSettings model,
  ) {
    final c = context.ui;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => ListenableBuilder(
        listenable: Listenable.merge([ctrl, panel.dataRevision]),
        builder: (context, _) {
          final shown = ctrl
              .display(item)
              .models
              .where((x) => x.id == model.id)
              .firstOrNull;
          if (shown == null) return const SizedBox.shrink();
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * .9,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 6, 6),
                  child: Row(
                    spacing: 10,
                    children: [
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: c.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const Spacer(),
                      _MobileIconButton(
                        key: const Key('mp-inspector-close'),
                        glyph: UiGlyphs.close,
                        tooltip: context.l10n.set_cancel,
                        onTap: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                ),
                Container(height: 1, color: c.rowLine),
                Flexible(
                  child: SingleChildScrollView(
                    key: const Key('mp-inspector-scroll'),
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
                    ),
                    child: _InspectorColumn(
                      panel: panel,
                      item: item,
                      inline: true,
                      onRemoveModel: (model) =>
                          _confirmRemoveModel(sheetContext, item, model),
                    ),
                  ),
                ),
                // 桌面端靠检查器右上角「⋯」菜单移除模型；手机端弹层里
                // 这个入口太深，底部再给一个显式的危险按钮。
                Container(
                  key: const Key('mp-inspector-remove-bar'),
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: c.rowLine)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _MobileDockButton(
                          key: const Key('mp-mobile-remove-model'),
                          label: context.l10n.mp_removeModel,
                          danger: true,
                          onTap: () =>
                              _confirmRemoveModel(sheetContext, item, shown),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 模型行右侧的上移 / 下移按钮：48dp 触摸目标，两端禁用。
class _MobileReorderButton extends StatelessWidget {
  const _MobileReorderButton({
    super.key,
    required this.glyph,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  final String glyph;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ui;
    final color = enabled ? c.muted : c.faint.withValues(alpha: .35);
    return Tooltip(
      message: tooltip,
      child: UiPressable(
        // 两端禁用时也要吃掉点击：否则会穿透到整行的“打开模型参数”。
        onTap: enabled ? onTap : () {},
        builder: (context, hover) => Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hover && enabled ? c.hover : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: UiGlyph(glyph, size: 17, color: color),
        ),
      ),
    );
  }
}

/// 弹层上的 48dp 图标按钮。
class _MobileIconButton extends StatelessWidget {
  const _MobileIconButton({
    super.key,
    required this.glyph,
    required this.tooltip,
    required this.onTap,
  });

  final String glyph;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ui;
    return Tooltip(
      message: tooltip,
      child: UiPressable(
        onTap: onTap,
        builder: (context, hover) => Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hover ? c.hover : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: UiGlyph(glyph, size: 16, color: c.muted),
        ),
      ),
    );
  }
}

/// 手机端保存条按钮：48dp 高，整宽条里放得下。
class _MobileDockButton extends StatelessWidget {
  const _MobileDockButton({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool primary;

  /// 危险操作（移除模型等）：红字 + 红色描边，不用品牌色。
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.ui;
    final enabled = onTap != null;
    final border = danger
        ? c.error.withValues(alpha: .35)
        : primary
        ? Colors.transparent
        : c.tipInk.withValues(alpha: .3);
    final fg = danger
        ? (enabled ? c.error : c.error.withValues(alpha: .45))
        : primary
        ? c.onBrand
        : (enabled ? c.tipInk : c.tipInk.withValues(alpha: .45));
    Color bg(bool hover) => primary
        ? (enabled ? c.brand : c.brand.withValues(alpha: .45))
        : danger
        ? (hover && enabled
              ? c.error.withValues(alpha: .08)
              : Colors.transparent)
        : (hover && enabled
              ? c.tipInk.withValues(alpha: .1)
              : Colors.transparent);
    return UiPressable(
      onTap: onTap,
      builder: (context, hover) => Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg(hover),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: UiText.sans(
            13,
            weight: FontWeight.w500,
            color: fg,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

/// 手机端目录模式的底部提交条：勾选模型后点「添加 N 个模型」。
///
/// 桌面端由右栏 [ProvidersPickTray] 承担这段流程；手机端编辑页没有右栏，
/// 这里必须常驻确认入口，否则目录里只能勾选、无法真正添加模型。
class _MobileCatalogDock extends StatelessWidget {
  const _MobileCatalogDock({
    required this.item,
    required this.ctrl,
    required this.picks,
    required this.onAdd,
  });

  final ProviderItem item;
  final ProvidersController ctrl;
  final List<String> picks;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.ui;
    final l = context.l10n;
    return Container(
      key: const Key('mp-mobile-catalog-dock'),
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.rowLine)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Row(
            spacing: 10,
            children: [
              Expanded(
                child: Text(
                  l.mp_picked('${picks.length}'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: UiText.sans(
                    12.5,
                    weight: FontWeight.w600,
                    color: picks.isEmpty ? c.muted : c.ink,
                  ),
                ),
              ),
              _MobileDockButton(
                key: const Key('mp-mobile-pick-cancel'),
                label: l.set_cancel,
                onTap: () {
                  ctrl
                    ..clearPicks(item.id)
                    ..setMode(item.id, ProvidersListMode.added);
                },
              ),
              _MobileDockButton(
                key: const Key('mp-mobile-add-picked'),
                label: l.mp_addPicked('${picks.length}'),
                primary: true,
                onTap: picks.isEmpty ? null : onAdd,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
