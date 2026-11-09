import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:nai_launcher/data/models/upscale/local_upscale_models.dart';
import 'package:nai_launcher/data/services/local_upscale_model_manager.dart';
import 'package:nai_launcher/data/services/local_upscale_service.dart';
import 'package:nai_launcher/data/services/onnx_upscale_engine.dart';

class _FakeOnnxEngine extends OnnxUpscaleEngine {
  Future<Uint8List> Function(Uint8List source)? onUpscale;
  final List<double> reported = <double>[];
  final List<String?> modelAssets = <String?>[];
  int calls = 0;

  @override
  Future<Uint8List> upscale(
    Uint8List sourcePng, {
    String? modelAsset,
    required LocalUpscaleCancellation cancellation,
    void Function(double fraction)? onProgress,
  }) async {
    calls++;
    modelAssets.add(modelAsset);
    cancellation.check();
    final custom = onUpscale;
    if (custom != null) return custom(sourcePng);
    final decoded = img.decodePng(sourcePng);
    if (decoded == null) throw StateError('decode failed');
    onProgress?.call(0.5);
    reported.add(0.5);
    final scaled = img.copyResize(
      decoded,
      width: decoded.width * OnnxUpscaleEngine.nativeScale,
      height: decoded.height * OnnxUpscaleEngine.nativeScale,
      interpolation: img.Interpolation.nearest,
    );
    return Uint8List.fromList(img.encodePng(scaled));
  }
}

Uint8List _source({bool alpha = false, int width = 48, int height = 32}) {
  final image = img.Image(
    width: width,
    height: height,
    numChannels: alpha ? 4 : 3,
  );
  for (final pixel in image) {
    pixel.setRgba(
      pixel.x * 255 ~/ width,
      pixel.y * 255 ~/ height,
      100,
      alpha ? (pixel.x < width ~/ 2 ? 0 : 255) : 255,
    );
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('device ONNX catalog', () {
    test('exposes anime and general models with unique assets', () {
      expect(
        onnxUpscaleCatalog.map((model) => model.id).toSet().length,
        onnxUpscaleCatalog.length,
      );
      for (final model in onnxUpscaleCatalog) {
        expect(model.bundled, isTrue);
        expect(model.installed, isTrue);
        expect(model.method, LocalUpscaleMethod.onnx);
        expect(model.scales, [4]);
        expect(
          onnxUpscaleAssetPath(model),
          'assets/local_upscale/onnx/${model.engineName}.onnx',
        );
      }
      expect(
        onnxUpscaleCatalog.map(onnxUpscaleAssetPath),
        contains('assets/local_upscale/onnx/realesr-general-x4v3.onnx'),
      );
    });

    test('keeps the anime model as the fallback default', () {
      expect(onnxUpscaleCatalog.first.id, 'onnx-anime-videov3');
      expect(onnxUpscaleCatalog.first.engineName, 'animevideov3-256');
    });
  });

  group('planOnnxTiles', () {
    List<OnnxTileSpan> spans(int length) => planOnnxTiles(length);

    void expectPartition(int length) {
      final result = spans(length);
      expect(result, isNotEmpty);
      expect(result.first.start, 0);
      expect(result.last.end, length);
      for (var i = 0; i < result.length; i++) {
        final span = result[i];
        expect(
          span.start,
          lessThan(span.end),
          reason: 'length=$length span $i must be non-empty',
        );
        expect(
          span.start,
          greaterThanOrEqualTo(span.origin),
          reason: 'length=$length span $i starts before its tile',
        );
        expect(
          span.end,
          lessThanOrEqualTo(span.origin + OnnxUpscaleEngine.tileSize),
          reason: 'length=$length span $i ends outside its tile',
        );
        if (i > 0) {
          expect(
            span.start,
            result[i - 1].end,
            reason: 'length=$length spans $i must be contiguous',
          );
        }
      }
    }

    test('covers edge sizes without overlap or gaps', () {
      for (final length in [
        1,
        32,
        100,
        255,
        256,
        257,
        300,
        480,
        512,
        640,
        832,
      ]) {
        expectPartition(length);
      }
    });

    test('single tile when the image fits', () {
      expect(spans(200).single.start, 0);
      expect(spans(200).single.end, 200);
      expect(spans(256).single.origin, 0);
    });

    test('right-aligns the last tile to avoid tiny remainders', () {
      final result = spans(832);
      expect(result.length, 4);
      expect(result.last.origin, 832 - OnnxUpscaleEngine.tileSize);
      expect(result.last.end, 832);
    });

    test('2d plan has one span pair per tile cross product', () {
      expect(planOnnxTiles2d(832, 1216).length, 4 * 6);
      expect(planOnnxTiles2d(100, 120).length, 1);
    });
  });

  group('LocalUpscaleService ONNX backend', () {
    late Directory temporary;
    late LocalUpscaleModelManager manager;
    setUp(() async {
      temporary = await Directory.systemTemp.createTemp('studio-onnx-test-');
      manager = LocalUpscaleModelManager(
        rootDirectory: () async => Directory(p.join(temporary.path, 'runtime')),
      );
    });
    tearDown(() async {
      manager.dispose();
      await temporary.delete(recursive: true);
    });

    LocalUpscaleService build(_FakeOnnxEngine engine) =>
        LocalUpscaleService(manager, supportedPlatform: true, onnx: engine);

    test(
      'runs the ONNX engine and keeps the existing resize pipeline',
      () async {
        final engine = _FakeOnnxEngine();
        final service = build(engine);
        final phases = <LocalUpscalePhase>[];
        final fractions = <double?>[];
        final result = await service.upscale(
          _source(width: 48, height: 32),
          modelId: onnxUpscaleCatalog.first.id,
          scale: 1.5,
          cancellation: LocalUpscaleCancellation(),
          onProgress: (progress) {
            phases.add(progress.phase);
            fractions.add(progress.fraction);
          },
        );
        expect(engine.calls, 1);
        expect(
          engine.modelAssets.single,
          'assets/local_upscale/onnx/animevideov3-256.onnx',
        );
        expect(result.width, (48 * 1.5).round());
        expect(result.height, (32 * 1.5).round());
        final output = img.decodePng(result.bytes);
        expect(output, isNotNull);
        expect(output!.width, result.width);
        expect(output.height, result.height);
        expect(phases.first, LocalUpscalePhase.preparing);
        expect(phases[1], LocalUpscalePhase.inference);
        expect(phases, contains(LocalUpscalePhase.resizing));
        expect(phases.last, LocalUpscalePhase.complete);
        expect(fractions.whereType<double>(), contains(0.5));
      },
    );

    test('uses the selected catalog model asset', () async {
      final engine = _FakeOnnxEngine();
      final service = build(engine);
      final general = onnxUpscaleCatalog.firstWhere(
        (model) => model.id == 'onnx-general-x4v3',
      );
      await service.upscale(
        _source(width: 48, height: 32),
        modelId: general.id,
        scale: 2,
        cancellation: LocalUpscaleCancellation(),
      );
      expect(
        engine.modelAssets.single,
        'assets/local_upscale/onnx/${general.engineName}.onnx',
      );
      expect(general.engineName, 'realesr-general-x4v3');
    });

    test('restores source alpha after the 4x upscale', () async {
      final engine = _FakeOnnxEngine();
      final service = build(engine);
      final result = await service.upscale(
        _source(alpha: true, width: 40, height: 24),
        modelId: onnxUpscaleCatalog.first.id,
        scale: 2,
        cancellation: LocalUpscaleCancellation(),
      );
      final output = img.decodePng(result.bytes)!;
      expect(output.hasAlpha, isTrue);
      expect(output.getPixel(0, 0).a, 0);
      expect(output.getPixel(output.width - 1, 0).a, 255);
    });

    test('rejects images above the ONNX pixel budget', () async {
      final engine = _FakeOnnxEngine();
      final service = build(engine);
      await expectLater(
        service.upscale(
          _source(width: 1200, height: 1100),
          modelId: onnxUpscaleCatalog.first.id,
          scale: 1.5,
          cancellation: LocalUpscaleCancellation(),
        ),
        throwsA(
          isA<LocalUpscaleException>().having(
            (error) => error.code,
            'code',
            LocalUpscaleError.sizeLimit,
          ),
        ),
      );
      expect(engine.calls, 0);
    });

    test(
      'keeps engine errors while the native engine is unavailable',
      () async {
        final service = LocalUpscaleService(manager, supportedPlatform: true);
        await expectLater(
          service.upscale(
            _source(),
            modelId: onnxUpscaleCatalog.first.id,
            scale: 1.5,
            cancellation: LocalUpscaleCancellation(),
          ),
          throwsA(
            isA<LocalUpscaleException>().having(
              (error) => error.code,
              'code',
              LocalUpscaleError.unsupportedPlatform,
            ),
          ),
        );
      },
    );
  });
}
