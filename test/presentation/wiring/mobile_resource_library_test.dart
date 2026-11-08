import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/data/models/prompt_block/prompt_block.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/mobile/mobile_breakpoints.dart';
import 'package:nai_launcher/presentation/providers/floating_resource_windows_provider.dart';
import 'package:nai_launcher/presentation/themes/presets/geist_theme.dart';
import 'package:nai_launcher/presentation/wiring/floating_resource_sources.dart';
import 'package:nai_launcher/presentation/wiring/floating_resource_window.dart';
import 'package:nai_launcher/presentation/wiring/mobile_resource_library.dart';
import 'package:nai_launcher/presentation/widgets/prompt/blocks/prompt_block_drag_data.dart';

import '../providers/floating_resource_windows_test.dart'
    show MemoryWindowSettings;

/// 手机全屏资源库：桌面浮窗的标题栏/缩放角/拖拽在手机上换成点按列表。
void main() {
  late ProviderContainer container;
  late FloatingResourceWindows manager;

  setUp(() {
    debugForceMobileLayout = true;
    container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(MemoryWindowSettings()),
        floatingResourceWindowsProvider.overrideWith(
          FloatingResourceWindows.new,
        ),
        floatingBlocksProvider.overrideWith(
          (ref, id) async => [
            PromptBlock(
              id: 'b1',
              title: '天空块',
              content: '1girl, sky',
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          ],
        ),
      ],
    );
    manager = container.read(floatingResourceWindowsProvider.notifier);
    manager.setViewport(const Rect.fromLTWH(0, 0, 360, 780));
  });

  tearDown(() {
    debugForceMobileLayout = null;
    container.dispose();
  });

  testWidgets('mobile library renders full-screen chrome and tappable rows', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 780);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final id = manager.open(FloatingResourceKind.blocks, persist: false)!;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: GeistTheme.light,
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: MobileResourceLibraryPage(windowId: id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l = AppLocalizations.of(
      tester.element(find.byType(MobileResourceLibraryPage)),
    )!;
    expect(find.byType(FloatingResourceWindow), findsOneWidget);
    expect(find.text(l.blocks_title), findsOneWidget);
    expect(find.text(l.floating_mobileTapHint), findsOneWidget);
    expect(find.byKey(Key('floating-close-$id')), findsOneWidget);

    // 手机全屏页没有桌面浮窗的缩放角，也不启用拖拽。
    expect(find.byKey(Key('floating-resize-$id')), findsNothing);
    expect(find.byType(Draggable<PromptBlockDragData>), findsNothing);

    // 块行是可点按的 44dp 触摸目标。
    final row = find.byKey(const Key('floating-block-b1'));
    expect(row, findsOneWidget);
    expect(tester.getSize(row).height, 44);
    expect(tester.takeException(), isNull);
  });
}
