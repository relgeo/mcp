import 'package:test/test.dart';

import '../tool/protocol_fixture.dart';

void main() {
  test('fixture exposes the same initialize/tools/resources wire contract', () {
    final fixture = McpProtocolFixture();

    final initialize = fixture.handle(<String, Object?>{
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': <String, Object?>{
        'protocolVersion': mcpFixtureProtocolVersion,
        'capabilities': <String, Object?>{},
        'clientInfo': <String, Object?>{'name': 'test', 'version': '0.1.0'},
      },
    });
    expect(initialize?['result'], isA<Map<String, Object?>>());
    expect(
      (initialize?['result'] as Map<String, Object?>)['protocolVersion'],
      mcpFixtureProtocolVersion,
    );

    expect(
      fixture.handle(<String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      }),
      isNull,
    );
    expect(
      fixture.handle(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/list',
      })?['result'],
      isA<Map<String, Object?>>(),
    );
    expect(
      fixture.handle(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': mcpFixtureToolName,
          'arguments': <String, Object?>{'message': 'fixture'},
        },
      })?['error'],
      isNull,
    );
    expect(
      fixture.handle(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 4,
        'method': 'resources/read',
        'params': <String, Object?>{'uri': mcpFixtureResourceUri},
      })?['result'],
      isA<Map<String, Object?>>(),
    );
  });

  test('fixture rejects unsupported version before operation phase', () {
    final fixture = McpProtocolFixture();
    final response = fixture.handle(<String, Object?>{
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': <String, Object?>{'protocolVersion': 'unsupported'},
    });

    expect(response?['error'], isA<Map<String, Object?>>());
    expect((response?['error'] as Map<String, Object?>)['code'], -32602);
  });
}
