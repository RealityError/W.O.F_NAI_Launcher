import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../core/utils/pica_lanczos_resizer.dart';
import '../../core/utils/desktop_platform.dart';
import '../models/upscale/local_upscale_models.dart';
import 'local_upscale_model_manager.dart';
import 'advanced_upscale_component_manager.dart';
import 'onnx_upscale_engine.dart';
import 'owned_upscale_process.dart';

typedef UpscaleProcessStarter = Future<Process> Function(String, List<String>);

/// One short-lived native worker per job. No remote generation or ComfyUI.
class LocalUpscaleService {
  static const maxNativeOutputPixels = 64000000;
  LocalUpscaleService(
    this.models, {
    UpscaleProcessStarter? startProcess,
    this.timeout = const Duration(minutes: 10),
    bool? supportedPlatform,
    this.advanced,
    this.beforeInference,
    this.afterInference,
    this.onnx,
  }) : _startProcess =
           startProcess ?? ((exe, args) => Process.start(exe, args)),
       _supportedPlatform =
           supportedPlatform ??
           (supportsLocalUpscale || supportsOnnxUpscale);

  final LocalUpscaleModelManager models;
  final AdvancedUpscaleComponentManager? advanced;
  final OnnxUpscaleEngine? onnx;
  final Future<void> Function()? beforeInference, afterInference;
  final UpscaleProcessStarter _startProcess;
  final bool _supportedPlatform;
  final Duration timeout;
  bool _running = false;
  bool get isRunning => _running;

  Future<LocalUpscaleResult> upscale(
    Uint8List source, {
    required String modelId,
    required double scale,
    required LocalUpscaleCancellation cancellation,
    Seedvr2Options seedvr2Options = const Seedvr2Options(),
    void Function(LocalUpscaleProgress)? onProgress,
  }) async {
    if (!_supportedPlatform) {
      throw const LocalUpscaleException(LocalUpscaleError.unsupportedPlatform);
    }
    if (_running) throw const LocalUpscaleException(LocalUpscaleError.busy);
    if (!scale.isFinite || scale < 1 || scale > 4) {
      throw const LocalUpscaleException(LocalUpscaleError.sizeLimit);
    }
    cancellation.check();
    // 桌面存档里的模型 id 在 Android 上回退到随包 ONNX 模型，其他调用方
    // （面板、自动增强、工具任务）不需要各自再判断平台。
    final resolvedModelId = effectiveLocalUpscaleModel(modelId);
    models.claimInference(resolvedModelId);
    try {
      advanced?.claimInference();
    } catch (_) {
      models.releaseInference();
      rethrow;
    }
    _running = true;
    Directory? job;
    void progress(LocalUpscalePhase phase, [double? fraction]) {
      if (!cancellation.isCancelled) {
        onProgress?.call(LocalUpscaleProgress(phase, fraction));
      }
    }

    try {
      await beforeInference?.call();
      progress(LocalUpscalePhase.preparing);
      final optional = advancedUpscaleCatalog
          .where((m) => m.id == resolvedModelId)
          .firstOrNull;
      final onnxModel = onnxUpscaleCatalog
          .where((m) => m.id == resolvedModelId)
          .firstOrNull;
      if (optional != null &&
          Platform.isMacOS &&
          models.bundledExecutable != null) {
        throw const LocalUpscaleException(
          LocalUpscaleError.unsupportedPlatform,
        );
      }
      if (onnxModel != null && onnx == null) {
        throw const LocalUpscaleException(
          LocalUpscaleError.unsupportedPlatform,
        );
      }
      final (executable, modelPath, model) = onnxModel != null
          ? ('', '', onnxModel)
          : optional == null
          ? await models.resolve(resolvedModelId)
          : ('', '', optional);
      if (onnxModel == null) {
        await models.initialize();
        cancellation.check();
        // The pinned native engine builds model paths into a 256-character buffer.
        final enginePath = modelPath + model.engineName;
        if ((Platform.isWindows
                    ? enginePath.length
                    : utf8.encode(enginePath).length) +
                12 >
            245) {
          throw const LocalUpscaleException(LocalUpscaleError.modelMissing);
        }
      }
      final nativeScale = onnxModel != null
          ? OnnxUpscaleEngine.nativeScale
          : model.inferenceScale(scale);
      final maxNativePixels = onnxModel != null
          ? onnxUpscaleMaxInputPixels * nativeScale * nativeScale
          : LocalUpscaleService.maxNativeOutputPixels;
      final frozen = Uint8List.fromList(source);
      final prepared = await _imageWorker({
        'source': frozen,
        'scale': scale,
        'nativeScale': nativeScale,
        'advanced': optional != null,
        'maxPixels': maxNativePixels,
      }, cancellation);
      final width = prepared['width'] as int;
      final height = prepared['height'] as int;
      final targetWidth = (width * scale).round();
      final targetHeight = (height * scale).round();
      final Uint8List upscaledBytes;
      if (onnxModel != null) {
        progress(LocalUpscalePhase.inference);
        upscaledBytes = await onnx!.upscale(
          prepared['bytes'] as Uint8List,
          cancellation: cancellation,
          onProgress: (fraction) =>
              progress(LocalUpscalePhase.inference, fraction),
        );
        cancellation.check();
      } else {
        job = Directory(p.join(models.directory.path, 'jobs', const Uuid().v4()));
        await job.create(recursive: true);
        final input = File(p.join(job.path, 'input.png'));
        final output = File(p.join(job.path, 'output.png'));
        await input.writeAsBytes(prepared['bytes'] as Uint8List, flush: true);
        cancellation.check();
        progress(LocalUpscalePhase.inference);
        if (optional != null) {
        if (advanced == null) {
          throw const LocalUpscaleException(LocalUpscaleError.modelMissing);
        }
        final spec = await advanced!.command(
          resolvedModelId,
          input.path,
          output.path,
          targetWidth,
          targetHeight,
          cancellation,
          seedvr2Options: seedvr2Options,
        );
        final result = await runOwnedUpscaleProcess(
          host: spec.host,
          executable: spec.executable,
          arguments: spec.arguments,
          cancellation: cancellation,
          startProcess: advanced!.startProcess,
          environment: {
            if (model.method == LocalUpscaleMethod.seedvr2)
              ...AdvancedUpscaleComponentManager.seedRuntimeEnvironment,
            'PYTHONIOENCODING': 'utf-8',
            'HF_HUB_OFFLINE': '1',
            'TRANSFORMERS_OFFLINE': '1',
            'HF_HUB_DISABLE_TELEMETRY': '1',
          },
          onLine: (line) {
            try {
              final item = jsonDecode(line) as Map<String, dynamic>;
              final phase = LocalUpscalePhase.values.byName(
                item['phase'] as String,
              );
              final total = item['total'] as num?;
              final current = item['current'] as num?;
              progress(
                phase,
                total != null && current != null && total > 0
                    ? (current / total).clamp(0, 1)
                    : null,
              );
            } catch (_) {
              /* Only structured native progress is displayed. */
            }
          },
        );
        if (result.exitCode != 0 || !await output.exists()) {
          throw LocalUpscaleException(
            result.exitCode == 12
                ? LocalUpscaleError.noCuda
                : result.exitCode == 13
                ? LocalUpscaleError.noInt8
                : result.diagnostics.contains('rtx_unavailable')
                ? LocalUpscaleError.noRtx
                : model.method == LocalUpscaleMethod.seedvr2 &&
                      RegExp(
                        r'CUDA out of memory|cudaErrorMemoryAllocation|"error"\s*:\s*"OutOfMemoryError"',
                        caseSensitive: false,
                      ).hasMatch(result.diagnostics)
                ? LocalUpscaleError.outOfMemory
                : LocalUpscaleError.processFailed,
            details: AdvancedUpscaleComponentManager.safeDiagnostics(
              'exit ${result.exitCode}\n${result.diagnostics}',
            ),
          );
        }
      } else {
        Process process;
        try {
          process = await _startProcess(executable, [
            '-i',
            input.path,
            '-o',
            output.path,
            '-m',
            modelPath,
            '-n',
            model.engineName,
            '-s',
            '$nativeScale',
            '-t',
            '128',
            '-j',
            '1:1:1',
          ]);
        } on ProcessException {
          throw const LocalUpscaleException(LocalUpscaleError.engineMissing);
        }
        var timedOut = false;
        var diagnostics = '';
        final stop = cancellation.listen(() => process.kill());
        final timer = Timer(timeout, () {
          timedOut = true;
          process.kill();
        });
        final stderrDone = process.stderr
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter())
            .listen((line) {
              diagnostics = '$diagnostics\n$line';
              if (diagnostics.length > 8192) {
                diagnostics = diagnostics.substring(diagnostics.length - 8192);
              }
              final match = RegExp(
                r'^\s*([0-9]+(?:\.[0-9]+)?)%\s*$',
              ).firstMatch(line);
              if (match != null) {
                progress(
                  LocalUpscalePhase.inference,
                  (double.parse(match.group(1)!) / 100).clamp(0, 1),
                );
              }
            })
            .asFuture<void>();
        final stdoutDone = process.stdout.drain<void>();
        int exit;
        try {
          // Do not release the model/GPU lock before the child has really exited.
          exit = await process.exitCode;
          await Future.wait([stderrDone, stdoutDone]);
        } finally {
          timer.cancel();
          stop();
        }
        cancellation.check();
        if (timedOut) {
          throw const LocalUpscaleException(LocalUpscaleError.timeout);
        }
        if (exit != 0 || !await output.exists()) {
          final vulkanFailure = RegExp(
            r'vkCreate|no.*vulkan|invalid gpu|no.*gpu|vkEnumerate',
            caseSensitive: false,
          ).hasMatch(diagnostics);
          throw LocalUpscaleException(
            vulkanFailure
                ? LocalUpscaleError.noVulkan
                : LocalUpscaleError.processFailed,
          );
        }
        }
        cancellation.check();
        upscaledBytes = await output.readAsBytes();
      }
      progress(LocalUpscalePhase.resizing);
      final result = await _imageWorker({
        'source': frozen,
        'output': upscaledBytes,
        'width': width,
        'height': height,
        'nativeScale': nativeScale,
        'advanced': optional != null,
        'padding': optional?.method == LocalUpscaleMethod.seedvr2 ? 64 : 0,
        'targetWidth': targetWidth,
        'targetHeight': targetHeight,
      }, cancellation);
      cancellation.check();
      progress(LocalUpscalePhase.complete, 1);
      return LocalUpscaleResult(
        result['bytes'] as Uint8List,
        targetWidth,
        targetHeight,
      );
    } on LocalUpscaleException {
      rethrow;
    } catch (_) {
      cancellation.check();
      throw const LocalUpscaleException(LocalUpscaleError.processFailed);
    } finally {
      try {
        if (job != null && await job.exists()) {
          if (!p.isWithin(
            await models.directory.resolveSymbolicLinks(),
            await job.resolveSymbolicLinks(),
          )) {
            throw const LocalUpscaleException(LocalUpscaleError.processFailed);
          }
          await job.delete(recursive: true);
        }
      } finally {
        _running = false;
        models.releaseInference();
        advanced?.releaseInference();
        try {
          await afterInference?.call();
        } catch (_) {
          // A retrieval restart must never discard a completed upscale.
        }
      }
    }
  }
}

Future<Map<String, Object>> _imageWorker(
  Map<String, Object> input,
  LocalUpscaleCancellation cancellation,
) async {
  cancellation.check();
  final messages = ReceivePort();
  final errors = ReceivePort();
  final complete = Completer<Map<String, Object>>();
  final subscription = messages.listen((message) {
    if (complete.isCompleted) return;
    final result = message as Map;
    if (result['error'] != null) {
      complete.completeError(
        LocalUpscaleException(
          LocalUpscaleError.values.byName(result['error'] as String),
        ),
      );
    } else {
      complete.complete(result.cast<String, Object>());
    }
  });
  final errorSubscription = errors.listen((_) {
    if (!complete.isCompleted) {
      complete.completeError(
        const LocalUpscaleException(LocalUpscaleError.invalidImage),
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
  // Attach an error handler immediately, including cancellation while spawning.
  final future = complete.future;
  unawaited(future.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
  try {
    worker = await Isolate.spawn(_imageWorkerEntry, (
      messages.sendPort,
      input,
    ), onError: errors.sendPort);
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

void _imageWorkerEntry((SendPort, Map<String, Object>) args) {
  try {
    final input = args.$2;
    final bytes = input['source'] as Uint8List;
    if (bytes.length > 64 * 1024 * 1024) {
      throw const LocalUpscaleException(LocalUpscaleError.sizeLimit);
    }
    final decoder = img.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (info == null) {
      throw const LocalUpscaleException(LocalUpscaleError.invalidImage);
    }
    final nativeScale = input['nativeScale'] as int;
    final advanced = input['advanced'] == true;
    final maxPixels =
        input['maxPixels'] as int? ?? LocalUpscaleService.maxNativeOutputPixels;
    if (info.width <= 0 ||
        info.height <= 0 ||
        info.width * info.height * nativeScale * nativeScale > maxPixels) {
      throw const LocalUpscaleException(LocalUpscaleError.sizeLimit);
    }
    final original = decoder!.decodeFrame(0);
    if (original == null) {
      throw const LocalUpscaleException(LocalUpscaleError.invalidImage);
    }
    if (input['output'] == null) {
      args.$1.send({
        'width': original.width,
        'height': original.height,
        'bytes': Uint8List.fromList(img.encodePng(original)),
      });
      return;
    }
    final encoded = input['output'] as Uint8List;
    final outputInfo = img.PngDecoder().startDecode(encoded);
    final targetWidth = input['targetWidth'] as int;
    final targetHeight = input['targetHeight'] as int;
    final padding = input['padding'] as int? ?? 0;
    if (outputInfo == null ||
        outputInfo.width * outputInfo.height > maxPixels ||
        (advanced &&
            ((outputInfo.width - targetWidth).abs() > padding ||
                (outputInfo.height - targetHeight).abs() > padding))) {
      throw const LocalUpscaleException(LocalUpscaleError.processFailed);
    }
    final scaled = img.decodePng(encoded);
    if (scaled == null ||
        (!advanced &&
            (scaled.width != original.width * nativeScale ||
                scaled.height != original.height * nativeScale))) {
      throw const LocalUpscaleException(LocalUpscaleError.processFailed);
    }
    final width = input['targetWidth'] as int;
    final height = input['targetHeight'] as int;
    var result = PicaLanczosResizer.resizeImage(
      scaled,
      width: width,
      height: height,
    );
    if (original.hasAlpha) {
      result = result.convert(numChannels: 4);
      final alpha = PicaLanczosResizer.resizeImage(
        original,
        width: width,
        height: height,
      );
      for (final pixel in result) {
        final a = alpha.getPixel(pixel.x, pixel.y).a;
        pixel.a = a;
        if (a == 0) pixel.setRgba(0, 0, 0, 0);
      }
    }
    args.$1.send({'bytes': Uint8List.fromList(img.encodePng(result))});
  } on LocalUpscaleException catch (error) {
    args.$1.send({'error': error.code.name});
  } catch (_) {
    args.$1.send({'error': LocalUpscaleError.invalidImage.name});
  }
}
