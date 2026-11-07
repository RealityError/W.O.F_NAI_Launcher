// 手机端设置页（列表 → 详情）组件测试：分组列表、详情导航、搜索、深链、浮条。
//
// 宿主测试环境无法模拟 Android 平台，用 settings_contract.dart 的
// debugForceMobileSettingsLayout 让 settingsPageAvailable 按 Android 口径工作；
// 手机布局本身由 MobileSettingsView 直接渲染验证。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/mobile/mobile_list.dart';
import 'package:nai_launcher/presentation/themes/presets/geist_theme.dart';
import 'package:nai_launcher/presentation/ui/settings/settings_contract.dart';
import 'package:nai_launcher/presentation/ui/settings/settings_fixture.dart';
import 'package:nai_launcher/presentation/ui/settings/settings_mobile.dart';
import 'package:nai_launcher/presentation/ui/settings/settings_scope.dart';

import '../../../../helpers/studio_capture_fonts.dart';

/// 手机布局测试宿主：提供 SettingsScope 的假数据与回调，并记录跳转/撤销/确认。
class _MobileHost extends StatefulWidget {
  const _MobileHost({
    super.key,
    required this.data,
    this.initialQuery = '',
    this.initialAnchor,
    this.toast,
  });

  final SettingsViewData data;
  final String initialQuery;
  final String? initialAnchor;
  final SettingsChange? toast;

  @override
  State<_MobileHost> createState() => _MobileHostState();
}

class _MobileHostState extends State<_MobileHost> {
  late SettingsViewData _data = widget.data;
  late SettingsChange? _toast = widget.toast;
  String? _highlight;

  final jumps = <(SettingsPageId, String?)>[];
  final confirmTitles = <String>[];
  final resetPages = <SettingsPageId>[];
  final undos = <String>[];

  @override
  void initState() {
    super.initState();
    _highlight = widget.initialAnchor;
  }

  /// 模拟接线方在外部切页（账号 / 桥接打开请求、页面内 jump）。
  void switchTo(SettingsPageId page) =>
      setState(() => _data = _data.copyWith(page: page));

  void _confirm({
    required String title,
    required String body,
    required String confirm,
    bool danger = false,
    required VoidCallback onConfirm,
  }) {
    confirmTitles.add(title);
    onConfirm();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScope(
      data: _data,
      actions: SettingsActions(
        onOpenPage: (page) =>
            setState(() => _data = _data.copyWith(page: page)),
        onResetPage: (page) => resetPages.add(page),
        onUndo: (id) => undos.add(id),
      ),
      highlight: _highlight,
      confirm: _confirm,
      jump: (page, {anchor}) {
        jumps.add((page, anchor));
        setState(() {
          _data = _data.copyWith(page: page);
          _highlight = anchor;
        });
      },
      reportDirty: (_) {},
      child: MobileSettingsView(
        data: _data,
        pageBuilder: (page) => Text(
          'mobile-content-${page.name}',
          key: Key('mobile-content-${page.name}'),
        ),
        guard: (go) => go(),
        initialQuery: widget.initialQuery,
        initialAnchor: widget.initialAnchor,
        toast: _toast,
        onDismissToast: () => setState(() => _toast = null),
      ),
    );
  }
}

/// 在 360×780 竖屏下装一个手机设置页。
Future<GlobalKey<_MobileHostState>> _pumpMobileSettings(
  WidgetTester tester, {
  SettingsViewData? data,
  String initialQuery = '',
  String? initialAnchor,
  SettingsChange? toast,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 780);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final host = GlobalKey<_MobileHostState>();
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: GeistTheme.light,
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: _MobileHost(
        key: host,
        data: data ?? SettingsFixture.view(),
        initialQuery: initialQuery,
        initialAnchor: initialAnchor,
        toast: toast,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return host;
}

void main() {
  setUpAll(loadStudioCaptureFonts);
  setUp(() => debugForceMobileSettingsLayout = true);
  tearDown(() => debugForceMobileSettingsLayout = false);

  testWidgets('列表页：分组标题 + 可见页行 + 隐藏桌面专属页', (tester) async {
    await _pumpMobileSettings(tester);
    expect(find.byKey(const Key('settings-mobile-list')), findsOneWidget);
    expect(
      find.byKey(const Key('settings-mobile-page-overview')),
      findsOneWidget,
    );
    // 列表按分组标题分段（首屏可见“个人”组；其余分组滚动后也有覆盖）。
    expect(find.byType(MobileSectionHeader), findsWidgets);
    final listScrollable = find.descendant(
      of: find.byKey(const Key('settings-mobile-list')),
      matching: find.byType(Scrollable),
    );
    for (final page in SettingsPageId.values) {
      final tile = find.byKey(Key('settings-mobile-page-${page.name}'));
      if (!settingsPageAvailable(page)) {
        // 桌面专属页（agent / rag / upscale / network）不进入手机列表。
        expect(tile, findsNothing, reason: page.name);
        continue;
      }
      await tester.scrollUntilVisible(tile, 120, scrollable: listScrollable);
      expect(tile, findsOneWidget, reason: page.name);
    }
  });

  testWidgets('列表页在 360dp 下滚动到底部无溢出', (tester) async {
    await _pumpMobileSettings(tester);
    await tester.drag(
      find.byKey(const Key('settings-mobile-list')),
      const Offset(0, -1600),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(SettingsFixture.view().version), findsOneWidget);
    expect(
      find.byKey(const Key('settings-mobile-update-badge')),
      findsOneWidget,
    );
  });

  testWidgets('点击页面进详情；左上返回与系统返回都回到列表', (tester) async {
    final host = await _pumpMobileSettings(tester);
    await tester.tap(find.byKey(const Key('settings-mobile-page-appearance')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('settings-mobile-detail-appearance')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('mobile-content-appearance')), findsOneWidget);
    expect(host.currentState!.jumps, [(SettingsPageId.appearance, null)]);

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-mobile-list')), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-mobile-page-canvas')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('settings-mobile-detail-canvas')),
      findsOneWidget,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-mobile-list')), findsOneWidget);
  });

  testWidgets('搜索命中直接进入详情并带锚点', (tester) async {
    final host = await _pumpMobileSettings(tester);
    await tester.enterText(
      find.byKey(const Key('settings-mobile-search-input')),
      'theme',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('settings-mobile-search-results')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('settings-mobile-hit-themeMode')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('settings-mobile-detail-appearance')),
      findsOneWidget,
    );
    expect(host.currentState!.jumps.last, (
      SettingsPageId.appearance,
      'themeMode',
    ));
  });

  testWidgets('搜索无结果时显示空态', (tester) async {
    await _pumpMobileSettings(tester);
    await tester.enterText(
      find.byKey(const Key('settings-mobile-search-input')),
      '不存在的设置 xyzzy',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('settings-mobile-search-empty')),
      findsOneWidget,
    );
  });

  testWidgets('深链 initialQuery 打开搜索结果', (tester) async {
    await _pumpMobileSettings(tester, initialQuery: 'theme');
    expect(
      find.byKey(const Key('settings-mobile-search-results')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('settings-mobile-hit-themeMode')),
      findsOneWidget,
    );
  });

  testWidgets('深链 initialAnchor 直接打开锚点所在页', (tester) async {
    await _pumpMobileSettings(
      tester,
      data: SettingsFixture.view(),
      initialAnchor: 'rescan',
    );
    expect(
      find.byKey(const Key('settings-mobile-detail-storage')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('settings-mobile-list')), findsNothing);
  });

  testWidgets('深链锚点找不到时退回列表', (tester) async {
    await _pumpMobileSettings(tester, initialAnchor: 'not-a-real-anchor');
    expect(find.byKey(const Key('settings-mobile-list')), findsOneWidget);
  });

  testWidgets('外部页面请求（data.page 变化）直接进详情并可再切页', (tester) async {
    final host = await _pumpMobileSettings(
      tester,
      data: SettingsFixture.view(page: SettingsPageId.account),
    );
    expect(
      find.byKey(const Key('settings-mobile-detail-account')),
      findsOneWidget,
    );
    host.currentState!.switchTo(SettingsPageId.privacy);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('settings-mobile-detail-privacy')),
      findsOneWidget,
    );
  });

  testWidgets('已保存浮条可撤销，撤销后浮条消失', (tester) async {
    final host = await _pumpMobileSettings(
      tester,
      toast: SettingsChange(
        id: 'c1',
        title: '主题',
        from: '浅色',
        to: '深色',
        at: SettingsFixture.now,
      ),
    );
    expect(find.byKey(const Key('settings-mobile-toast')), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-mobile-undo-c1')));
    await tester.pumpAndSettle();
    expect(host.currentState!.undos, ['c1']);
    expect(find.byKey(const Key('settings-mobile-toast')), findsNothing);
  });

  testWidgets('详情页右上提供“恢复本页默认”（手机端无 hover 入口）', (tester) async {
    final host = await _pumpMobileSettings(
      tester,
      data: SettingsFixture.view(page: SettingsPageId.appearance),
    );
    expect(find.byKey(const Key('settings-mobile-reset-page')), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-mobile-reset-page')));
    await tester.pumpAndSettle();
    expect(host.currentState!.confirmTitles, isNotEmpty);
    expect(host.currentState!.resetPages, [SettingsPageId.appearance]);
  });

  testWidgets('手机端设置页在 360×780 无 RenderFlex 溢出', (tester) async {
    await _pumpMobileSettings(tester);
    expect(tester.takeException(), isNull);
  });
}
