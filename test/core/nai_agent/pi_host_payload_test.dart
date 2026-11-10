import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/nai_agent/pi_host_process.dart';

void main() {
  test('内嵌宿主载荷按 UTF-8 编码，中文行可被下游还原', () {
    const payload = '{"type":"response","message":"我想画一个满月意境的少女"}';
    final bytes = encodeHostPayload(payload);
    expect(utf8.decode(bytes), '$payload\n');
  });

  test('内嵌宿主载荷末尾只带一个换行', () {
    final bytes = encodeHostPayload('{"type":"ready"}');
    expect(bytes.last, 0x0A);
    expect(bytes.where((byte) => byte == 0x0A).length, 1);
  });
}
