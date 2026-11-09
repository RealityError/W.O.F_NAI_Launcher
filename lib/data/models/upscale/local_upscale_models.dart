import 'dart:typed_data';

import '../../../core/utils/desktop_platform.dart';

enum LocalUpscaleError {
  unsupportedPlatform,
  engineMissing,
  integrity,
  modelMissing,
  invalidModel,
  invalidImage,
  sizeLimit,
  noVulkan,
  noCuda,
  noInt8,
  noRtx,
  outOfMemory,
  processFailed,
  modelOperationFailed,
  timeout,
  busy,
  cancelled,
}

class LocalUpscaleException implements Exception {
  const LocalUpscaleException(this.code, {this.details});
  final LocalUpscaleError code;
  final String? details;
  @override
  String toString() => 'LocalUpscaleException(${code.name})';
}

enum LocalUpscalePhase {
  preparing,
  encoding,
  inference,
  decoding,
  resizing,
  complete,
}

enum LocalUpscaleMethod { standard, seedvr2, rtx, onnx }

class LocalUpscaleProgress {
  const LocalUpscaleProgress(this.phase, [this.fraction]);
  final LocalUpscalePhase phase;
  final double? fraction;
}

class LocalUpscaleModel {
  const LocalUpscaleModel({
    required this.id,
    required this.name,
    required this.engineName,
    required this.scales,
    this.installed = false,
    this.bundled = false,
    this.custom = false,
    this.method = LocalUpscaleMethod.standard,
    this.modelBytes = 0,
    this.diskBytes = 0,
  });
  final String id;
  final String name;
  final String engineName;
  final List<int> scales;
  final bool installed;
  final bool bundled;
  final bool custom;
  final LocalUpscaleMethod method;

  /// Model files from the pinned manifest (or the imported pair), independent
  /// of installation state. Shared runtimes and download archives are excluded.
  final int modelBytes;
  final int diskBytes;
  bool get isSeedvr2Seven => const {
    'seedvr2-7b',
    'seedvr2-7b-sharp',
    'seedvr2-7b-int8',
    'seedvr2-7b-sharp-int8',
  }.contains(id);
  bool get isSeedvr2Int8 =>
      method == LocalUpscaleMethod.seedvr2 && id.endsWith('-int8');
  bool get isSeedvr2Sharp =>
      id == 'seedvr2-7b-sharp' || id == 'seedvr2-7b-sharp-int8';
  int inferenceScale(double requested) => scales.firstWhere(
    (scale) => scale >= requested,
    orElse: () => scales.last,
  );
  LocalUpscaleModel withInstalled(
    bool value, {
    int? modelBytes,
    int? diskBytes,
  }) => LocalUpscaleModel(
    id: id,
    name: name,
    engineName: engineName,
    scales: scales,
    installed: value,
    bundled: bundled,
    custom: custom,
    method: method,
    modelBytes: modelBytes ?? this.modelBytes,
    diskBytes: diskBytes ?? this.diskBytes,
  );
}

const localUpscaleDefaultModel = 'anime';

/// 设备端 ONNX 模型。固定 256×256 输入、4 倍输出，随包分发（无需下载）。
///
/// 与桌面端 `anime-fast` 同属 `realesr-animevideov3` 模型族，只换了推理后端。
const onnxUpscaleCatalog = [
  LocalUpscaleModel(
    id: 'onnx-anime-videov3',
    name: 'RealESR AnimeVideo v3',
    engineName: 'animevideov3-256',
    scales: [4],
    bundled: true,
    installed: true,
    method: LocalUpscaleMethod.onnx,
    modelBytes: 2494775,
  ),
];

/// 设备端 ONNX 推理单个 4 倍中间图允许的最大输入像素数（约 19.2MP 输出）。
const int onnxUpscaleMaxInputPixels = 1200000;

bool isOnnxUpscaleModel(String id) =>
    onnxUpscaleCatalog.any((model) => model.id == id);

/// 当前平台实际可用的本地模型 id。
///
/// 桌面端工作流默认 `anime`；Android 只随包 ONNX 模型，沿用桌面存档里的
/// 模型 id 会直接命中「模型缺失」，因此统一在这里做一次回退。
String effectiveLocalUpscaleModel(String id) =>
    supportsOnnxUpscale && !isOnnxUpscaleModel(id)
    ? onnxUpscaleCatalog.first.id
    : id;

/// 本地放大的 4 倍中间图上限：桌面沿用 64MP，Android 按 ONNX 预算收紧。
int get localUpscaleMaxNativePixels => supportsOnnxUpscale
    ? onnxUpscaleMaxInputPixels * 16
    : 64000000;

const localUpscaleCatalog = [
  LocalUpscaleModel(
    id: 'anime',
    name: 'Real-ESRGAN x4plus Anime',
    engineName: 'realesrgan-x4plus-anime',
    scales: [4],
    bundled: true,
  ),
  LocalUpscaleModel(
    id: 'anime-fast',
    name: 'RealESR AnimeVideo v3',
    engineName: 'realesr-animevideov3',
    scales: [2, 3, 4],
  ),
  LocalUpscaleModel(
    id: 'general',
    name: 'Real-ESRGAN x4plus',
    engineName: 'realesrgan-x4plus',
    scales: [4],
  ),
];

const advancedUpscaleCatalog = [
  LocalUpscaleModel(
    id: 'seedvr2-3b',
    name: 'SeedVR2 3B FP8',
    engineName: 'seedvr2',
    scales: [1, 2, 3, 4],
    method: LocalUpscaleMethod.seedvr2,
  ),
  LocalUpscaleModel(
    id: 'seedvr2-7b',
    name: 'SeedVR2 7B FP8',
    engineName: 'seedvr2',
    scales: [1, 2, 3, 4],
    method: LocalUpscaleMethod.seedvr2,
  ),
  LocalUpscaleModel(
    id: 'seedvr2-7b-sharp',
    name: 'SeedVR2 7B Sharp FP8',
    engineName: 'seedvr2',
    scales: [1, 2, 3, 4],
    method: LocalUpscaleMethod.seedvr2,
  ),
  LocalUpscaleModel(
    id: 'seedvr2-3b-int8',
    name: 'SeedVR2 3B INT8',
    engineName: 'seedvr2',
    scales: [1, 2, 3, 4],
    method: LocalUpscaleMethod.seedvr2,
  ),
  LocalUpscaleModel(
    id: 'seedvr2-7b-int8',
    name: 'SeedVR2 7B INT8',
    engineName: 'seedvr2',
    scales: [1, 2, 3, 4],
    method: LocalUpscaleMethod.seedvr2,
  ),
  LocalUpscaleModel(
    id: 'seedvr2-7b-sharp-int8',
    name: 'SeedVR2 7B Sharp INT8',
    engineName: 'seedvr2',
    scales: [1, 2, 3, 4],
    method: LocalUpscaleMethod.seedvr2,
  ),
  LocalUpscaleModel(
    id: 'rtx-vsr',
    name: 'NVIDIA RTX Video Super Resolution',
    engineName: 'rtx-vsr',
    scales: [1, 2, 3, 4],
    method: LocalUpscaleMethod.rtx,
  ),
];

class Seedvr2Options {
  const Seedvr2Options({
    this.colorCorrection = 'lab',
    this.seed = 0,
    this.blocksToSwap = 0,
    this.vaeTiled = true,
    this.vaeTileSize = 1024,
    this.vaeTileOverlap = 128,
    this.inputNoise = 0,
    this.latentNoise = 0,
  });

  static const colors = [
    'lab',
    'wavelet',
    'wavelet_adaptive',
    'hsv',
    'adain',
    'none',
  ];
  static int maxBlocks(String modelId) => switch (modelId) {
    'seedvr2-7b' ||
    'seedvr2-7b-sharp' ||
    'seedvr2-7b-int8' ||
    'seedvr2-7b-sharp-int8' => 36,
    _ => 32,
  };
  final String colorCorrection;
  final int seed, blocksToSwap, vaeTileSize, vaeTileOverlap;
  final bool vaeTiled;
  final double inputNoise, latentNoise;

  Seedvr2Options copyWith({
    String? colorCorrection,
    int? seed,
    int? blocksToSwap,
    bool? vaeTiled,
    int? vaeTileSize,
    int? vaeTileOverlap,
    double? inputNoise,
    double? latentNoise,
  }) => Seedvr2Options(
    colorCorrection: colorCorrection ?? this.colorCorrection,
    seed: seed ?? this.seed,
    blocksToSwap: blocksToSwap ?? this.blocksToSwap,
    vaeTiled: vaeTiled ?? this.vaeTiled,
    vaeTileSize: vaeTileSize ?? this.vaeTileSize,
    vaeTileOverlap: vaeTileOverlap ?? this.vaeTileOverlap,
    inputNoise: inputNoise ?? this.inputNoise,
    latentNoise: latentNoise ?? this.latentNoise,
  );

  Seedvr2Options normalized(String modelId) {
    final tile = (vaeTileSize.clamp(128, 4096) ~/ 64) * 64;
    return copyWith(
      colorCorrection: colors.contains(colorCorrection)
          ? colorCorrection
          : 'lab',
      seed: seed.clamp(0, 0xffffffff),
      blocksToSwap: blocksToSwap.clamp(0, maxBlocks(modelId)),
      vaeTileSize: tile,
      vaeTileOverlap: (vaeTileOverlap.clamp(0, tile - 64) ~/ 8) * 8,
      inputNoise: inputNoise.isFinite ? inputNoise.clamp(0, 1) : 0,
      latentNoise: latentNoise.isFinite ? latentNoise.clamp(0, 1) : 0,
    );
  }

  factory Seedvr2Options.fromJson(Object? value, {required String modelId}) {
    final map = value is Map ? value : const {};
    int integer(String key, int fallback) =>
        map[key] is num && (map[key] as num).isFinite
        ? (map[key] as num).toInt()
        : fallback;
    double number(String key) =>
        map[key] is num ? (map[key] as num).toDouble() : 0;
    return Seedvr2Options(
      colorCorrection: map['colorCorrection'] is String
          ? map['colorCorrection'] as String
          : 'lab',
      seed: integer('seed', 0),
      blocksToSwap: integer('blocksToSwap', 0),
      vaeTiled: map['vaeTiled'] is bool ? map['vaeTiled'] as bool : true,
      vaeTileSize: integer('vaeTileSize', 1024),
      vaeTileOverlap: integer('vaeTileOverlap', 128),
      inputNoise: number('inputNoise'),
      latentNoise: number('latentNoise'),
    ).normalized(modelId);
  }

  Map<String, Object> toJson() => {
    'colorCorrection': colorCorrection,
    'seed': seed,
    'blocksToSwap': blocksToSwap,
    'vaeTiled': vaeTiled,
    'vaeTileSize': vaeTileSize,
    'vaeTileOverlap': vaeTileOverlap,
    'inputNoise': inputNoise,
    'latentNoise': latentNoise,
  };

  List<String> arguments(String modelId) {
    final value = normalized(modelId);
    return [
      '--seed',
      '${value.seed}',
      '--color_correction',
      value.colorCorrection,
      '--input_noise_scale',
      '${value.inputNoise}',
      '--latent_noise_scale',
      '${value.latentNoise}',
      '--blocks_to_swap',
      '${value.blocksToSwap}',
      if (value.blocksToSwap >= 24) '--swap_io_components',
      if (value.vaeTiled) ...[
        '--vae_encode_tiled',
        '--vae_decode_tiled',
        '--vae_encode_tile_size',
        '${value.vaeTileSize}',
        '--vae_decode_tile_size',
        '${value.vaeTileSize}',
        '--vae_encode_tile_overlap',
        '${value.vaeTileOverlap}',
        '--vae_decode_tile_overlap',
        '${value.vaeTileOverlap}',
      ],
    ];
  }
}

class LocalUpscaleResult {
  const LocalUpscaleResult(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width;
  final int height;
}

class LocalUpscaleCancellation {
  bool _cancelled = false;
  final _listeners = <void Function()>[];
  bool get isCancelled => _cancelled;
  void check() {
    if (_cancelled) {
      throw const LocalUpscaleException(LocalUpscaleError.cancelled);
    }
  }

  void Function() listen(void Function() callback) {
    if (_cancelled) {
      callback();
      return () {};
    }
    _listeners.add(callback);
    return () => _listeners.remove(callback);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }
}
