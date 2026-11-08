import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/wiring/tools_generation_wiring.dart';

/// Android 没有随包本地超分引擎：放大面板不出现「本地」卡片，只留云端。
void main() {
  late AppLocalizations l;
  setUpAll(() async {
    l = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  test('upgrade sheet on Android only offers the cloud backend', () {
    final backends = toolsUpscaleBackends(
      l,
      mobile: true,
      localEnabled: true,
      cloudCost: 30,
    );
    expect(backends.map((b) => b.id), ['novelai']);
    expect(backends.single.cost, 30);
  });

  test('desktop keeps both local and cloud backends', () {
    final backends = toolsUpscaleBackends(
      l,
      mobile: false,
      localEnabled: true,
      cloudCost: 30,
    );
    expect(backends.map((b) => b.id), ['local', 'novelai']);
    expect(backends.first.enabled, isTrue);
  });

  test('unknown cloud cost hides the price instead of the card', () {
    final backends = toolsUpscaleBackends(
      l,
      mobile: true,
      localEnabled: false,
      cloudCost: null,
    );
    expect(backends.single.id, 'novelai');
    expect(backends.single.cost, isNull);
  });
}
