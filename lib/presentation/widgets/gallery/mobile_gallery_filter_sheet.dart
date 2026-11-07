import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/localization_extension.dart';
import '../../../data/services/gallery/gallery_filter_service.dart';
import '../../../data/services/gallery/gallery_group_mode.dart';
import '../../../data/services/gallery/gallery_nai_only_store.dart';
import '../../../data/services/gallery/gallery_sort.dart';
import '../../../data/services/gallery/gallery_sort_store.dart';
import '../../../data/services/gallery/gallery_view_mode.dart';
import '../../../data/services/gallery/gallery_view_mode_store.dart';
import '../../mobile/mobile_list.dart';
import '../../mobile/mobile_sheet.dart';
import '../../providers/local_gallery_provider.dart';
import '../common/studio_icons.dart';
import 'date_range_picker_dialog.dart';
import 'gallery_nai_versions.dart';

/// 手机端筛选弹层：仅 NAI / 模型版本 / 日期范围 / 已选标签 / 分组 / 清除。
///
/// 和桌面 [LocalGalleryFilterBar] 共用同一份 provider 与持久化存储；桌面筛选条
/// 保持原样，这里只提供 ≥44dp 触摸目标的触屏排版。
class MobileGalleryFilterSheet extends ConsumerWidget {
  const MobileGalleryFilterSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final state = ref.watch(localGalleryChromeStateProvider);
    final criteria = state.filterCriteria;
    final notifier = ref.read(localGalleryNotifierProvider.notifier);
    final match = GalleryNaiVersions.match(criteria.filterModels);

    void setNaiOnly(bool value) {
      unawaited(notifier.setNaiOnly(value));
      unawaited(const GalleryNaiOnlyStore().save(value));
      if (!value && criteria.filterModels.isNotEmpty) {
        unawaited(notifier.setFilterModels(const []));
      }
    }

    void setModels(List<String> ids) {
      unawaited(notifier.setFilterModels(ids));
      if (ids.isNotEmpty && !criteria.naiOnly) {
        unawaited(notifier.setNaiOnly(true));
        unawaited(const GalleryNaiOnlyStore().save(true));
      }
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        SwitchListTile(
          key: const Key('mobile-filter-nai'),
          secondary: const Icon(StudioIcons.gallerySpark, size: 22),
          title: Text(l.localGallery_naiOnlyChip),
          value: criteria.naiOnly,
          onChanged: setNaiOnly,
        ),
        MobileSectionHeader(title: l.localGallery_modelLabel),
        _FilterChoiceTile(
          label: l.localGallery_allVersions,
          selected: match == null,
          onTap: () => setModels(const []),
        ),
        for (final version in GalleryNaiVersions.labels)
          _FilterChoiceTile(
            key: ValueKey('mobile-filter-model-$version'),
            label: 'V$version',
            selected: match?.version == version,
            onTap: () => setModels(GalleryNaiVersions.modelIds[version]!),
          ),
        if (match != null &&
            GalleryNaiVersions.fullIds.containsKey(match.version)) ...[
          _FilterChoiceTile(
            label: l.localGallery_allVariants,
            selected: match.variant == null,
            onTap: () => setModels(GalleryNaiVersions.modelIds[match.version]!),
          ),
          _FilterChoiceTile(
            label: 'Full',
            selected: match.variant == 'F',
            onTap: () => setModels(GalleryNaiVersions.fullIds[match.version]!),
          ),
          _FilterChoiceTile(
            label: 'Curated',
            selected: match.variant == 'C',
            onTap: () =>
                setModels(GalleryNaiVersions.curatedIds[match.version]!),
          ),
        ],
        MobileSectionHeader(title: l.localGallery_dateRangeChip),
        MobileListTile(
          key: const Key('mobile-filter-date'),
          icon: StudioIcons.galleryCalendar,
          title: l.localGallery_dateRangeChip,
          subtitle: mobileGalleryDateRangeLabel(context, criteria),
          showChevron: true,
          onTap: () => unawaited(showMobileGalleryDateRangeSheet(context)),
        ),
        if (criteria.selectedTags.isNotEmpty) ...[
          MobileSectionHeader(title: l.localGallery_tagIntersection),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in criteria.selectedTags)
                  InputChip(
                    key: ValueKey('mobile-filter-tag-$tag'),
                    label: Text(tag),
                    onDeleted: () => unawaited(notifier.removeSelectedTag(tag)),
                  ),
              ],
            ),
          ),
        ],
        MobileSectionHeader(title: l.localGallery_groupModeTooltip),
        _FilterChoiceTile(
          label: l.localGallery_groupByDay,
          selected: state.groupMode == GalleryGroupMode.day,
          onTap: () => _setGroupMode(notifier, GalleryGroupMode.day),
        ),
        _FilterChoiceTile(
          label: l.localGallery_groupByMonth,
          selected: state.groupMode == GalleryGroupMode.month,
          onTap: () => _setGroupMode(notifier, GalleryGroupMode.month),
        ),
        _FilterChoiceTile(
          label: l.localGallery_groupNone,
          selected: state.groupMode == GalleryGroupMode.none,
          onTap: () => _setGroupMode(notifier, GalleryGroupMode.none),
        ),
        if (state.hasSessionFilters)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: OutlinedButton.icon(
              key: const Key('mobile-filter-clear'),
              onPressed: () => unawaited(notifier.clearAllFilters()),
              icon: const Icon(Icons.filter_alt_off, size: 18),
              label: Text(l.localGallery_clearFilters),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
      ],
    );
  }
}

void _setGroupMode(LocalGalleryNotifier notifier, GalleryGroupMode mode) {
  notifier.setGroupMode(mode);
  unawaited(const GalleryGroupModeStore().save(mode));
}

/// 手机端最近筛选的当前值文案（与桌面筛选条的日期 chip 一致）。
String mobileGalleryDateRangeLabel(
  BuildContext context,
  FilterCriteria criteria,
) {
  final l = context.l10n;
  final locale = Localizations.localeOf(context).toLanguageTag();
  final format = DateFormat.MMMd(locale);
  final start = criteria.dateStart;
  final end = criteria.displayDateEnd;
  if (start == null && end == null) return l.localGallery_dateRangeChip;
  if (start != null && end != null) {
    return start == end
        ? format.format(start)
        : '${format.format(start)} – ${format.format(end)}';
  }
  if (start != null) return '${format.format(start)} –';
  return '– ${format.format(end!)}';
}

/// 打开手机端日期范围选择弹层，选中后写回画廊筛选。
Future<void> showMobileGalleryDateRangeSheet(BuildContext context) {
  return showMobileSheet<void>(
    context: context,
    title: context.l10n.localGallery_dateRangeChip,
    heightFactor: 0.8,
    builder: (_) => const _MobileGalleryDateRangeSheet(),
  );
}

class _MobileGalleryDateRangeSheet extends ConsumerWidget {
  const _MobileGalleryDateRangeSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final criteria = ref.watch(
      localGalleryChromeStateProvider.select((s) => s.filterCriteria),
    );
    final notifier = ref.read(localGalleryNotifierProvider.notifier);
    return SingleChildScrollView(
      child: Center(
        child: GalleryDateRangePicker(
          initialStart: criteria.dateStart,
          initialEnd: criteria.displayDateEnd,
          onSelected: (result) {
            if (result != null) {
              unawaited(notifier.setDateRange(result.start, result.end));
            }
            Navigator.of(context).maybePop();
          },
        ),
      ),
    );
  }
}

/// 手机端显示设置弹层：排序字段 / 方向 / 视图模式。
///
/// 缩略图大小在手机端按视口自适应（见 `MobileLocalGallery`），不暴露桌面列宽
/// 滑块，避免把桌面偏好改成手机尺寸。
class MobileGalleryDisplaySheet extends ConsumerWidget {
  const MobileGalleryDisplaySheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final state = ref.watch(localGalleryChromeStateProvider);
    final notifier = ref.read(localGalleryNotifierProvider.notifier);
    final fields = <(GallerySortField, String)>[
      (GallerySortField.modifiedAt, l.localGallery_sortFieldModified),
      (GallerySortField.createdAt, l.localGallery_sortFieldCreated),
      (GallerySortField.fileName, l.localGallery_sortFieldName),
      (GallerySortField.fileSize, l.localGallery_sortFieldSize),
      (GallerySortField.imageDimensions, l.localGallery_sortFieldDimensions),
    ];
    final descending = state.sortDirection == GallerySortDirection.descending;

    void applySort(GallerySortField field, GallerySortDirection direction) {
      unawaited(notifier.setSort(field, direction));
      unawaited(
        const GallerySortStore().save(
          GallerySort(field: field, direction: direction),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        MobileSectionHeader(title: l.localGallery_sortButton),
        for (final (field, label) in fields)
          _FilterChoiceTile(
            key: ValueKey('mobile-sort-field-${field.name}'),
            label: label,
            selected: field == state.sortField,
            onTap: () =>
                applySort(field, GallerySort.defaultDirectionFor(field)),
          ),
        _FilterChoiceTile(
          label: l.localGallery_sortDescending,
          selected: descending,
          onTap: () =>
              applySort(state.sortField, GallerySortDirection.descending),
        ),
        _FilterChoiceTile(
          label: l.localGallery_sortAscending,
          selected: !descending,
          onTap: () =>
              applySort(state.sortField, GallerySortDirection.ascending),
        ),
        MobileSectionHeader(title: l.common_grid),
        _FilterChoiceTile(
          key: const Key('mobile-view-grid'),
          label: l.common_grid,
          selected: state.viewMode == GalleryViewMode.grid,
          onTap: () => _setViewMode(notifier, GalleryViewMode.grid),
        ),
        _FilterChoiceTile(
          key: const Key('mobile-view-masonry'),
          label: l.localGallery_masonryViewLabel,
          selected: state.viewMode == GalleryViewMode.masonry,
          onTap: () => _setViewMode(notifier, GalleryViewMode.masonry),
        ),
        _FilterChoiceTile(
          key: const Key('mobile-view-justified'),
          label: l.localGallery_justifiedViewLabel,
          selected: state.viewMode == GalleryViewMode.justified,
          onTap: () => _setViewMode(notifier, GalleryViewMode.justified),
        ),
      ],
    );
  }
}

void _setViewMode(LocalGalleryNotifier notifier, GalleryViewMode mode) {
  notifier.setViewMode(mode);
  unawaited(const GalleryViewModeStore().save(mode));
}

/// 筛选弹层里的单选项：56dp 行高，尾部勾选。
class _FilterChoiceTile extends StatelessWidget {
  const _FilterChoiceTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MobileListTile(
      title: label,
      showChevron: false,
      onTap: onTap,
      trailing: selected
          ? Icon(StudioIcons.galleryCheck, size: 20, color: colors.primary)
          : null,
    );
  }
}
