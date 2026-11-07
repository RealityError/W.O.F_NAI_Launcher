import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/localization_extension.dart';
import '../../../data/models/gallery/gallery_category.dart';
import '../../mobile/mobile_list.dart';
import '../../providers/collection_provider.dart';
import '../../providers/gallery_category_provider.dart';
import '../../providers/local_gallery_provider.dart';
import '../../utils/gallery_category_label.dart';
import '../common/studio_icons.dart';

/// 手机端浏览范围弹层：资料库入口 + 分类树 + 收藏集 + 新建入口。
///
/// 数据与桌面侧栏 `GalleryCategoryTreeView` 完全一致（同一个分类/收藏集
/// provider），只是把桌面树换成 ≥56dp 的大触摸行；选择后回宿主走现有的
/// `_handleCategorySelected` 流程。
class MobileGalleryBrowseSheet extends ConsumerWidget {
  const MobileGalleryBrowseSheet({
    super.key,
    required this.onSelected,
    required this.onCreateCategory,
    required this.onCreateCollection,
  });

  /// 与桌面侧栏一致的范围 ID：null=全部，'favorites' / 'recent' / 'trash'，
  /// 分类传 category.id，收藏集传 `collection:<id>`。
  final ValueChanged<String?> onSelected;
  final VoidCallback onCreateCategory;
  final VoidCallback onCreateCollection;

  void _select(BuildContext context, String? id) {
    Navigator.of(context).pop();
    onSelected(id);
  }

  void _create(BuildContext context, VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final categoryState = ref.watch(galleryCategoryNotifierProvider);
    final collections = ref.watch(collectionNotifierProvider).collections;
    final totalCount = ref.watch(
      localGalleryNotifierProvider.select((s) => s.totalCount),
    );
    final favoriteCount = ref.watch(galleryFavoriteCountProvider).value ?? 0;
    final selectedId = categoryState.selectedCategoryId;

    Widget? check(String? id) => selectedId == id
        ? const Icon(StudioIcons.galleryCheck, size: 20)
        : null;

    final children = <Widget>[
      MobileSectionHeader(title: l.localGallery_sectionLibrary),
      MobileListTile(
        key: const Key('mobile-browse-all'),
        icon: StudioIcons.galleryImage,
        title: l.localGallery_allImages,
        trailingText: '$totalCount',
        trailing: check(null),
        showChevron: false,
        onTap: () => _select(context, null),
      ),
      MobileListTile(
        key: const Key('mobile-browse-favorites'),
        icon: StudioIcons.galleryHeart,
        title: l.common_favorite,
        trailingText: '$favoriteCount',
        trailing: check('favorites'),
        showChevron: false,
        onTap: () => _select(context, 'favorites'),
      ),
      MobileListTile(
        key: const Key('mobile-browse-recent'),
        icon: Icons.history_outlined,
        title: l.localGallery_recentViews,
        trailing: check('recent'),
        showChevron: false,
        onTap: () => _select(context, 'recent'),
      ),
      MobileListTile(
        key: const Key('mobile-browse-trash'),
        icon: StudioIcons.galleryTrash,
        title: l.localGallery_trashTitle,
        trailing: check('trash'),
        showChevron: false,
        onTap: () => _select(context, 'trash'),
      ),
    ];

    final tree = categoryState.categories.buildTree();
    final visitedCategories = <String>{};
    final categoryTiles = <Widget>[];
    void addCategories(String? parentId, int depth) {
      for (final category in tree[parentId] ?? const <GalleryCategory>[]) {
        if (!visitedCategories.add(category.id)) continue;
        categoryTiles.add(
          Padding(
            padding: EdgeInsets.only(left: depth * 16.0),
            child: MobileListTile(
              key: ValueKey('mobile-browse-category-${category.id}'),
              icon: depth == 0 ? StudioIcons.galleryFolder : null,
              title: category.galleryLabel(context),
              subtitle: category.isExternal
                  ? l.localGallery_externalSourceChip
                  : null,
              trailingText: '${category.imageCount}',
              trailing: check(category.id),
              showChevron: false,
              onTap: () => _select(context, category.id),
            ),
          ),
        );
        addCategories(category.id, depth + 1);
      }
    }

    addCategories(null, 0);
    if (categoryTiles.isNotEmpty) {
      children.add(MobileSectionHeader(title: l.common_category));
      children.addAll(categoryTiles);
    }

    final visitedCollections = <String>{};
    final collectionTiles = <Widget>[];
    void addCollections(String? parentId, int depth) {
      for (final collection in collections) {
        if (collection.parentId != parentId) continue;
        if (!visitedCollections.add(collection.id)) continue;
        final selectionId = '$collectionSelectedIdPrefix${collection.id}';
        collectionTiles.add(
          Padding(
            padding: EdgeInsets.only(left: depth * 16.0),
            child: MobileListTile(
              key: ValueKey('mobile-browse-collection-${collection.id}'),
              icon: collection.isFolder
                  ? StudioIcons.galleryFolder
                  : StudioIcons.galleryCollection,
              title: collection.name,
              trailingText: '${collection.imageCount}',
              trailing: check(selectionId),
              showChevron: false,
              // 收藏文件夹只是组织节点（桌面同款语义），不承载图片。
              onTap: collection.isFolder
                  ? null
                  : () => _select(context, selectionId),
            ),
          ),
        );
        addCollections(collection.id, depth + 1);
      }
    }

    addCollections(null, 0);
    if (collectionTiles.isNotEmpty) {
      children.add(
        MobileSectionHeader(title: l.localGallery_sectionCollections),
      );
      children.addAll(collectionTiles);
    }

    children
      ..add(const Divider(height: 1))
      ..add(
        MobileListTile(
          key: const Key('mobile-browse-create-category'),
          icon: StudioIcons.galleryFolderPlus,
          title: l.localGallery_createCategoryTitle,
          showChevron: false,
          onTap: () => _create(context, onCreateCategory),
        ),
      )
      ..add(
        MobileListTile(
          key: const Key('mobile-browse-create-collection'),
          icon: StudioIcons.galleryCollection,
          title: l.localGallery_createCollectionTitle,
          showChevron: false,
          onTap: () => _create(context, onCreateCollection),
        ),
      );

    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: children,
    );
  }
}
