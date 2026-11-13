import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/utils/localization_extension.dart';
import 'package:nai_launcher/presentation/mobile/mobile_breakpoints.dart';
import 'package:nai_launcher/presentation/ui/tools/tools_contract.dart';
import 'package:nai_launcher/presentation/ui/tools/tools_sheets.dart';
import 'package:nai_launcher/presentation/wiring/tools_generation_wiring.dart';

import '../../../helpers/studio_capture_fonts.dart';
import '../../../helpers/uiux_frontend_capture.dart';
import '../gen/gen_test_harness.dart';
import 'tools_test_harness.dart';

void main() {
  setUpAll(loadStudioCaptureFonts);
  setUp(() => debugForceMobileLayout = true);
  tearDown(() => debugForceMobileLayout = null);

  for (final locale in ['zh', 'zh_TW', 'en', 'ja', 'ko']) {
    for (final enhance in [false, true]) {
      testWidgets(
        'device size warning is readable at 360dp $locale enhance=$enhance',
        (t) async {
          t.view.devicePixelRatio = 1;
          t.view.physicalSize = const Size(360, 640);
          addTearDown(t.view.reset);
          final r = ToolsRecorder();
          late String warning;
          await t.pumpWidget(
            genApp(
              Builder(
                builder: (context) {
                  final l = context.l10n;
                  warning = l.localUpscale_onnxSizeLimit;
                  return Center(
                    child: enhance
                        ? ToolsEnhanceSheet(
                            data: ToolsEnhanceData(
                              sourceWidth: 1536,
                              sourceHeight: 1024,
                              scales: const ['1', 'local'],
                              scale: 'local',
                              local: const ToolsLocalUpscale(
                                label: 'AnimeVideo v3',
                                factor: 2,
                              ),
                              blocked: warning,
                            ),
                            actions: r.enhance,
                          )
                        : ToolsUpscaleSheet(
                            data: ToolsUpscaleData(
                              sourceWidth: 1536,
                              sourceHeight: 1024,
                              backends: toolsUpscaleBackends(
                                l,
                                mobile: true,
                                deviceLocal: true,
                                localEnabled: true,
                                cloudCost: 2,
                              ),
                              backend: 'local',
                              method: 'onnx',
                              models: const [
                                ToolsUpscaleModel(
                                  id: 'anime',
                                  label: 'AnimeVideo v3',
                                  state: ToolsModelState.ready,
                                ),
                              ],
                              model: 'anime',
                              scale: 2,
                              outWidth: 3072,
                              outHeight: 2048,
                              canManageModels: false,
                              blocked: warning,
                            ),
                            actions: r.upscale,
                          ),
                  );
                },
              ),
              locale: locale,
            ),
          );
          await t.pumpAndSettle();
          expect(find.text(warning), findsOneWidget);
          final text = t.widget<Text>(find.text(warning));
          expect(text.maxLines, isNull);
          expect(text.overflow, isNot(TextOverflow.ellipsis));
          expect(find.byKey(const Key('tools-upscale-manage')), findsNothing);
          await t.tap(
            find.byKey(
              Key(enhance ? 'tools-enhance-run' : 'tools-upscale-run'),
            ),
          );
          await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await t.sendKeyEvent(LogicalKeyboardKey.enter);
          await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          expect(r.calls, isEmpty);
          await captureUiuxRegion(
            t,
            find.byKey(const Key('gen-capture')),
            'device-upscale-$locale-$enhance',
            const Rect.fromLTWH(0, 0, 360, 640),
          );
          if (!enhance) {
            await t.tap(find.byKey(const Key('tools-backend-novelai')));
            expect(r.calls, ['onBackend(novelai)']);
          } else {
            await t.tap(find.byKey(const Key('tools-scale-1')));
            expect(r.calls, ['onScale(1)']);
          }
          expect(t.takeException(), isNull, reason: uiuxOverflowDetails(t));
        },
      );
    }
  }
}
