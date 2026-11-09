import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/wiring/tools_generation_wiring.dart';

/// Android 没有桌面可执行文件：默认仍只出现云端卡片；带随包 ONNX 模型的
/// Android 版本（deviceLocal）才把「本地」卡片加回来。
void main() {
  late AppLocalizations l;
  setUpAll(() async {
    l = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  test('mobile without device model only offers the cloud backend', () {
    final backends = toolsUpscaleBackends(
      l,
      mobile: true,
      localEnabled: true,
      cloudCost: 30,
    );
    expect(backends.map((b) => b.id), ['novelai']);
    expect(backends.single.cost, 30);
  });

  test('mobile with bundled ONNX model offers local and cloud', () {
    final backends = toolsUpscaleBackends(
      l,
      mobile: true,
      deviceLocal: true,
      localEnabled: true,
      cloudCost: 30,
    );
    expect(backends.map((b) => b.id), ['local', 'novelai']);
    expect(backends.first.enabled, isTrue);
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
