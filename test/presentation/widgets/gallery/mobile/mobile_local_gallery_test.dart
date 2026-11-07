// ignore: depend_on_referenced_packages
import 'package:irondash_message_channel/irondash_message_channel.dart';
// ignore: implementation_imports, depend_on_referenced_packages
import 'package:super_native_extensions/src/native/context.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/gallery/gallery_category.dart';
import 'package:nai_launcher/data/models/gallery/image_collection.dart';
import 'package:nai_launcher/data/models/gallery/local_image_record.dart';
import 'package:nai_launcher/data/models/gallery/nai_image_metadata.dart';
import 'package:nai_launcher/data/services/gallery/unified_gallery_service.dart';
import 'package:nai_launcher/data/services/thumbnail_service.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/mobile/mobile_context_menu.dart';
import 'package:nai_launcher/presentation/mobile/mobile_sheet.dart';
import 'package:nai_launcher/presentation/providers/collection_provider.dart';
import 'package:nai_launcher/presentation/providers/gallery_category_provider.dart';
import 'package:nai_launcher/presentation/providers/gallery_trash_provider.dart';
import 'package:nai_launcher/presentation/providers/krita/krita_bridge_notifier.dart';
import 'package:nai_launcher/presentation/providers/local_gallery_provider.dart';
import 'package:nai_launcher/presentation/providers/selection_mode_provider.dart';
import 'package:nai_launcher/presentation/screens/local_gallery/mobile_local_gallery.dart';
import 'package:nai_launcher/presentation/widgets/gallery/gallery_inspector_panel.dart';
import 'package:nai_launcher/presentation/widgets/gallery/local_image_card.dart';
import 'package:nai_launcher/presentation/widgets/gallery/mobile_gallery_browse_sheet.dart';
import 'package:nai_launcher/presentation/widgets/gallery/mobile_gallery_filter_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../helpers/fake_local_gallery_service.dart';

class _TestKritaBridgeNotifier extends KritaBridgeNotifier {
  @override
  Future<void> close() async {}
}

class _FakeCategoryNotifier extends GalleryCategoryNotifier {
  @override
  GalleryCategoryState build() {
    final now = DateTime(2026, 9, 1);
    GalleryCategory category(
      String id,
      String name,
      int count, {
      String? parent,
      int order = 0,
    }) => GalleryCategory(
      id: id,
      name: name,
      folderPath: parent == null ? name : '$parent/$name',
      parentId: parent,
      imageCount: count,
      sortOrder: order,
      createdAt: now,
      updatedAt: now,
    );
    return GalleryCategoryState(
      categories: [
        category('v45', 'NAI 4.5', 12),
        category('v45r', 'R18', 7, parent: 'v45', order: 0),
        category('v5', 'NAI 5', 5, order: 1),
      ],
    );
  }

  @override
  Future<void> refresh() async {}

  @override
  Future<void> syncWithFileSystem() async {}
}

class _FakeCollectionNotifier extends CollectionNotifier {
  @override
  CollectionState build() {
    final now = DateTime(2026, 9, 1);
    return CollectionState(
      collections: [
        ImageCollection(
          id: 'fav',
          name: 'Favorites Folder',
          createdAt: now,
          isFolder: true,
        ),
        ImageCollection(
          id: 'art',
          name: 'Art',
          createdAt: now,
          parentId: 'fav',
          imageCount: 3,
        ),
      ],
    );
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> refresh() async {}
}

List<LocalImageRecord> _records() {
  final start = DateTime(2026, 9, 20, 20);
  return [
    for (var i = 0; i < 24; i++)
      LocalImageRecord(
        path: 'C:/gallery/missing/img_$i.png',
        size: 1000 + i,
        modifiedAt: start.subtract(Duration(days: i ~/ 6, minutes: i)),
        metadata: NaiImageMetadata(
          prompt: 'prompt $i',
          width: i.isEven ? 832 : 1216,
          height: i.isEven ? 1216 : 832,
          seed: 100 + i,
        ),
      ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setContextOverride(
    MockMessageChannelContext()
      ..registerMockMethodCallHandler('DropManager', (_) async => null)
      ..registerMockMethodCallHandler('DragManager', (_) async => null),
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dev.irondash.engine_context'),
        (_) async => 1,
      );

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(ThumbnailService.instance.cancelAll);

  late ProviderContainer container;
  late FakeLocalGalleryService service;
  late List<LocalImageRecord> records;
  final opened = <int>[];
  final longPressed = <String>[];
  final selectedScopes = <String?>[];
  late BuildContext galleryContext;

  Future<void> pumpGallery(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    records = _records();
    opened.clear();
    longPressed.clear();
    selectedScopes.clear();
    service = FakeLocalGalleryService(records);
    container = ProviderContainer(
      overrides: [
        galleryServiceProvider.overrideWith(
          () => FakeGalleryServiceNotifier(service),
        ),
        galleryTrashTimelineProvider.overrideWith(
          (ref) async => [
            for (final record in records)
              GalleryTimelineEntry(
                path: record.path,
                modifiedAt: record.modifiedAt,
                width: record.metadata?.width,
                height: record.metadata?.height,
              ),
          ],
        ),
        galleryCategoryNotifierProvider.overrideWith(_FakeCategoryNotifier.new),
        collectionNotifierProvider.overrideWith(_FakeCollectionNotifier.new),
        kritaBridgeNotifierProvider.overrideWith(
          (ref) => _TestKritaBridgeNotifier(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(localGalleryNotifierProvider.notifier).initialize();

    final actions = MobileGalleryActions(
      openViewerAt: opened.add,
      showRecordMenu: (record) {
        longPressed.add(record.path);
        unawaited(
          showMobileContextMenu(
            galleryContext,
            title: '卡片操作',
            items: [
              MobileMenuItem(
                label: '详情',
                icon: Icons.info_outline,
                onTap: () {},
              ),
              MobileMenuItem(
                label: '删除',
                icon: Icons.delete_outline,
                destructive: true,
                onTap: () {},
              ),
            ],
          ),
        );
      },
      openInspector: () => unawaited(
        showMobileSheet<void>(
          context: galleryContext,
          heightFactor: 0.92,
          builder: (sheetContext) => GalleryInspectorPanel(
            touchOptimized: true,
            onAction: (record, action) async {},
            onOpenViewer: (_) {},
            onClose: () => Navigator.of(sheetContext).pop(),
            onFavoriteMenu: (record, anchor) {},
          ),
        ),
      ),
      onImageAction: (record, action) async {},
      openViewerForPath: (_) {},
      showFavoriteMenu: (record, anchor) {},
      selectScope: selectedScopes.add,
      createCategory: () {},
      createCollection: () {},
      clearFilters: () {},
      refresh: () {},
      importImages: () {},
      openGalleryFolder: () {},
      undo: null,
      redo: null,
      selectAllResults: () async {},
      moveSelected: () {},
      copySelected: () {},
      packSelected: () {},
      editSelectedMetadata: () {},
      addSelectedToCollection: () {},
      removeSelectedFromCollection: null,
      deleteSelected: () {},
      restoreSelected: null,
      restoreTrashAll: () {},
      purgeTrashAll: () {},
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MobileLocalGallery(actions: actions),
        ),
      ),
    );
    galleryContext = tester.element(find.byType(MobileLocalGallery));
    await _pumpUntilCards(tester);
  }

  Finder firstCard() => find.byType(LocalImageCard).first;

  testWidgets('360dp phone layout renders chrome and grid without overflow', (
    tester,
  ) async {
    await pumpGallery(tester);
    final l = AppLocalizations.of(galleryContext)!;

    expect(find.text(l.localGallery_title), findsOneWidget);
    expect(find.byType(LocalImageCard), findsWidgets);
    expect(find.byKey(const Key('mobile-gallery-scope')), findsOneWidget);
    expect(find.byKey(const Key('mobile-gallery-filter')), findsOneWidget);
    expect(find.byKey(const Key('mobile-gallery-display')), findsOneWidget);
    expect(find.byKey(const Key('mobile-gallery-multiselect')), findsOneWidget);
    expect(find.byKey(const Key('mobile-gallery-inspector')), findsOneWidget);
    expect(find.byKey(const Key('mobile-gallery-more')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _disposeGallery(tester);
  });

  testWidgets('tap opens the existing viewer and long-press opens the menu', (
    tester,
  ) async {
    await pumpGallery(tester);

    await tester.tap(firstCard());
    await tester.pump();
    expect(opened, [0]);

    await tester.longPress(firstCard());
    await tester.pumpAndSettle();
    expect(longPressed, [records.first.path]);
    expect(find.text('卡片操作'), findsOneWidget);
    expect(find.text('详情'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('详情'));
    await tester.pumpAndSettle();
    expect(find.text('卡片操作'), findsNothing);

    await _disposeGallery(tester);
  });

  testWidgets('header multiselect toggles selection and the shared bulk bar', (
    tester,
  ) async {
    await pumpGallery(tester);

    await tester.tap(find.byKey(const Key('mobile-gallery-multiselect')));
    await tester.pump();
    expect(
      container.read(localGallerySelectionNotifierProvider).isActive,
      true,
    );
    expect(find.byKey(const Key('gallery-floating-bulk-bar')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(firstCard());
    await tester.pump();
    expect(
      container.read(localGallerySelectionNotifierProvider).selectedIds,
      contains(records.first.path),
    );

    await tester.tap(find.byKey(const Key('gallery-bulk-exit')));
    await tester.pump();
    expect(
      container.read(localGallerySelectionNotifierProvider).isActive,
      false,
    );
    expect(find.byKey(const Key('gallery-floating-bulk-bar')), findsNothing);

    await _disposeGallery(tester);
  });

  testWidgets('inspector header action opens the reused detail panel sheet', (
    tester,
  ) async {
    await pumpGallery(tester);
    final l = AppLocalizations.of(galleryContext)!;

    await tester.tap(find.byKey(const Key('mobile-gallery-inspector')));
    await tester.pumpAndSettle();
    expect(find.byType(GalleryInspectorPanel), findsOneWidget);
    expect(find.text(l.localGallery_inspectorTitle), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip(l.localGallery_hideInspector));
    await tester.pumpAndSettle();
    expect(find.byType(GalleryInspectorPanel), findsNothing);

    await _disposeGallery(tester);
  });

  testWidgets('filter and display sheets open at phone width', (tester) async {
    await pumpGallery(tester);

    await tester.tap(find.byKey(const Key('mobile-gallery-filter')));
    await tester.pumpAndSettle();
    expect(find.byType(MobileGalleryFilterSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(180, 20));
    await tester.pumpAndSettle();
    expect(find.byType(MobileGalleryFilterSheet), findsNothing);

    await tester.tap(find.byKey(const Key('mobile-gallery-display')));
    await tester.pumpAndSettle();
    expect(find.byType(MobileGalleryDisplaySheet), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _disposeGallery(tester);
  });

  testWidgets('browse sheet lists scopes and routes category selection', (
    tester,
  ) async {
    await pumpGallery(tester);

    await tester.tap(find.byKey(const Key('mobile-gallery-scope')));
    await tester.pumpAndSettle();
    expect(find.byType(MobileGalleryBrowseSheet), findsOneWidget);
    final browseAll = find.byKey(const Key('mobile-browse-all'));
    expect(browseAll, findsOneWidget);
    expect(
      find.descendant(of: browseAll, matching: find.text('全部图片')),
      findsOneWidget,
    );
    expect(find.text('NAI 4.5'), findsOneWidget);
    expect(find.text('R18'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('mobile-browse-category-v45')));
    await tester.pumpAndSettle();
    expect(selectedScopes, ['v45']);
    expect(find.byType(MobileGalleryBrowseSheet), findsNothing);

    await _disposeGallery(tester);
  });
}

Future<void> _pumpUntilCards(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 40));
    if (find.byType(LocalImageCard).evaluate().isNotEmpty) return;
  }
}

Future<void> _disposeGallery(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}
