import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/utils/app_bundle_paths.dart';
import 'package:path/path.dart' as p;

void main() {
  group('AppBundlePaths.resolveAgentDataDirectory', () {
    test('Android 放到应用支持目录，不放在只读的可执行目录', () {
      final root = AppBundlePaths.resolveAgentDataDirectory(
        android: true,
        executableDirectory: p.join('/system', 'bin'),
        androidSupport: '/data/user/0/com.wof.nai_launcher/files',
      );
      expect(
        root,
        p.join(
          '/data/user/0/com.wof.nai_launcher/files',
          'nai_agent',
          'agent-data',
        ),
      );
    });

    test('Android 缺少已解析的支持目录时报错，而不是退回只读路径', () {
      expect(
        () => AppBundlePaths.resolveAgentDataDirectory(
          android: true,
          executableDirectory: p.join('/system', 'bin'),
        ),
        throwsStateError,
      );
    });

    test('桌面仍放在可执行文件旁（安装器负责保留）', () {
      expect(
        AppBundlePaths.resolveAgentDataDirectory(
          android: false,
          executableDirectory: p.join('/opt', 'app'),
        ),
        p.join('/opt', 'app', 'agent-data'),
      );
    });

    test('macOS 使用已解析的应用支持目录', () {
      expect(
        AppBundlePaths.resolveAgentDataDirectory(
          android: false,
          macOS: true,
          executableDirectory: p.join('/Applications', 'x.app'),
          macSupport: p.join('/Users/me/Library/Application Support/x'),
        ),
        p.join('/Users/me/Library/Application Support/x', 'agent-data'),
      );
    });
  });
}
