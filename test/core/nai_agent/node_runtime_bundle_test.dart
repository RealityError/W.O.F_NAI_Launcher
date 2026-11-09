import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/nai_agent/node_runtime_bundle.dart';
import 'package:path/path.dart' as p;

/// Serves the packed fixture for the one asset the bundle reads.
class _SingleAssetBundle extends CachingAssetBundle {
  _SingleAssetBundle(this.bytes);

  final Uint8List bytes;

  @override
  Future<ByteData> load(String key) async {
    if (key != AndroidNodeRuntimeBundle.assetPath) {
      throw FlutterError('Unexpected asset: $key');
    }
    return ByteData.sublistView(bytes);
  }
}

const _longDirectory =
    'node_modules/some-very-long-package-name-that-exceeds-one-hundred-bytes-'
    'in-total-length-for-testing-purposes/lib/deeply/nested';

void main() {
  late Directory root;
  late Uint8List fixture;

  setUp(() {
    root = Directory.systemTemp.createTempSync('nai-agent-runtime-test');
    fixture = File(
      'test/core/nai_agent/fixtures/runtime_sample.tar.gz',
    ).readAsBytesSync();
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  AndroidNodeRuntimeBundle buildBundle() => AndroidNodeRuntimeBundle(
    root: root,
    assets: _SingleAssetBundle(fixture),
  );

  test('extracts the packed runtime and writes the version marker', () async {
    final progress = <String>[];
    final directory = await buildBundle().ensure(
      onProgress: (message, _) => progress.add(message),
    );

    expect(directory.path, root.path);
    expect(
      File(p.join(root.path, 'host.mjs')).readAsStringSync(),
      "console.log('host');",
    );
    expect(
      File(p.join(root.path, 'node_modules', 'pkg', 'index.js')).readAsStringSync(),
      'module.exports = 42;',
    );
    expect(
      File(p.join(root.path, _longDirectory, 'file.js')).readAsStringSync(),
      "export default 'long';",
    );
    expect(
      File(p.join(root.path, 'skills', 'nai-studio', 'references', 'blocks.md'))
          .existsSync(),
      isTrue,
    );
    expect(
      File(p.join(root.path, '.runtime-version')).readAsStringSync().trim(),
      AndroidNodeRuntimeBundle.bundleVersion,
    );
    expect(progress, contains('ready'));
  });

  test('a current marker skips extraction', () async {
    final bundle = buildBundle();
    await bundle.ensure();
    File(p.join(root.path, 'host.mjs')).writeAsStringSync('// locally changed');

    await bundle.ensure();

    expect(
      File(p.join(root.path, 'host.mjs')).readAsStringSync(),
      '// locally changed',
    );
  });

  test('a stale marker re-extracts the runtime', () async {
    final bundle = buildBundle();
    await bundle.ensure();
    File(p.join(root.path, '.runtime-version')).writeAsStringSync('older');
    File(p.join(root.path, 'host.mjs')).writeAsStringSync('// stale');

    await bundle.ensure();

    expect(
      File(p.join(root.path, 'host.mjs')).readAsStringSync(),
      "console.log('host');",
    );
    expect(
      File(p.join(root.path, '.runtime-version')).readAsStringSync().trim(),
      AndroidNodeRuntimeBundle.bundleVersion,
    );
  });
}
