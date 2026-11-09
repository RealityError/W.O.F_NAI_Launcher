// 手机端「设置 → 桥接与集成」：状态卡置顶、ComfyUI 地址整宽、360–430dp 无溢出；
// 桌面端仍保持右侧状态侧注。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/ui/settings/settings_contract.dart';

import '../../../../helpers/studio_capture_fonts.dart';
import '../settings_test_harness.dart';

const _phoneWidths = [360.0, 430.0];

Future<void> pumpBridges(
  WidgetTester tester, {
  required double window,
  double height = 780,
}) => pumpSettings(
  tester,
  window: window,
  height: height,
  page: SettingsPageId.bridges,
);

void main() {
  setUpAll(loadStudioCaptureFonts);
  setUp(() => debugForceMobileSettingsLayout = true);
  tearDown(() => debugForceMobileSettingsLayout = false);

  testWidgets('手机布局：状态卡在内容最上方，ComfyUI 地址整宽，无溢出', (tester) async {
    for (final width in _phoneWidths) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await pumpBridges(tester, window: width + settingsRail);
      final where = '${width.round()}dp';
      expect(
        find.byKey(const Key('settings-mobile-detail-bridges')),
        findsOneWidget,
        reason: '$where 应已打开桥接详情',
      );
      expect(tester.takeException(), isNull, reason: '$where 首屏');

      // 状态卡不再作为右侧侧注，而是内容区第一块。
      final status = find.byKey(const Key('bridges-status'));
      expect(status, findsOneWidget, reason: '$where 缺状态卡');
      expect(
        tester.getTopLeft(status).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('setting-comfyEnabled'))).dy,
        ),
        reason: '$where 状态卡应在 ComfyUI 设置之前',
      );

      // ComfyUI 地址框占满一行，测试按钮单独一行仍在。
      final url = find.byKey(const Key('input-comfyUrl'));
      expect(url, findsOneWidget, reason: '$where 缺 ComfyUI 地址框');
      expect(
        tester.getSize(url).width,
        greaterThan(200),
        reason: '$where 地址框应接近整宽',
      );
      expect(find.byKey(const Key('comfy-test')), findsOneWidget);

      final scroll = find.byKey(const Key('settings-scroll'));
      await tester.drag(scroll, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$where 第一屏滚动');
      await tester.drag(scroll, const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$where 滚动到底');
    }
  });

  testWidgets('桌面布局：桥接页仍用右侧状态侧注', (tester) async {
    await pumpBridges(tester, window: 1600, height: 1000);
    expect(find.byKey(const Key('bridges-status')), findsOneWidget);
    expect(find.byKey(const Key('comfy-test')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
