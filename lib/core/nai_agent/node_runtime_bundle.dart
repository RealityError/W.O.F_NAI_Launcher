import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Manages the NAI Agent Node runtime shipped as a gzipped tar asset.
///
/// Android cannot execute binaries and the Pi host needs ~15k `node_modules`
/// files, so the runtime is packed once at build time and extracted into the
/// app support directory on first use. Extraction is streamed: the gzip stream
/// is inflated chunk by chunk and tar entries are written as they arrive, so
/// peak memory stays close to the asset size (about 24 MB).
class AndroidNodeRuntimeBundle {
  AndroidNodeRuntimeBundle({required this.root, AssetBundle? assets})
    : _assets = assets ?? rootBundle;

  /// Target directory, e.g. `<app support>/nai_agent/runtime`.
  final Directory root;
  final AssetBundle _assets;

  /// Bump when the packed runtime changes; the marker forces re-extraction.
  static const bundleVersion = '2026-11-13.1';
  static const assetPath = 'assets/nai_agent/runtime.tar.gz';
  static const _markerName = '.runtime-version';

  /// Rough number of files in the packed runtime; used for coarse progress.
  static const _expectedFiles = 16700;

  String get hostScript => p.join(root.path, 'host.mjs');

  /// Extracts the runtime when missing or stale and returns the runtime root.
  Future<Directory> ensure({
    void Function(String message, double progress)? onProgress,
  }) async {
    final marker = File(p.join(root.path, _markerName));
    if (await _isCurrent(marker)) {
      onProgress?.call('ready', 1);
      return root;
    }
    final temporary = Directory('${root.path}.tmp');
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
    await temporary.create(recursive: true);
    final data = await _assets.load(assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    await _extract(bytes, temporary, onProgress);
    if (!await File(p.join(temporary.path, 'host.mjs')).exists()) {
      throw const FileSystemException('NAI Agent runtime asset is incomplete');
    }
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
    await temporary.rename(root.path);
    await File(p.join(root.path, _markerName)).writeAsString(bundleVersion);
    onProgress?.call('ready', 1);
    return root;
  }

  Future<bool> _isCurrent(File marker) async {
    if (!await marker.exists()) return false;
    if ((await marker.readAsString()).trim() != bundleVersion) return false;
    return File(hostScript).exists();
  }

  Future<void> _extract(
    Uint8List bytes,
    Directory destination,
    void Function(String message, double progress)? onProgress,
  ) async {
    var files = 0;
    final parser = _TarExtractor(
      destination,
      onEntry: () {
        files++;
        if (files % 200 == 0) {
          onProgress?.call(
            'unpacking',
            (files / _expectedFiles).clamp(0, 0.95),
          );
        }
      },
    );
    await for (final chunk in Stream<List<int>>.value(
      bytes,
    ).transform(gzip.decoder)) {
      await parser.add(chunk);
    }
    await parser.finish();
    onProgress?.call('unpacking', 1);
  }
}

enum _TarState { header, data, skip, pad, longName, pax, longLink }

/// Minimal streaming tar reader. Directories and regular files are enough for
/// npm's node_modules; GNU long-name entries and pax extended headers are
/// honoured so paths longer than 100 bytes survive the round trip. Symlinks and
/// other special entries are skipped on purpose.
class _TarExtractor {
  _TarExtractor(this.destination, {required this.onEntry});

  final Directory destination;
  final void Function() onEntry;

  final List<int> _buffer = <int>[];
  int _start = 0;
  _TarState _state = _TarState.header;
  RandomAccessFile? _file;
  int _remaining = 0;
  int _padding = 0;
  String? _longName;
  List<int> _meta = <int>[];
  bool _ended = false;

  int get _available => _buffer.length - _start;

  Future<void> add(List<int> chunk) async {
    if (_ended) return;
    _buffer.addAll(chunk);
    await _drain();
  }

  Future<void> finish() async {
    await _file?.close();
    _file = null;
  }

  Future<void> _drain() async {
    while (!_ended) {
      switch (_state) {
        case _TarState.header:
          if (_available < 512) return;
          final header = _take(512);
          if (header.every((byte) => byte == 0)) {
            _ended = true;
            await _file?.close();
            _file = null;
            return;
          }
          await _handleHeader(header);
        case _TarState.data:
          if (_available == 0) return;
          final count = _remaining < _available ? _remaining : _available;
          await _file?.writeFrom(_take(count));
          _remaining -= count;
          if (_remaining == 0) {
            await _file?.close();
            _file = null;
            _enterPadding();
          }
        case _TarState.skip:
          if (_available == 0) return;
          final count = _remaining < _available ? _remaining : _available;
          _take(count);
          _remaining -= count;
          if (_remaining == 0) _enterPadding();
        case _TarState.pad:
          if (_remaining == 0) {
            _state = _TarState.header;
            continue;
          }
          if (_available == 0) return;
          final count = _remaining < _available ? _remaining : _available;
          _take(count);
          _remaining -= count;
        case _TarState.longName:
        case _TarState.pax:
        case _TarState.longLink:
          if (_available == 0) return;
          final count = _remaining < _available ? _remaining : _available;
          _meta.addAll(_take(count));
          _remaining -= count;
          if (_remaining == 0) {
            _consumeMeta();
            _enterPadding();
          }
      }
    }
  }

  Future<void> _handleHeader(Uint8List header) async {
    final name = _string(header, 0, 100);
    final prefix = _string(header, 345, 500);
    final size = _octal(header, 124, 136);
    final type = header[156];
    final fullName = prefix.isEmpty ? name : '$prefix/$name';
    _remaining = size;
    _padding = (512 - (size % 512)) % 512;
    switch (type) {
      case 0x35: // '5' directory
        await _createDirectory(fullName);
        _state = _TarState.skip;
      case 0x30 || 0x00: // '0' / '\0' regular file
        _file = await _openFile(_longName ?? fullName);
        _longName = null;
        _state = _TarState.data;
        onEntry();
      case 0x4C: // 'L' GNU long name
        _meta = <int>[];
        _state = _TarState.longName;
      case 0x4B: // 'K' GNU long link name
        _meta = <int>[];
        _state = _TarState.longLink;
      case 0x78 || 0x67: // 'x' per-file / 'g' global pax header
        _meta = <int>[];
        _state = _TarState.pax;
      default:
        // Symlinks, hard links, devices: skip payload.
        _longName = null;
        _state = _TarState.skip;
    }
  }

  void _consumeMeta() {
    final text = String.fromCharCodes(_meta);
    _meta = <int>[];
    switch (_state) {
      case _TarState.longName:
        _longName = text.trimRight();
      case _TarState.pax:
        for (final record in _parsePax(text)) {
          if (record.$1 == 'path') _longName = record.$2;
        }
      default:
        // Long link names are irrelevant for regular-file extraction.
        break;
    }
  }

  static Iterable<(String, String)> _parsePax(String text) sync* {
    var offset = 0;
    while (offset < text.length) {
      final space = text.indexOf(' ', offset);
      if (space < 0) return;
      final length = int.tryParse(text.substring(offset, space));
      if (length == null || length <= 0) return;
      final end = offset + length;
      if (end > text.length) return;
      final record = text.substring(space + 1, end).trimRight();
      final equals = record.indexOf('=');
      if (equals > 0) {
        yield (record.substring(0, equals), record.substring(equals + 1));
      }
      offset = end;
    }
  }

  void _enterPadding() {
    _remaining = _padding;
    _padding = 0;
    _state = _remaining == 0 ? _TarState.header : _TarState.pad;
  }

  Future<void> _createDirectory(String name) async {
    final target = _safePath(name);
    if (target == null) return;
    await Directory(target).create(recursive: true);
  }

  Future<RandomAccessFile?> _openFile(String name) async {
    final target = _safePath(name);
    if (target == null) return null;
    final file = File(target);
    await file.parent.create(recursive: true);
    return file.open(mode: FileMode.write);
  }

  String? _safePath(String name) {
    final normalized = p.posix.normalize(name);
    if (normalized.startsWith('..') || p.posix.isAbsolute(normalized)) {
      return null;
    }
    final target = p.joinAll([
      destination.path,
      ...p.posix.split(normalized),
    ]);
    final relative = p.relative(target, from: destination.path);
    return relative.startsWith('..') ? null : target;
  }

  Uint8List _take(int length) {
    final view = Uint8List.fromList(
      _buffer.sublist(_start, _start + length),
    );
    _start += length;
    if (_start > 1 << 20 && _start * 2 > _buffer.length) {
      _buffer.removeRange(0, _start);
      _start = 0;
    }
    return view;
  }

  static String _string(Uint8List data, int start, int end) {
    final slice = data.sublist(start, end);
    final terminator = slice.indexOf(0);
    return String.fromCharCodes(
      terminator == -1 ? slice : slice.sublist(0, terminator),
    );
  }

  static int _octal(Uint8List data, int start, int end) {
    final text = String.fromCharCodes(data.sublist(start, end)).trim();
    return int.tryParse(text, radix: 8) ?? 0;
  }
}
