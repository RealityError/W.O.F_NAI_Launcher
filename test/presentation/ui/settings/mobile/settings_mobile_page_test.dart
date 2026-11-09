// 手机端设置页集成测试：真实 SettingsPage 在手机竖屏宽度走移动分支，
// 详情页复用真实页面内容（SettingsPageFrame / SettingsRow 等），验证
// 列表 → 详情 → 返回、深链、搜索与各页 RenderFlex 溢出。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/ui/settings/settings_contract.dart';

import '../../../../helpers/studio_capture_fonts.dart';
import '../settings_test_harness.dart';

/// Android 手机端实际可见的设置页。
///
/// 用生产口径过滤（[settingsPageAvailable]），避免手写清单漏跟隐藏页：
/// agent / rag / upscale / network 依赖桌面运行时，shortcuts 需要物理键盘。
final _mobilePages = SettingsPageId.values
    .where(settingsPageAvailable)
    .toList(growable: false);

/// 验收范围的手机竖屏逻辑宽度（dp）。
const _phoneWidths = [360.0, 430.0];

Future<SettingsRecorder> pumpPhone(
  WidgetTester tester, {
  SettingsPageId page = SettingsPageId.overview,
  SettingsViewData? data,
  String initialQuery = '',
  double width = 360,
}) => pumpSettings(
  tester,
  window: width + settingsRail,
  height: 780,
  page: page,
  data: data,
  initialQuery: initialQuery,
);

void main() {
  setUpAll(loadStudioCaptureFonts);
  setUp(() => debugForceMobileSettingsLayout = true);
  tearDown(() => debugForceMobileSettingsLayout = false);

  testWidgets('手机布局：列表 → 真实详情页 → 返回', (tester) async {
    final rec = await pumpPhone(tester);
    expect(find.byKey(const Key('settings-mobile-list')), findsOneWidget);
    // 桌面专属页不出现在列表里。
    expect(find.byKey(const Key('settings-mobile-page-agent')), findsNothing);
    expect(find.byKey(const Key('settings-mobile-page-rag')), findsNothing);
    // 触屏没有物理键盘，快捷键录制页没有意义。
    expect(
      find.byKey(const Key('settings-mobile-page-shortcuts')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('settings-mobile-page-appearance')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('settings-mobile-detail-appearance')),
      findsOneWidget,
    );
    // 复用桌面页面内容（主题切换卡片等真实控件）。
    expect(find.byKey(const Key('theme-system')), findsOneWidget);
    expect(rec.pages, contains(SettingsPageId.appearance));

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-mobile-list')), findsOneWidget);
  });

  testWidgets('手机布局：section 深链直接进对应详情', (tester) async {
    await pumpPhone(tester, page: SettingsPageId.account);
    expect(
      find.byKey(const Key('settings-mobile-detail-account')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('settings-mobile-list')), findsNothing);
  });

  testWidgets('手机布局：搜索命中进入详情并滚动到锚点', (tester) async {
    await pumpPhone(tester);
    await tester.enterText(
      find.byKey(const Key('settings-mobile-search-input')),
      'theme',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-mobile-hit-themeMode')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('settings-mobile-detail-appearance')),
      findsOneWidget,
    );
    // 搜索跳转的锚点落在真实行上（SettingsAnchor / SettingsRow 的 anchor）。
    expect(find.byKey(const Key('settings-anchor-themeMode')), findsOneWidget);
    // 走完高亮计时器，避免测试结束时仍有 pending timer。
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('手机布局：360–430dp 下各可见设置页详情无 RenderFlex 溢出', (tester) async {
    for (final width in _phoneWidths) {
      for (final page in _mobilePages) {
        // pumpSettings 复用同一 Element 树；先卸载，确保每页都用新的 data 重建。
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await pumpPhone(tester, page: page, width: width);
        if (page == SettingsPageId.overview) {
          await tester.tap(
            find.byKey(const Key('settings-mobile-page-overview')),
          );
          await tester.pumpAndSettle();
        }
        final where = '${width.round()}dp ${page.name}';
        expect(
          find.byKey(Key('settings-mobile-detail-${page.name}')),
          findsOneWidget,
          reason: '$where 应已打开详情',
        );
        expect(tester.takeException(), isNull, reason: '$where 首屏');

        final scroll = find.byKey(const Key('settings-scroll'));
        expect(scroll, findsOneWidget, reason: '$where 缺滚动容器');
        await tester.drag(scroll, const Offset(0, -700));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$where 第一屏滚动');
        await tester.drag(scroll, const Offset(0, -2600));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$where 滚动到底');
      }
    }
  });
}
