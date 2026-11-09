import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/mobile/mobile_breakpoints.dart';
import 'package:nai_launcher/presentation/widgets/gallery/date_range_picker_dialog.dart';

import '../../../helpers/studio_capture_fonts.dart';

/// 日期范围选择 360dp 移动端回归：7×48 网格不溢出、选日/确认/取消可点。
void main() {
  setUp(() => debugForceMobileLayout = true);
  tearDown(() => debugForceMobileLayout = null);

  Future<void> pumpWithDialog(
    WidgetTester tester, {
    required void Function(DateRangeSelectionState?) onPicked,
    Size size = const Size(360, 640),
    String locale = 'en',
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loadStudioCaptureFonts();
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  onPicked(await showGalleryDateRangePicker(context));
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('360dp 日期格 48dp、选中后可确认、无溢出', (tester) async {
    DateRangeSelectionState? picked;
    await pumpWithDialog(tester, onPicked: (v) => picked = v);
    expect(tester.takeException(), isNull);

    final now = DateTime.now();
    final day = DateTime(now.year, now.month, 1);
    final cell = find.byKey(ValueKey(day));
    expect(cell, findsOneWidget);
    expect(tester.getSize(cell), const Size(48, 48));

    // 选一天 → 确认按钮可用 → 返回单日范围。
    await tester.tap(cell);
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(GalleryDateRangePicker));
    final l10n = AppLocalizations.of(context)!;
    await tester.tap(find.text(l10n.common_confirm));
    await tester.pumpAndSettle();
    expect(picked, isNotNull);
    expect(picked!.start, day);
    expect(picked!.end, day);
    expect(tester.takeException(), isNull);
  });

  testWidgets('360dp 取消关闭且不返回结果', (tester) async {
    var called = false;
    DateRangeSelectionState? picked;
    await pumpWithDialog(
      tester,
      onPicked: (v) {
        called = true;
        picked = v;
      },
    );
    final context = tester.element(find.byType(GalleryDateRangePicker));
    final l10n = AppLocalizations.of(context)!;
    await tester.tap(find.text(l10n.common_cancel));
    await tester.pumpAndSettle();
    expect(called, isTrue);
    expect(picked, isNull);
    expect(find.byType(GalleryDateRangePicker), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('桌面端日期格保持 36（手机 48 不影响桌面）', (tester) async {
    debugForceMobileLayout = false;
    await pumpWithDialog(
      tester,
      onPicked: (_) {},
      size: const Size(1280, 900),
      locale: 'zh',
    );
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, 1);
    final cell = find.byKey(ValueKey(day));
    expect(cell, findsOneWidget);
    // 桌面端视觉圆保持 36；手机端才是 40 视觉 / 48 命中。
    expect(
      tester.getSize(
        find.descendant(of: cell, matching: find.byType(AnimatedContainer)),
      ),
      const Size(36, 36),
    );
    expect(tester.takeException(), isNull);
  });
}
