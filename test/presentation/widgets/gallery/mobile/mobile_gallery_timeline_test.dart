// ignore: depend_on_referenced_packages
import 'package:irondash_message_channel/irondash_message_channel.dart';
// ignore: implementation_imports, depend_on_referenced_packages
import 'package:super_native_extensions/src/native/context.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/gallery/local_image_record.dart';
import 'package:nai_launcher/data/models/gallery/nai_image_metadata.dart';
import 'package:nai_launcher/data/services/gallery/unified_gallery_service.dart';
import 'package:nai_launcher/data/services/thumbnail_service.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/gallery_trash_provider.dart';
import 'package:nai_launcher/presentation/providers/krita/krita_bridge_notifier.dart';
import 'package:nai_launcher/presentation/providers/local_gallery_focus_provider.dart';
import 'package:nai_launcher/presentation/providers/local_gallery_provider.dart';
import 'package:nai_launcher/presentation/providers/selection_mode_provider.dart';
import 'package:nai_launcher/presentation/widgets/gallery/local_image_card.dart';
import 'package:nai_launcher/presentation/widgets/gallery/timeline/gallery_timeline_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../helpers/fake_local_gallery_service.dart';

class _TestKritaBridgeNotifier extends KritaBridgeNotifier {
  @override
  Future<void> close() async {}
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
        ),
      ),
  ];
}

/// 手机端时间线的触屏语义：单击打开大图、长按弹菜单；桌面语义不变。
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
  late List<LocalImageRecord> records;
  final opened = <int>[];
  final longPressed = <String>[];
  final contextMenus = <String>[];

  Future<void> pumpTimeline(
    WidgetTester tester, {
    required bool mobileMode,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    records = _records();
    opened.clear();
    longPressed.clear();
    contextMenus.clear();
    final service = FakeLocalGalleryService(records);
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
        kritaBridgeNotifierProvider.overrideWith(
          (ref) => _TestKritaBridgeNotifier(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(localGalleryNotifierProvider.notifier).initialize();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: GalleryTimelineView(
              mobileMode: mobileMode,
              maxTileSize: mobileMode ? 150 : null,
              onOpenViewer: opened.add,
              onContextMenu: (record, _) => contextMenus.add(record.path),
              onMobileLongPress: (record) => longPressed.add(record.path),
              onUseImage: (_) async {},
              onFavoriteMenu: (record, anchor) {},
              onClearFilters: () {},
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 40));
      if (find.byType(LocalImageCard).evaluate().isNotEmpty) break;
    }
  }

  Future<void> disposeTimeline(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('mobile tap opens the viewer and long-press raises the menu', (
    tester,
  ) async {
    await pumpTimeline(tester, mobileMode: true);
    final cards = find.byType(LocalImageCard);
    expect(cards, findsWidgets);

    await tester.tap(cards.first);
    await tester.pump();
    expect(opened, [0]);
    expect(
      container.read(localGallerySelectionNotifierProvider).isActive,
      false,
    );

    await tester.longPress(cards.at(1));
    await tester.pump();
    expect(longPressed, [records[1].path]);
    expect(
      container.read(localGallerySelectionNotifierProvider).isActive,
      false,
      reason: '移动端长按应弹菜单，不应进入多选',
    );
    expect(tester.takeException(), isNull);

    await disposeTimeline(tester);
  });

  testWidgets(
    'desktop timeline keeps tap focus and never raises the mobile menu',
    (tester) async {
      await pumpTimeline(tester, mobileMode: false);
      final cards = find.byType(LocalImageCard);
      expect(cards, findsWidgets);

      await tester.tap(cards.first);
      await tester.pump();
      expect(opened, isEmpty);
      expect(
        container.read(localGalleryFocusNotifierProvider),
        records.first.path,
      );
      expect(
        container.read(localGallerySelectionNotifierProvider).isActive,
        false,
      );
      expect(contextMenus, isEmpty);
      expect(longPressed, isEmpty);
      expect(tester.takeException(), isNull);

      await disposeTimeline(tester);
    },
    // 桌面变体：拖拽包装器启用的路径。
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
