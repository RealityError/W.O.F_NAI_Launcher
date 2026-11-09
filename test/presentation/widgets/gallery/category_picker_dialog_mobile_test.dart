import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/gallery/gallery_category.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/mobile/mobile_breakpoints.dart';
import 'package:nai_launcher/presentation/providers/gallery_category_provider.dart';
import 'package:nai_launcher/presentation/widgets/gallery/category_picker_dialog.dart';

import '../../../helpers/studio_capture_fonts.dart';

class _MockCategoryNotifier extends GalleryCategoryNotifier {
  final List<GalleryCategory> _categories;

  _MockCategoryNotifier(this._categories);

  @override
  GalleryCategoryState build() => GalleryCategoryState(categories: _categories);
}

/// 分类选择对话框 360dp 移动端回归：整屏弹层、无溢出、关键按钮可点。
void main() {
  final now = DateTime.now();
  final categories = <GalleryCategory>[
    GalleryCategory(
      id: 'cat-1',
      name: '2026-09-09',
      folderPath: '2026-09-09',
      sortOrder: 0,
      imageCount: 5,
      createdAt: now,
      updatedAt: now,
    ),
    GalleryCategory(
      id: 'cat-sub-1',
      parentId: 'cat-1',
      name: 'Drafts',
      folderPath: '2026-09-09/Drafts',
      sortOrder: 0,
      imageCount: 2,
      createdAt: now,
      updatedAt: now,
    ),
    GalleryCategory(
      id: 'cat-ext-1',
      name: 'External Source',
      folderPath: r'D:\External\Photos',
      sortOrder: 1,
      imageCount: 10,
      createdAt: now,
      updatedAt: now,
    ),
  ];

  setUp(() {
    CategoryPickerDialog.debugClearSessionExpandedIds();
    debugForceMobileLayout = true;
  });
  tearDown(() => debugForceMobileLayout = null);

  Widget app({double width = 360, double height = 640, String locale = 'zh'}) {
    return ProviderScope(
      overrides: [
        galleryCategoryNotifierProvider.overrideWith(
          () => _MockCategoryNotifier(categories),
        ),
      ],
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () =>
                    CategoryPickerDialog.show(context, title: '移动到…'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> pumpApp(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loadStudioCaptureFonts();
    await tester.pumpWidget(app(width: size.width, height: size.height));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('360dp 打开为整屏弹层、无溢出、展开与关闭都可点', (tester) async {
    await pumpApp(tester, const Size(360, 640));
    expect(tester.takeException(), isNull);

    final dialogSize = tester.getSize(find.byType(Dialog));
    expect(dialogSize.width, 360);
    expect(dialogSize.height, 640);

    // 关闭图标（默认 48 命中）。
    expect(
      tester.getSize(find.byKey(const ValueKey('category_picker_close'))),
      const Size(48, 48),
    );
    // 展开按钮手机端 48 命中。
    final expand = find.byKey(const ValueKey('category_picker_expand_cat-1'));
    expect(tester.getSize(expand).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(expand).height, greaterThanOrEqualTo(48));

    // 展开 cat-1 → 子分类出现；分类行本身 ≥48 高。
    await tester.tap(expand);
    await tester.pumpAndSettle();
    expect(find.text('Drafts'), findsOneWidget);
    final rootItem = find.byKey(const ValueKey('category_picker_item_cat-1'));
    expect(tester.getSize(rootItem).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);

    // 点根分类返回「未分类」结果并关闭。
    await tester.tap(find.byKey(const ValueKey('category_picker_root_item')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('360dp 英文长文案不溢出', (tester) async {
    debugForceMobileLayout = true;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loadStudioCaptureFonts();
    await tester.pumpWidget(app(locale: 'en'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('External Source'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('桌面端仍是 560 宽的 AlertDialog（未受手机改动影响）', (tester) async {
    debugForceMobileLayout = false;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(width: 1280, height: 900));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('category-picker-body'))),
      const Size(560, 700),
    );
    // 桌面展开按钮保持 18 视觉（+4 右间距=22 命中）。
    expect(
      tester
          .getSize(find.byKey(const ValueKey('category_picker_expand_cat-1')))
          .width,
      22,
    );
    expect(tester.takeException(), isNull);
  });
}
