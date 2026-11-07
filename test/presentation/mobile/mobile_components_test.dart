import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/mobile/mobile_breakpoints.dart';
import 'package:nai_launcher/presentation/mobile/mobile_context_menu.dart';
import 'package:nai_launcher/presentation/mobile/mobile_list.dart';
import 'package:nai_launcher/presentation/mobile/mobile_scaffold.dart';
import 'package:nai_launcher/presentation/mobile/mobile_sheet.dart';
import 'package:nai_launcher/presentation/mobile/mobile_touch.dart';

/// 手机端地基组件的 360dp 布局 smoke 测试。
///
/// 目标不是像素对比，而是保证在手机竖屏下不出现 RenderFlex overflow、
/// 关键交互（返回、长按菜单、底部弹层、列表行）可用。
void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  Future<void> pumpPhone(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(wrap(child));
    await tester.pumpAndSettle();
  }

  testWidgets('MobilePageScaffold renders at 360dp without overflow', (
    tester,
  ) async {
    var backTapped = false;
    await pumpPhone(
      tester,
      MobilePageScaffold(
        title: '设置',
        subtitle: '手机端布局',
        actions: [
          MobileHeaderAction(icon: Icons.search, tooltip: '搜索', onTap: () {}),
        ],
        onBack: () => backTapped = true,
        bottomBar: const Padding(
          padding: EdgeInsets.all(12),
          child: Text('bottom bar'),
        ),
        child: ListView(
          children: [
            const MobileSectionHeader(title: '个人'),
            MobileListTile(
              icon: Icons.person_outline,
              title: '账号',
              subtitle: '登录状态与订阅',
              trailingText: 'Opus',
              onTap: () {},
            ),
            MobileListTile(
              icon: Icons.palette_outlined,
              title: '外观',
              subtitle: '主题、字体与密度',
              onTap: () {},
            ),
          ],
        ),
      ),
    );

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('账号'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('搜索'));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pump();
    expect(backTapped, isTrue);
  });

  testWidgets('showMobileSheet opens and dismisses', (tester) async {
    await pumpPhone(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showMobileSheet<void>(
                context: context,
                title: '参数',
                builder: (_) => const MobileSheetScrollView(
                  children: [ListTile(title: Text('步数'))],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('参数'), findsOneWidget);
    expect(find.text('步数'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile context menu shows long-press entries', (tester) async {
    var tapped = false;
    await pumpPhone(
      tester,
      Scaffold(
        body: Center(
          child: MobileContextMenuRegion(
            enabled: true,
            title: '图片操作',
            items: [
              MobileMenuItem(
                label: '分享',
                icon: Icons.share_outlined,
                onTap: () => tapped = true,
              ),
              const MobileMenuItem(
                label: '删除',
                icon: Icons.delete_outline,
                destructive: true,
              ),
            ],
            child: MobileTapCard(
              onTap: () {},
              child: const SizedBox(
                width: 160,
                height: 120,
                child: ColoredBox(color: Colors.grey),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.longPress(find.byType(MobileTapCard));
    await tester.pumpAndSettle();
    expect(find.text('图片操作'), findsOneWidget);
    await tester.tap(find.text('分享'));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  test('breakpoint helpers stay aligned with the documented values', () {
    expect(kMobileBreakpoint, 600);
    expect(kTabletBreakpoint, 900);
    expect(kMobileMinTouchTarget, greaterThanOrEqualTo(44));
  });
}
