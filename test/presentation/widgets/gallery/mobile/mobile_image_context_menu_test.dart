import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/widgets/gallery/local_image_context_menu.dart';

/// 手机端长按菜单：动作集合与桌面右键同源，但以 bottom sheet 平铺展示。
void main() {
  testWidgets('mobile context menu flattens actions and returns the choice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    LocalImageContextAction? selected;
    Future<void> openMenu(BuildContext context) async {
      selected = await LocalImageContextMenu.showMobile(
        context,
        title: 'image_1.png',
        hasImportableMetadata: true,
        hasPrompt: true,
        hasSeed: true,
        isKritaConnected: false,
        isFavorite: false,
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => openMenu(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('image_1.png'), findsOneWidget);
    expect(find.text('详情'), findsOneWidget);
    expect(find.text('已收藏'), findsOneWidget);
    expect(find.text('复制图片'), findsOneWidget);
    expect(find.text('复制 Prompt'), findsOneWidget);
    expect(find.text('复制种子'), findsOneWidget);
    // 桌面专属动作不外泄到手机菜单。
    expect(find.text('发送到 Krita'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('详情'));
    await tester.pumpAndSettle();
    expect(selected, LocalImageContextAction.details);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('放大'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('放大'));
    await tester.pumpAndSettle();
    expect(selected, LocalImageContextAction.upscale);

    // 底部动作在弹层里可滚动到达（删除在菜单末尾）。
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('删除'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('删除'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(selected, LocalImageContextAction.delete);
  });
}
