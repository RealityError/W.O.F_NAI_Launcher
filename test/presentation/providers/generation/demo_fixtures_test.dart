import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/providers/image_generation_provider.dart';

void main() {
  test('adoptDemoImages 让示例图同时进入画布、最近生成与目录', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final image = GeneratedImage.create(
      Uint8List.fromList([1, 2, 3, 4]),
      width: 320,
      height: 468,
    );
    container.read(imageGenerationNotifierProvider.notifier).adoptDemoImages([
      image,
    ]);

    final state = container.read(imageGenerationNotifierProvider);
    expect(state.currentImages.single.id, image.id);
    expect(state.history.single.id, image.id);
    expect(state.displayImages.single.id, image.id);
    expect(state.mergedPanelImages.single.id, image.id);
    expect(state.isGenerating, isFalse);
    expect(state.generationRunId, isNotNull);
    expect(state.history.single.generationRunId, state.generationRunId);
    expect(state.history.single.batchIndex, 0);
    expect(state.batchWidth, 320);
    expect(state.batchHeight, 468);
  });
}
