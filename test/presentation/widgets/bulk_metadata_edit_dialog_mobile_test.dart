import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/mobile/mobile_breakpoints.dart';
import 'package:nai_launcher/presentation/providers/selection_mode_provider.dart';
import 'package:nai_launcher/presentation/widgets/bulk_metadata_edit_dialog.dart';

import '../../helpers/studio_capture_fonts.dart';

class _MockSelectionNotifier extends LocalGallerySelectionNotifier {
  _MockSelectionNotifier(this._state);

  final SelectionModeState _state;

  @override
  SelectionModeState build() => _state;
}

/// 批量元数据编辑对话框 360dp 移动端回归：四种语言不溢出、新增文案生效、按钮可点。
void main() {
  setUp(() => debugForceMobileLayout = true);
  tearDown(() => debugForceMobileLayout = null);

  Widget app({String locale = 'zh'}) {
    return ProviderScope(
      overrides: [
        localGallerySelectionNotifierProvider.overrideWith(
          () => _MockSelectionNotifier(
            const SelectionModeState(isActive: true, selectedIds: {'a', 'b'}),
          ),
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
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const BulkMetadataEditDialog(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> pumpDialog(
    WidgetTester tester, {
    String locale = 'zh',
    Size size = const Size(360, 640),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loadStudioCaptureFonts();
    await tester.pumpWidget(app(locale: locale));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('360dp 中文：标题计数、分区文案与按钮可点、不溢出', (tester) async {
    await pumpDialog(tester);
    expect(tester.takeException(), isNull);

    final context = tester.element(find.byType(BulkMetadataEditDialog));
    final l10n = AppLocalizations.of(context)!;
    expect(find.text(l10n.bulkMetadata_title(2)), findsOneWidget);
    expect(find.text(l10n.bulkMetadata_tagsToAdd), findsOneWidget);
    expect(find.text(l10n.bulkMetadata_tagsToRemove), findsOneWidget);
    expect(find.text(l10n.bulkMetadata_promptSection), findsOneWidget);
    expect(find.text(l10n.bulkMetadata_promptComingSoon), findsOneWidget);
    expect(find.text(l10n.common_cancel), findsOneWidget);
    expect(find.text(l10n.common_apply), findsOneWidget);

    // 弹窗宽度铺满 360dp（左右 12 留边 + AlertDialog 默认 24 内容内边距）。
    final dialogWidth = tester
        .getSize(find.byKey(const Key('bulk-metadata-content')))
        .width;
    expect(dialogWidth, greaterThanOrEqualTo(280));
    expect(dialogWidth, lessThanOrEqualTo(360));

    // 未填标签点「应用」：提示至少输入一个标签，弹窗保留。
    await tester.tap(find.text(l10n.common_apply));
    await tester.pumpAndSettle();
    expect(find.text(l10n.bulkProgress_errorNoMetadataChanges), findsOneWidget);
    expect(find.byType(BulkMetadataEditDialog), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 取消关闭。
    await tester.tap(find.text(l10n.common_cancel));
    await tester.pumpAndSettle();
    expect(find.byType(BulkMetadataEditDialog), findsNothing);
  });

  testWidgets('360dp 英文 / 日文 / 韩文不溢出', (tester) async {
    for (final locale in const ['en', 'ja', 'ko']) {
      await pumpDialog(tester, locale: locale);
      expect(tester.takeException(), isNull, reason: '$locale 打开溢出');
      final context = tester.element(find.byType(BulkMetadataEditDialog));
      final l10n = AppLocalizations.of(context)!;
      expect(find.text(l10n.bulkMetadata_title(2)), findsOneWidget);
      expect(find.text(l10n.bulkMetadata_tagsToAddHint), findsOneWidget);
      expect(find.text(l10n.bulkMetadata_promptComingSoon), findsOneWidget);
      await tester.tap(find.text(l10n.common_cancel));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$locale 关闭异常');
    }
  });

  testWidgets('桌面端宽度仍按 500 收缩（不起 360dp 布局）', (tester) async {
    debugForceMobileLayout = false;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loadStudioCaptureFonts();
    await tester.pumpWidget(app());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(BulkMetadataEditDialog));
    final l10n = AppLocalizations.of(context)!;
    expect(find.text(l10n.bulkMetadata_title(2)), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('bulk-metadata-content'))).width,
      500,
    );
    expect(tester.takeException(), isNull);
  });
}
