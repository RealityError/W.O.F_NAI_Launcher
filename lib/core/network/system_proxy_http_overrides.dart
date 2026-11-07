import 'dart:io';

import '../utils/app_logger.dart';

/// 系统代理 HTTP 覆盖类
///
/// 通过 [HttpOverrides.global] 注入，实现全局代理配置。
/// 该类会拦截所有基于 [dart:io.HttpClient] 的网络请求，
/// 包括 Dio 和 CachedNetworkImage。
class SystemProxyHttpOverrides extends HttpOverrides {
  /// 代理配置字符串
  final String _proxyString;

  /// 构造函数
  ///
  /// [proxyString] 格式为 "PROXY host:port" 或 "DIRECT"
  SystemProxyHttpOverrides(this._proxyString);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    // 调用父类方法创建默认客户端
    final client = super.createHttpClient(context);

    // 设置代理配置
    // findProxy 回调接收请求 URI，返回代理字符串
    client.findProxy = (uri) {
      // 本机回环（3D 编辑器本地资源服务、Krita 桥接等）必须直连。
      final isLoopbackHost =
          uri.host.toLowerCase() == 'localhost' ||
          InternetAddress.tryParse(uri.host)?.isLoopback == true;
      if (Platform.isMacOS && isLoopbackHost) {
        return 'DIRECT';
      }
      // Android 手机常配系统代理访问外网：局域网内部服务（ComfyUI 等）直连，
      // 否则会被代理服务器当成远程地址而失败。
      if (Platform.isAndroid &&
          (isLoopbackHost || _isPrivateNetworkHost(uri.host))) {
        return 'DIRECT';
      }
      AppLogger.d(
        'Proxy request for: ${uri.host}:${uri.port} -> $_proxyString',
        'PROXY',
      );
      return _proxyString;
    };

    // 可选：处理代理服务器的证书验证问题
    // 对于某些本地代理工具（如 Fiddler、Charles），可能需要忽略证书验证
    // 注意：这会降低安全性，仅在开发环境使用
    // client.badCertificateCallback = (cert, host, port) => true;

    return client;
  }

  /// 局域网 / 链路本地地址：代理服务器通常无法访问，交给直连。
  static bool _isPrivateNetworkHost(String host) {
    final lower = host.toLowerCase();
    if (lower.endsWith('.local')) return true;
    final address = InternetAddress.tryParse(host);
    if (address == null) return false;
    if (address.type == InternetAddressType.IPv4) {
      final bytes = address.rawAddress;
      return bytes[0] == 10 ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
          (bytes[0] == 192 && bytes[1] == 168) ||
          (bytes[0] == 169 && bytes[1] == 254);
    }
    if (address.type == InternetAddressType.IPv6) {
      final bytes = address.rawAddress;
      // fc00::/7（unique-local）与 fe80::/10（link-local）。
      return (bytes[0] & 0xfe) == 0xfc ||
          (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80);
    }
    return false;
  }
}
