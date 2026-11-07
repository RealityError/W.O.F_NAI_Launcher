import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/localization_extension.dart';
import '../../../data/models/gallery/gallery_category.dart';
import '../../../data/models/gallery/local_image_record.dart';
import '../../../data/services/gallery/gallery_nai_only_store.dart';
import '../../mobile/mobile_context_menu.dart';
import '../../mobile/mobile_scaffold.dart';
import '../../mobile/mobile_sheet.dart';
import '../../mobile/mobile_touch.dart';
import '../../providers/collection_provider.dart';
import '../../providers/gallery_category_provider.dart';
import '../../providers/local_gallery_provider.dart';
import '../../providers/selection_mode_provider.dart';
import '../../utils/gallery_category_label.dart';
import '../../widgets/common/studio_icons.dart';
import '../../widgets/gallery/gallery_floating_bulk_bar.dart';
import '../../widgets/gallery/gallery_nai_versions.dart';
import '../../widgets/gallery/gallery_state_views.dart';
import '../../widgets/gallery/local_image_context_menu.dart';
import '../../widgets/gallery/mobile_gallery_browse_sheet.dart';
import '../../widgets/gallery/mobile_gallery_filter_sheet.dart';
import '../../widgets/gallery/timeline/gallery_timeline_view.dart';

/// 手机端网格目标行高：360dp 竖屏下约 2–3 列（桌面列宽偏好保持不变）。
const double kMobileGalleryTileSize = 150;

/// 手机端本地画廊需要的宿主动作集合。
///
/// 移动布局只负责触屏排版与手势；确认框、业务状态、文件操作仍由
/// `LocalGalleryScreen`（桌面同一份实现）执行，避免两套行为漂移。
class MobileGalleryActions {
  const MobileGalleryActions({
    required this.openViewerAt,
    required this.showRecordMenu,
    required this.openInspector,
    required this.onImageAction,
    required this.openViewerForPath,
    required this.showFavoriteMenu,
    required this.selectScope,
    required this.createCategory,
    required this.createCollection,
    required this.clearFilters,
    required this.refresh,
    required this.importImages,
    required this.openGalleryFolder,
    required this.undo,
    required this.redo,
    required this.selectAllResults,
    required this.moveSelected,
    required this.copySelected,
    required this.packSelected,
    required this.editSelectedMetadata,
    required this.addSelectedToCollection,
    required this.removeSelectedFromCollection,
    required this.deleteSelected,
    required this.restoreSelected,
    required this.restoreTrashAll,
    required this.purgeTrashAll,
  });

  /// 打开查看器（按时间线索引）。
  final void Function(int index) openViewerAt;

  /// 长按卡片：弹出上下文菜单（宿主统一分派现有动作）。
  final void Function(LocalImageRecord record) showRecordMenu;

  /// 打开详情面板（底部弹层）；宿主复用 `GalleryInspectorPanel`。
  final VoidCallback openInspector;

  /// 详情面板里的动作（与桌面右键动作共用 `_handleImageAction`）。
  final Future<void> Function(
    LocalImageRecord record,
    LocalImageContextAction action,
  )
  onImageAction;

  /// 详情面板预览打开大图。
  final void Function(String path) openViewerForPath;

  /// 收藏/收藏集菜单（沿用桌面浮层）。
  final void Function(LocalImageRecord record, Offset anchor) showFavoriteMenu;

  /// 切换浏览范围（数据口径与桌面侧栏一致）。
  final void Function(String? id) selectScope;
  final VoidCallback createCategory;
  final VoidCallback createCollection;
  final VoidCallback clearFilters;
  final VoidCallback refresh;
  final VoidCallback importImages;
  final VoidCallback openGalleryFolder;
  final VoidCallback? undo;
  final VoidCallback? redo;

  /// 多选批量动作（选择态底部沿用桌面 `GalleryFloatingBulkBar`）。
  final Future<void> Function() selectAllResults;
  final VoidCallback moveSelected;
  final VoidCallback copySelected;
  final VoidCallback packSelected;
  final VoidCallback editSelectedMetadata;
  final VoidCallback addSelectedToCollection;
  final VoidCallback? removeSelectedFromCollection;
  final VoidCallback deleteSelected;

  /// 仅在删除池（回收站）范围提供。
  final VoidCallback? restoreSelected;
  final VoidCallback restoreTrashAll;
  final VoidCallback purgeTrashAll;
}

/// 本地画廊手机端布局（Android 手机竖屏 360–430dp）。
///
/// 结构：`MobilePageScaffold` 顶栏（搜索/多选/详情/更多）+ 浏览范围栏 +
/// 筛选状态 chips + 网格主体；多选时底部浮出桌面同款批量操作条；详情面板
/// 走底部弹层；长按卡片弹上下文菜单。桌面 `LocalGalleryScreen` 布局与行为
/// 不受影响（只在 `usesMobileLayout` 分支进入这里）。
class MobileLocalGallery extends ConsumerStatefulWidget {
  const MobileLocalGallery({super.key, required this.actions});

  final MobileGalleryActions actions;

  @override
  ConsumerState<MobileLocalGallery> createState() => _MobileLocalGalleryState();
}

class _MobileLocalGalleryState extends ConsumerState<MobileLocalGallery> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'gallery-mobile');
  Timer? _searchDebounce;
  bool _searchOpen = false;

  MobileGalleryActions get _actions => widget.actions;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _toggleMultiSelect() {
    final notifier = ref.read(localGallerySelectionNotifierProvider.notifier);
    if (ref.read(localGallerySelectionNotifierProvider).isActive) {
      notifier.exit();
    } else {
      notifier.enter();
    }
  }

  void _toggleSearch() {
    final opening = !_searchOpen;
    setState(() {
      _searchOpen = opening;
      if (!opening) {
        _searchDebounce?.cancel();
        _searchController.clear();
        _searchFocusNode.unfocus();
        unawaited(
          ref.read(localGalleryNotifierProvider.notifier).setSearchQuery(''),
        );
      }
    });
    if (opening) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocusNode.requestFocus();
      });
    }
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(
        ref.read(localGalleryNotifierProvider.notifier).setSearchQuery(value),
      );
    });
  }

  void _submitSearch(String value) {
    _searchDebounce?.cancel();
    unawaited(
      ref.read(localGalleryNotifierProvider.notifier).setSearchQuery(value),
    );
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    _searchFocusNode.requestFocus();
    unawaited(
      ref.read(localGalleryNotifierProvider.notifier).setSearchQuery(''),
    );
    setState(() {});
  }

  Future<void> _showMoreActions() async {
    final browseScope = ref.read(localGalleryChromeStateProvider).browseScope;
    final l = context.l10n;
    if (browseScope == GalleryBrowseScope.trash) {
      await showMobileContextMenu(
        context,
        title: l.localGallery_trashTitle,
        items: [
          MobileMenuItem(
            label: l.localGallery_trashRestoreAll,
            icon: StudioIcons.galleryUndo,
            onTap: _actions.restoreTrashAll,
          ),
          MobileMenuItem(
            label: l.localGallery_trashDeleteAll,
            icon: StudioIcons.galleryTrash,
            destructive: true,
            onTap: _actions.purgeTrashAll,
          ),
        ],
      );
      return;
    }
    await showMobileContextMenu(
      context,
      title: l.localGallery_moreActions,
      items: [
        MobileMenuItem(
          label: l.common_import,
          icon: StudioIcons.galleryFolderImport,
          onTap: _actions.importImages,
        ),
        MobileMenuItem(
          label: l.shortcut_action_open_folder,
          icon: StudioIcons.galleryFolder,
          onTap: _actions.openGalleryFolder,
        ),
        MobileMenuItem(
          label: l.common_refresh,
          icon: StudioIcons.galleryRefresh,
          onTap: _actions.refresh,
        ),
        MobileMenuItem(
          label: l.common_undo,
          icon: StudioIcons.galleryUndo,
          enabled: _actions.undo != null,
          onTap: _actions.undo,
        ),
        MobileMenuItem(
          label: l.common_redo,
          icon: StudioIcons.galleryRedo,
          enabled: _actions.redo != null,
          onTap: _actions.redo,
        ),
        MobileMenuItem(
          label: l.localGallery_createCategoryTitle,
          icon: StudioIcons.galleryFolderPlus,
          onTap: _actions.createCategory,
        ),
        MobileMenuItem(
          label: l.localGallery_createCollectionTitle,
          icon: StudioIcons.galleryCollection,
          onTap: _actions.createCollection,
        ),
      ],
    );
  }

  Future<void> _openBrowseSheet() {
    return showMobileSheet<void>(
      context: context,
      title: context.l10n.localGallery_sectionLibrary,
      heightFactor: 0.85,
      builder: (_) => MobileGalleryBrowseSheet(
        onSelected: _actions.selectScope,
        onCreateCategory: _actions.createCategory,
        onCreateCollection: _actions.createCollection,
      ),
    );
  }

  Future<void> _openFilterSheet() {
    return showMobileSheet<void>(
      context: context,
      title: context.l10n.mp_filter,
      heightFactor: 0.9,
      builder: (_) => const MobileGalleryFilterSheet(),
    );
  }

  Future<void> _openDisplaySheet() {
    return showMobileSheet<void>(
      context: context,
      title: context.l10n.localGallery_sortButton,
      heightFactor: 0.9,
      builder: (_) => const MobileGalleryDisplaySheet(),
    );
  }

  Future<void> _toggleNaiOnly() async {
    final criteria = ref.read(localGalleryChromeStateProvider).filterCriteria;
    final notifier = ref.read(localGalleryNotifierProvider.notifier);
    await notifier.setNaiOnly(!criteria.naiOnly);
    await const GalleryNaiOnlyStore().save(!criteria.naiOnly);
  }

  /// 当前浏览范围的短标签（与桌面工具栏面包屑同源）。
  String _scopeLabel(BuildContext context, LocalGalleryState state) {
    final l = context.l10n;
    switch (state.browseScope) {
      case GalleryBrowseScope.recent:
        return l.localGallery_recentViews;
      case GalleryBrowseScope.trash:
        return l.localGallery_trashTitle;
      case GalleryBrowseScope.library:
        final criteria = state.filterCriteria;
        if (criteria.showFavoritesOnly) return l.common_favorite;
        final collectionId = criteria.collectionId;
        if (collectionId != null) {
          final collection = ref
              .watch(collectionNotifierProvider)
              .collections
              .where((entry) => entry.id == collectionId)
              .firstOrNull;
          if (collection != null) return collection.name;
        }
        final categoryId = criteria.categoryId;
        if (categoryId != null) {
          final category = ref
              .watch(galleryCategoryNotifierProvider)
              .categories
              .findById(categoryId);
          if (category != null) return category.galleryLabel(context);
        }
        return l.localGallery_allImages;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final state = ref.watch(localGalleryChromeStateProvider);
    final selectionActive = ref.watch(
      localGallerySelectionNotifierProvider.select((s) => s.isActive),
    );
    final colorScheme = Theme.of(context).colorScheme;
    final scopeLabel = _scopeLabel(context, state);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final countText = NumberFormat.decimalPattern(
      locale,
    ).format(state.resultCount);

    return PopScope(
      // 多选中按系统返回键先退出多选，再退出页面。
      canPop: !selectionActive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) {
          ref.read(localGallerySelectionNotifierProvider.notifier).exit();
        }
      },
      child: MobilePageScaffold(
        title: l.localGallery_title,
        subtitle:
            '$scopeLabel · '
            '${l.localGallery_imageCountLabel(state.resultCount, countText)}',
        showBack: false,
        actions: [
          MobileHeaderAction(
            key: const Key('mobile-gallery-search'),
            icon: StudioIcons.gallerySearch,
            tooltip: l.online_modeSearch,
            onTap: _toggleSearch,
          ),
          MobileHeaderAction(
            key: const Key('mobile-gallery-multiselect'),
            icon: selectionActive
                ? Icons.check_circle_rounded
                : StudioIcons.gallerySelect,
            tooltip: selectionActive ? l.common_exit : l.common_multiSelect,
            onTap: _toggleMultiSelect,
          ),
          MobileHeaderAction(
            key: const Key('mobile-gallery-inspector'),
            icon: StudioIcons.galleryPanelRight,
            tooltip: l.localGallery_showInspector,
            onTap: _actions.openInspector,
          ),
          MobileHeaderAction(
            key: const Key('mobile-gallery-more'),
            icon: StudioIcons.galleryMore,
            tooltip: l.localGallery_moreActions,
            onTap: () => unawaited(_showMoreActions()),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_searchOpen) _buildSearchRow(context, scopeLabel),
            _buildBrowseBar(context, scopeLabel),
            if (state.hasSessionFilters || state.filterCriteria.naiOnly)
              _buildFilterChips(context, state),
            if (state.browseScope == GalleryBrowseScope.trash)
              _buildTrashActions(context, colorScheme),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: _buildBody(context)),
                  if (selectionActive)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _buildBulkBar(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchRow(BuildContext context, String scopeLabel) {
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: kMobileMinTouchTarget,
              child: TextField(
                key: const Key('mobile-gallery-search-field'),
                controller: _searchController,
                focusNode: _searchFocusNode,
                textInputAction: TextInputAction.search,
                onChanged: _onSearchChanged,
                onSubmitted: _submitSearch,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l.localGallery_searchInScope(scopeLabel),
                  hintMaxLines: 1,
                  prefixIcon: const Icon(StudioIcons.gallerySearch, size: 18),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: l.common_clear,
                          icon: const Icon(StudioIcons.galleryClose, size: 16),
                          onPressed: _clearSearch,
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            key: const Key('mobile-gallery-search-close'),
            tooltip: l.common_close,
            icon: const Icon(Icons.close_rounded),
            onPressed: _toggleSearch,
          ),
        ],
      ),
    );
  }

  Widget _buildBrowseBar(BuildContext context, String scopeLabel) {
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: _MobileGalleryBarButton(
              key: const Key('mobile-gallery-scope'),
              icon: StudioIcons.galleryFolder,
              label: scopeLabel,
              onTap: () => unawaited(_openBrowseSheet()),
            ),
          ),
          IconButton(
            key: const Key('mobile-gallery-filter'),
            tooltip: l.mp_filter,
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => unawaited(_openFilterSheet()),
          ),
          IconButton(
            key: const Key('mobile-gallery-display'),
            tooltip: l.localGallery_sortButton,
            icon: const Icon(StudioIcons.gallerySortDesc),
            onPressed: () => unawaited(_openDisplaySheet()),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(BuildContext context, LocalGalleryState state) {
    final l = context.l10n;
    final criteria = state.filterCriteria;
    final notifier = ref.read(localGalleryNotifierProvider.notifier);
    final match = GalleryNaiVersions.match(criteria.filterModels);
    final chips = <Widget>[
      if (criteria.naiOnly)
        _MobileGalleryChip(
          key: const Key('mobile-chip-nai'),
          label: l.localGallery_naiOnlyChip,
          icon: StudioIcons.galleryCheck,
          onTap: () => unawaited(_toggleNaiOnly()),
        ),
      if (match != null)
        _MobileGalleryChip(
          key: const Key('mobile-chip-model'),
          label: match.variant == null
              ? 'V${match.version}'
              : 'V${match.version} ${match.variant}',
          onTap: () => unawaited(_openFilterSheet()),
        ),
      if (criteria.dateStart != null || criteria.dateEnd != null)
        _MobileGalleryChip(
          key: const Key('mobile-chip-date'),
          label: mobileGalleryDateRangeLabel(context, criteria),
          icon: StudioIcons.galleryCalendar,
          onTap: () => unawaited(showMobileGalleryDateRangeSheet(context)),
        ),
      for (final tag in criteria.selectedTags)
        _MobileGalleryChip(
          key: ValueKey('mobile-chip-tag-$tag'),
          label: tag,
          icon: StudioIcons.galleryTag,
          onTap: () => unawaited(notifier.removeSelectedTag(tag)),
        ),
      if (state.hasSessionFilters)
        _MobileGalleryChip(
          key: const Key('mobile-chip-clear'),
          label: l.localGallery_clearFilters,
          onTap: _actions.clearFilters,
        ),
    ];
    return SizedBox(
      height: 52,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            for (final (index, chip) in chips.indexed) ...[
              if (index > 0) const SizedBox(width: 8),
              chip,
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTrashActions(BuildContext context, ColorScheme colorScheme) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.localGallery_trashHint,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('mobile-trash-restore-all'),
                  onPressed: _actions.restoreTrashAll,
                  icon: const Icon(StudioIcons.galleryUndo, size: 18),
                  label: Text(
                    l.localGallery_trashRestoreAll,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(kMobileMinTouchTarget),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  key: const Key('mobile-trash-purge-all'),
                  onPressed: _actions.purgeTrashAll,
                  icon: const Icon(StudioIcons.galleryTrash, size: 18),
                  label: Text(
                    l.localGallery_trashDeleteAll,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(kMobileMinTouchTarget),
                    backgroundColor: colorScheme.error,
                    foregroundColor: colorScheme.onError,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final error = ref.watch(
      localGalleryNotifierProvider.select((s) => s.error),
    );
    if (error != null) {
      return GalleryErrorView(
        error: error.localized(context.l10n),
        onRetry: _actions.refresh,
      );
    }
    return GalleryTimelineView(
      mobileMode: true,
      maxTileSize: kMobileGalleryTileSize,
      onOpenViewer: _actions.openViewerAt,
      onContextMenu: (record, _) => _actions.showRecordMenu(record),
      onMobileLongPress: _actions.showRecordMenu,
      onUseImage: (_) async {},
      onFavoriteMenu: _actions.showFavoriteMenu,
      onClearFilters: _actions.clearFilters,
    );
  }

  Widget _buildBulkBar() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: GalleryFloatingBulkBar(
            onSelectAllResults: _actions.selectAllResults,
            onMove: _actions.moveSelected,
            onCopy: _actions.copySelected,
            onPack: _actions.packSelected,
            onEditMetadata: _actions.editSelectedMetadata,
            onAddToCollection: _actions.addSelectedToCollection,
            onRemoveFromCollection: _actions.removeSelectedFromCollection,
            onDelete: _actions.deleteSelected,
            onRestore: _actions.restoreSelected,
          ),
        ),
      ),
    );
  }
}

/// 浏览范围按钮：44dp 高，整行可点。
class _MobileGalleryBarButton extends StatelessWidget {
  const _MobileGalleryBarButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: kMobileMinTouchTarget,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 6),
            child: Row(
              children: [
                Icon(icon, size: 18, color: colors.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  StudioIcons.galleryChevronDown,
                  size: 16,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 筛选状态 chip：44dp 高，点击打开对应筛选弹层（标签/清除直接生效）。
class _MobileGalleryChip extends StatelessWidget {
  const _MobileGalleryChip({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.primary.withValues(alpha: 0.10),
      shape: StadiumBorder(
        side: BorderSide(color: colors.primary.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: kMobileMinTouchTarget,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: colors.primary),
                  const SizedBox(width: 6),
                ],
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
