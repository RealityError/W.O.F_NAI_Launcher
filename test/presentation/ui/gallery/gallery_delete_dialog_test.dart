import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/themes/presets/geist_theme.dart';
import 'package:nai_launcher/presentation/ui/gallery/gallery_delete_dialog.dart';

Future<bool?> _show(
  WidgetTester tester, {
  required int count,
  String? fileName,
  bool permanent = false,
  Size surfaceSize = const Size(1000, 800),
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  bool? result;
  await tester.pumpWidget(
    MaterialApp(
      theme: GeistTheme.light,
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            key: const Key('open-delete-dialog'),
            onPressed: () async {
              result = await GalleryDeleteDialog.show(
                context,
                count: count,
                fileName: fileName,
                permanent: permanent,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-delete-dialog')));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('move-to-pool dialog explains the trash and can cancel', (
    tester,
  ) async {
    await _show(tester, count: 3);

    expect(find.byKey(const Key('gallery-delete-dialog')), findsOneWidget);
    expect(find.text('将 3 张图片移入删除池？'), findsOneWidget);
    expect(find.textContaining('重启'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gallery-delete-dialog')), findsNothing);
  });

  testWidgets('single image shows the file name', (tester) async {
    await _show(tester, count: 1, fileName: 'image-001.png');

    expect(find.text('image-001.png'), findsOneWidget);
    expect(find.text('将这张图片移入删除池？'), findsOneWidget);
  });

  testWidgets('permanent delete uses the danger confirm and returns true', (
    tester,
  ) async {
    await _show(tester, count: 2, permanent: true);

    expect(find.byKey(const Key('gallery-delete-dialog')), findsOneWidget);
    expect(find.text('彻底删除这 2 张图片？'), findsOneWidget);
    expect(find.textContaining('无法恢复'), findsOneWidget);
    expect(find.byKey(const Key('gallery-delete-confirm')), findsOneWidget);

    await tester.tap(find.byKey(const Key('gallery-delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gallery-delete-dialog')), findsNothing);
  });

  testWidgets('fits a 360x640 phone portrait surface', (tester) async {
    await _show(
      tester,
      count: 4,
      permanent: true,
      surfaceSize: const Size(360, 640),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('gallery-delete-dialog')), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('gallery-delete-dialog')), findsNothing);
  });
}
