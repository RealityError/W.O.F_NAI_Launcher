import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
// ignore: implementation_imports
import 'package:onnxruntime/src/bindings/onnxruntime_bindings_generated.dart'
    as bg;

import '../models/upscale/local_upscale_models.dart';

/// 设备端 Real-ESRGAN（ONNX Runtime）推理引擎。
///
/// 桌面端用随包的 ncnn Vulkan 可执行文件；Android 没有可执行位，改为在独立
/// isolate 里用 ONNX Runtime 跑同一个 Real-ESRGAN 模型：
///
/// * 模型是 fixed-shape 的 `animevideov3`（256×256 输入，4 倍输出），
///   所以按 256 分块、块间重叠 32 像素，块内用边缘复制补齐；
/// * 每块的输出只写它对应的「中缝」区域，块与块之间的重叠各取一半，
///   这样既不会出现接缝，也不需要额外保存整张 4 倍图的浮点缓冲；
/// * 原始 alpha 不参与推理，由调用方在缩放后按桌面端同样的方式重采样。
class OnnxUpscaleEngine {
  OnnxUpscaleEngine({AssetBundle? bundle, this.modelAsset = defaultModelAsset})
    : _bundle = bundle;

  /// 随包模型；来源与许可记录在 `assets/local_upscale/onnx/README.md`。
  static const String defaultModelAsset =
      'assets/local_upscale/onnx/animevideov3-256.onnx';

  static const int nativeScale = 4;
  static const int tileSize = 256;
  static const int tileStride = tileSize - overlap;
  static const int overlap = 32;

  /// 4 倍中间图的上限。1.2M 输入像素 → 19.2M 输出像素，大约 58MB RGB。
  static const int maxInputPixels = onnxUpscaleMaxInputPixels;

  final String modelAsset;
  final AssetBundle? _bundle;

  bool get isSupported => true;

  /// 把 [sourcePng] 按 [nativeScale] 放大，返回同样尺寸的 PNG 字节。
  Future<Uint8List> upscale(
    Uint8List sourcePng, {
    required LocalUpscaleCancellation cancellation,
    void Function(double fraction)? onProgress,
  }) async {
    cancellation.check();
    final data = await (_bundle ?? rootBundle).load(modelAsset);
    final modelBytes = Uint8List.sublistView(data);
    final messages = ReceivePort();
    final errors = ReceivePort();
    final complete = Completer<Uint8List>();
    final subscription = messages.listen((message) {
      if (complete.isCompleted) return;
      if (message is double) {
        onProgress?.call(message.clamp(0, 1));
        return;
      }
      final result = message as Map;
      final error = result['error'];
      if (error != null) {
        final details = result['details'];
        if (details != null) {
          debugPrint('ONNX upscale worker failed: $details');
        }
        complete.completeError(
          LocalUpscaleException(LocalUpscaleError.values.byName(error as String)),
        );
      } else {
        final transferred = result['bytes'] as TransferableTypedData;
        complete.complete(transferred.materialize().asUint8List());
      }
    });
    final errorSubscription = errors.listen((message) {
      debugPrint('ONNX upscale isolate error: $message');
      if (!complete.isCompleted) {
        complete.completeError(
          const LocalUpscaleException(LocalUpscaleError.processFailed),
        );
      }
    });
    Isolate? worker;
    final stop = cancellation.listen(() {
      worker?.kill(priority: Isolate.immediate);
      if (!complete.isCompleted) {
        complete.completeError(
          const LocalUpscaleException(LocalUpscaleError.cancelled),
        );
      }
    });
    final future = complete.future;
    unawaited(future.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    try {
      worker = await Isolate.spawn(
        _onnxWorkerEntry,
        (
          messages.sendPort,
          modelBytes,
          sourcePng,
          tileSize,
          tileStride,
          maxInputPixels,
        ),
        onError: errors.sendPort,
        debugName: 'onnx-upscale',
      );
      if (cancellation.isCancelled) worker.kill(priority: Isolate.immediate);
      return await future;
    } finally {
      stop();
      worker?.kill(priority: Isolate.immediate);
      await subscription.cancel();
      await errorSubscription.cancel();
      messages.close();
      errors.close();
    }
  }
}

/// 单个 256 块的分区：`[start, end)` 是这块负责写入的输入像素区间，
/// [origin] 是块在输入图上的起点（用于换算 4 倍输出坐标）。
class OnnxTileSpan {
  const OnnxTileSpan({
    required this.start,
    required this.end,
    required this.origin,
  });

  final int start;
  final int end;
  final int origin;

  int get length => end - start;
}

/// 计算一维分块方案；纯函数便于单测覆盖边界尺寸。
@visibleForTesting
List<OnnxTileSpan> planOnnxTiles(
  int length, {
  int tile = OnnxUpscaleEngine.tileSize,
  int stride = OnnxUpscaleEngine.tileStride,
}) {
  if (length <= 0) return const [];
  final origins = <int>[];
  for (var x = 0; x + tile < length; x += stride) {
    origins.add(x);
  }
  final last = length > tile ? length - tile : 0;
  if (origins.isEmpty || last > origins.last) origins.add(last);
  return [
    for (var i = 0; i < origins.length; i++)
      OnnxTileSpan(
        start: i == 0
            ? 0
            : (origins[i - 1] + tile + origins[i]) ~/ 2,
        end: i == origins.length - 1
            ? length
            : (origins[i] + tile + origins[i + 1]) ~/ 2,
        origin: origins[i],
      ),
  ];
}

/// 根据 [planOnnxTiles] 生成二维分块计划，供 worker 与单测共用。
@visibleForTesting
List<(OnnxTileSpan, OnnxTileSpan)> planOnnxTiles2d(
  int width,
  int height, {
  int tile = OnnxUpscaleEngine.tileSize,
  int stride = OnnxUpscaleEngine.tileStride,
}) => [
  for (final y in planOnnxTiles(height, tile: tile, stride: stride))
    for (final x in planOnnxTiles(width, tile: tile, stride: stride))
      (x, y),
];

void _onnxWorkerEntry(
  (SendPort, Uint8List, Uint8List, int, int, int) args,
) {
  final progress = args.$1;
  final modelBytes = args.$2;
  final sourcePng = args.$3;
  final tile = args.$4;
  final stride = args.$5;
  final maxPixels = args.$6;
  try {
    final decoded = img.decodePng(sourcePng);
    if (decoded == null) {
      throw const LocalUpscaleException(LocalUpscaleError.invalidImage);
    }
    final width = decoded.width;
    final height = decoded.height;
    if (width <= 0 ||
        height <= 0 ||
        width * height > maxPixels) {
      throw const LocalUpscaleException(LocalUpscaleError.sizeLimit);
    }
    final source = decoded.getBytes(order: img.ChannelOrder.rgb);
    OrtEnv.instance.init();
    final options = OrtSessionOptions()
      ..setIntraOpNumThreads(
        (Platform.numberOfProcessors.clamp(2, 6)) & 0x7fffffff,
      )
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
    final session = OrtSession.fromBuffer(modelBytes, options);
    final inputName = session.inputNames.first;
    final tileCount = tile * OnnxUpscaleEngine.nativeScale;
    final plane = tileCount * tileCount;
    final outputWidth = width * OnnxUpscaleEngine.nativeScale;
    final outputHeight = height * OnnxUpscaleEngine.nativeScale;
    final destination = Uint8List(outputWidth * outputHeight * 3);
    final plans = planOnnxTiles2d(width, height, tile: tile, stride: stride);
    final inputPlane = tile * tile;
    final pixels = Float32List(3 * inputPlane);
    final outputBytes = 3 * plane;
    final readTensorData = OrtEnv.instance.ortApiPtr.ref.GetTensorMutableData
        .asFunction<
          bg.OrtStatusPtr Function(
            ffi.Pointer<bg.OrtValue>,
            ffi.Pointer<ffi.Pointer<ffi.Void>>,
          )
        >();
    final runOptions = OrtRunOptions();
    for (var index = 0; index < plans.length; index++) {
      final (xSpan, ySpan) = plans[index];
      for (var y = 0; y < tile; y++) {
        final sourceY = (ySpan.origin + y).clamp(0, height - 1);
        final sourceRow = sourceY * width * 3;
        final tileRow = y * tile;
        for (var x = 0; x < tile; x++) {
          final sourceX = (xSpan.origin + x).clamp(0, width - 1);
          final sourceIndex = sourceRow + sourceX * 3;
          final target = tileRow + x;
          pixels[target] = source[sourceIndex] / 255.0;
          pixels[inputPlane + target] = source[sourceIndex + 1] / 255.0;
          pixels[2 * inputPlane + target] = source[sourceIndex + 2] / 255.0;
        }
      }
      final input = OrtValueTensor.createTensorWithDataList(pixels, [
        1,
        3,
        tile,
        tile,
      ]);
      final outputs = session.run(runOptions, <String, OrtValue>{
        inputName: input,
      });
      try {
        if (outputs.isEmpty || outputs.first == null) {
          throw const LocalUpscaleException(LocalUpscaleError.processFailed);
        }
        final tensor = outputs.first! as OrtValueTensor;
        final outPtr = calloc<ffi.Pointer<ffi.Void>>();
        try {
          final status = readTensorData(tensor.ptr, outPtr);
          OrtStatus.checkOrtStatus(status);
          if (outPtr.value == ffi.nullptr) {
            throw const LocalUpscaleException(LocalUpscaleError.processFailed);
          }
          final values = outPtr.value.cast<ffi.Float>().asTypedList(
            outputBytes,
          );
          const scale = OnnxUpscaleEngine.nativeScale;
          final writeWidth = xSpan.length * scale;
          final writeHeight = ySpan.length * scale;
          for (var row = 0; row < writeHeight; row++) {
            final sourceRowBase =
                ((ySpan.start - ySpan.origin) * scale + row) * tileCount;
            final destinationRowBase =
                ((ySpan.start * scale + row) * outputWidth +
                    xSpan.start * scale) *
                3;
            for (var column = 0; column < writeWidth; column++) {
              final sourceIndex =
                  sourceRowBase + (xSpan.start - xSpan.origin) * scale + column;
              final destinationIndex = destinationRowBase + column * 3;
              destination[destinationIndex] = _channel(values[sourceIndex]);
              destination[destinationIndex + 1] = _channel(
                values[plane + sourceIndex],
              );
              destination[destinationIndex + 2] = _channel(
                values[2 * plane + sourceIndex],
              );
            }
          }
        } finally {
          calloc.free(outPtr);
        }
      } finally {
        input.release();
        for (final value in outputs) {
          value?.release();
        }
      }
      progress.send((index + 1) / plans.length);
    }
    session.release();
    final encoded = img.Image.fromBytes(
      width: outputWidth,
      height: outputHeight,
      bytes: destination.buffer,
      order: img.ChannelOrder.rgb,
    );
    progress.send({
      'bytes': TransferableTypedData.fromList([
        Uint8List.fromList(img.encodePng(encoded)),
      ]),
    });
  } on LocalUpscaleException catch (error) {
    progress.send({'error': error.code.name});
  } on Object catch (error) {
    progress.send({
      'error': LocalUpscaleError.processFailed.name,
      'details': '$error',
    });
  }
}

int _channel(double value) {
  if (value <= 0) return 0;
  if (value >= 1) return 255;
  final scaled = (value * 255).round();
  return scaled < 0 ? 0 : (scaled > 255 ? 255 : scaled);
}
