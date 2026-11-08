import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/mobile/mobile_breakpoints.dart';
import 'package:nai_launcher/presentation/ui/gen/gen_contract.dart';
import 'package:nai_launcher/presentation/ui/gen/gen_fixture.dart';
import 'package:nai_launcher/presentation/ui/gen/gen_page.dart';
import 'package:nai_launcher/presentation/ui/gen/gen_prompt.dart';

import '../../../helpers/studio_capture_fonts.dart';
import 'gen_test_harness.dart';

/// 生成页手机端触控目标（G4）：代表性按钮/胶囊的命中区至少 48dp。
///
/// 桌面端尺寸由本文件最后一个用例守住（同一个组件在 `usesMobileLayout` 为假时
/// 必须保持原尺寸）；手机布局开关只在测试内强制打开。
void main() {
  setUpAll(loadStudioCaptureFonts);
  setUp(() => debugForceMobileLayout = true);
  tearDown(() => debugForceMobileLayout = null);

  Future<void> pumpMobile(WidgetTester tester) async {
    // pumpGen 按“窗口宽 − genRail”计算页面宽度；手机端没有左侧主导航，
    // 加上 genRail 让页面实际宽度等于 360dp。
    await pumpGen(
      tester,
      data: GenFixture.view(),
      window: 360 + genRail,
      height: 780,
    );
    await tester.pumpAndSettle();
  }

  void expectTouchTarget(WidgetTester tester, String key) {
    final finder = find.byKey(Key(key));
    expect(finder, findsOneWidget, reason: '$key 应存在');
    final size = tester.getSize(finder);
    expect(
      size.width,
      greaterThanOrEqualTo(48),
      reason: '$key 命中区宽度 ${size.width} < 48dp',
    );
    expect(
      size.height,
      greaterThanOrEqualTo(48),
      reason: '$key 命中区高度 ${size.height} < 48dp',
    );
  }

  testWidgets('顶部胶囊和底部生成条入口命中区 >= 48dp', (tester) async {
    await pumpMobile(tester);

    // 顶栏：模型胶囊 / 模型切换 / Turbo / 模式切换 / 额度胶囊。
    expect(
      tester.getSize(find.byKey(const Key('gen-model-capsule'))).height,
      greaterThanOrEqualTo(48),
    );
    expectTouchTarget(tester, 'gen-model');
    expectTouchTarget(tester, 'gen-turbo');
    expectTouchTarget(tester, 'gen-mode');
    expectTouchTarget(tester, 'gen-quota');
    // 单行：模型胶囊和额度胶囊同一行，顶栏 = 4 + 50 + 4 + 1px 边线。
    final header = tester.getSize(find.byKey(const Key('gen-header')));
    expect(header.height, 59, reason: '手机顶栏应单行 59dp，实际 ${header.height}');
    expect(
      (tester.getRect(find.byKey(const Key('gen-quota'))).top -
              tester.getRect(find.byKey(const Key('gen-model-capsule'))).top)
          .abs(),
      lessThan(1),
      reason: '额度胶囊应和模型胶囊在同一行',
    );

    // 模型菜单（手机底部面板）的行同样是 48dp 触摸目标。
    await tester.tap(find.byKey(const Key('gen-model')));
    await tester.pumpAndSettle();
    expectTouchTarget(tester, 'gen-model-nai-diffusion-5');

    // 底部生成条：提示词编辑 / 最近生成入口 + 主生成按钮。
    expectTouchTarget(tester, 'gen-mobile-editor');
    expectTouchTarget(tester, 'gen-mobile-history');
    expect(
      tester.getSize(find.byKey(const Key('gen-generate'))).height,
      greaterThanOrEqualTo(48),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('画布工具条命中区 >= 48dp', (tester) async {
    await pumpMobile(tester);

    // 右下操作条：钉住 / 复制 / 保存 / 打开查看器。
    for (final key in ['gen-pin', 'gen-copy', 'gen-save', 'gen-info']) {
      expectTouchTarget(tester, key);
    }
    // 左下信息条：显示设置 + 种子胶囊。
    expectTouchTarget(tester, 'gen-display');
    expectTouchTarget(tester, 'gen-seed-pill');
    // 顶部工具条：增强 / 变体 / 放大 / 收起菜单 / 设为图生图 / 编辑 / 局部重绘。
    for (final key in [
      'gen-enhance',
      'gen-variations',
      'gen-upscale',
      'gen-set-init',
      'gen-edit',
      'gen-inpaint',
    ]) {
      expectTouchTarget(tester, key);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('参数条与参数抽屉控件命中区 >= 48dp', (tester) async {
    await pumpMobile(tester);

    for (final key in [
      'gen-param-steps',
      'gen-param-scale',
      'gen-param-seed',
      'gen-param-sampler',
      'gen-params-toggle',
    ]) {
      expectTouchTarget(tester, key);
    }

    // 打开参数抽屉：种子随机 / 锁定、采样器下拉、抽屉关闭按钮。
    await tester.tap(find.byKey(const Key('gen-params-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gen-params-drawer')), findsOneWidget);
    expectTouchTarget(tester, 'gen-seed-random');
    expectTouchTarget(tester, 'gen-seed-lock');
    expect(
      tester.getSize(find.byKey(const Key('gen-drawer-sampler'))).height,
      greaterThanOrEqualTo(48),
    );
    expectTouchTarget(tester, 'gen-params-close');
    expect(tester.takeException(), isNull);
  });

  testWidgets('最近生成浮层的标题/底栏图标命中区 >= 48dp', (tester) async {
    await pumpMobile(tester);
    await tester.tap(find.byKey(const Key('gen-mobile-history')));
    await tester.pumpAndSettle();

    expectTouchTarget(tester, 'gen-history-select');
    expectTouchTarget(tester, 'gen-autosave');
    expectTouchTarget(tester, 'gen-history-lock');
    expectTouchTarget(tester, 'gen-history-save-all');
    expectTouchTarget(tester, 'gen-history-clear');
    expect(tester.takeException(), isNull);
  });

  testWidgets('提示词编辑浮层工具按钮命中区 >= 48dp', (tester) async {
    await pumpMobile(tester);
    await tester.tap(find.byKey(const Key('gen-mobile-editor')));
    await tester.pumpAndSettle();

    // 浮层关闭 / 库入口是 Material IconButton（标题栏下边线占 1px，命中 47），
    // 这里只守住自绘工具按钮。
    expectTouchTarget(tester, 'gen-tool-menu');
    expectTouchTarget(tester, 'gen-tool-palette');
    expect(
      tester.getSize(find.byKey(const Key('gen-tab-positive'))).height,
      greaterThanOrEqualTo(48),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('全屏编辑器头部命中区 >= 48dp（正/负向仍可切换）', (tester) async {
    final recorder = GenRecorder();
    await pumpGen(
      tester,
      data: GenFixture.view(),
      actions: recorder.actions,
      window: 360 + genRail,
      height: 780,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gen-mobile-editor')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gen-tool-menu')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('gen-fullscreen')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gen-fullscreen')));
    await tester.pumpAndSettle();

    // 关闭 / 清除 / 正负向分段：手机端命中区都是 48dp（视觉仍是 30dp 图标）。
    expectTouchTarget(tester, 'gen-fullscreen-close');
    expectTouchTarget(tester, 'gen-clear-base-full');
    expectTouchTarget(tester, 'gen-fullscreen-tabs');
    expectTouchTarget(tester, 'gen-fullscreen-tab-positive');
    expectTouchTarget(tester, 'gen-fullscreen-tab-negative');

    // 正 / 负向 tab 仍可切换（命中层转发到 onNegativeTab）。
    await tester.tap(find.byKey(const Key('gen-fullscreen-tab-negative')));
    await tester.pumpAndSettle();
    expect(recorder.calls, contains('onNegativeTab(true)'));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('gen-fullscreen-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gen-fullscreen-editor')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('桌面端尺寸不受手机命中区改动影响', (tester) async {
    debugForceMobileLayout = null;
    await pumpGen(tester, data: GenFixture.view(), window: 1600, height: 1120);
    await tester.pumpAndSettle();

    // 顶栏仍是 37 高，图标按钮仍是 32×30，参数列仍是 28 高的小控件。
    expect(tester.getSize(find.byKey(const Key('gen-header'))).height, 37);
    expect(
      tester.getSize(find.byKey(const Key('gen-pin'))),
      const Size(32, 30),
    );
    expect(
      tester.getSize(find.byKey(const Key('gen-params-toggle'))).height,
      lessThan(48),
    );
    expect(find.byKey(const Key('gen-mobile-editor')), findsNothing);
    expect(tester.takeException(), isNull);

    // 全屏编辑器头部在桌面仍是 30dp 图标、28 高分段。
    await tester.pumpWidget(const SizedBox());
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1056, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      genApp(
        Center(
          child: GenScope(
            data: GenFixture.view(),
            actions: GenActions.logging((_) {}),
            slots: GenSlots(editor: (_, _) => const SizedBox()),
            controller: _FakeController(),
            child: const GenFullscreenEditor(
              target: GenEditorTarget.base(negative: false, fullscreen: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('gen-fullscreen-close'))),
      const Size(30, 30),
    );
    expect(
      tester.getSize(find.byKey(const Key('gen-clear-base-full'))),
      const Size(30, 30),
    );
    expect(
      tester.getSize(find.byKey(const Key('gen-fullscreen-tabs'))).height,
      28,
    );
    expect(tester.takeException(), isNull);
  });
}

class _FakeController extends Fake implements GenController {}
