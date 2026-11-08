import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_logger.dart';
import '../providers/image_generation_provider.dart';

/// 调试模式开关：`--dart-define=NAI_DEMO=1`（或 `=true`）的构建才启用。
///
/// 没有 NovelAI 订阅 / 额度时，启动后往生成页注入一张本地示例图，让画布、
/// 最近生成、查看器、导演工具都能照常点开讨论 UI；走的是和真实生成结果相同的
/// 状态结构，但不会请求接口、不会扣费。发布构建默认关闭，也不影响桌面端。
const String _demoFlag = String.fromEnvironment('NAI_DEMO');
const bool kDemoFixtures = bool.fromEnvironment('NAI_DEMO') || _demoFlag == '1';

/// 示例图：320×468 的竖图，够铺满画布与导演工具预览。
const String kDemoImageAsset = 'assets/images/demo-sample.jpg';

/// 启动后调用一次。没开调试模式时直接返回。
Future<void> seedDemoFixtures(ProviderContainer container) async {
  if (!kDemoFixtures) return;
  try {
    final data = await rootBundle.load(kDemoImageAsset);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final image = GeneratedImage.create(bytes, width: 832, height: 1216);
    container.read(imageGenerationNotifierProvider.notifier).adoptDemoImages([
      image,
    ]);
    AppLogger.i('Demo fixture image injected', 'DemoFixtures');
  } catch (error, stackTrace) {
    AppLogger.w('Demo fixture seeding failed: $error', 'DemoFixtures');
    AppLogger.d('Demo fixture stack: $stackTrace', 'DemoFixtures');
  }
}
