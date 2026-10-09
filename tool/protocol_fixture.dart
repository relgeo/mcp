import 'dart:convert';

const mcpFixtureProtocolVersion = '2025-11-25';
const mcpFixtureToolName = 'relgeo_fixture_echo';
const mcpFixtureResourceUri = 'relgeo://fixture/provenance';

/// A deliberately small JSON-RPC/MCP fixture shared by both transports.
///
/// This is not the RelGeo server implementation. It exists to prove that a
/// candidate SDK/transport preserves the same initialize, tools, and resources
/// wire contract over stdio and Streamable HTTP.
class McpProtocolFixture {
  bool _initialized = false;

  bool get initialized => _initialized;

  Map<String, Object?>? handle(Map<String, Object?> message) {
    final method = message['method'];
    if (method is! String) {
      return _error(message['id'], -32600, 'Invalid Request');
    }

    if (method == 'notifications/initialized') {
      _initialized = true;
      return null;
    }
    if (method == 'notifications/cancelled') return null;

    final id = message['id'];
    if (id == null) return null;

    if (method == 'initialize') return _initialize(message);
    if (method == 'ping') return _result(id, <String, Object?>{});
    if (!_initialized) {
      return _error(id, -32002, 'Server not initialized');
    }

    switch (method) {
      case 'tools/list':
        return _result(id, <String, Object?>{
          'tools': <Object?>[
            <String, Object?>{
              'name': mcpFixtureToolName,
              'description': 'Echoes a bounded fixture message.',
              'inputSchema': <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{
                  'message': <String, Object?>{'type': 'string'},
                },
                'required': <Object?>['message'],
                'additionalProperties': false,
              },
            },
          ],
        });
      case 'tools/call':
        return _callTool(id, message['params']);
      case 'resources/list':
        return _result(id, <String, Object?>{
          'resources': <Object?>[
            <String, Object?>{
              'uri': mcpFixtureResourceUri,
              'name': 'Fixture provenance',
              'description': 'Versioned provenance fixture.',
              'mimeType': 'application/json',
            },
          ],
        });
      case 'resources/read':
        return _readResource(id, message['params']);
      default:
        return _error(id, -32601, 'Method not found: $method');
    }
  }

  Map<String, Object?> _initialize(Map<String, Object?> message) {
    final params = _map(message['params']);
    final requested = params?['protocolVersion'];
    if (requested is String && requested != mcpFixtureProtocolVersion) {
      return _error(message['id'], -32602, 'Unsupported protocol version', {
        'supported': <String>[mcpFixtureProtocolVersion],
        'requested': requested,
      });
    }
    return _result(message['id'], <String, Object?>{
      'protocolVersion': mcpFixtureProtocolVersion,
      'capabilities': <String, Object?>{
        'tools': <String, Object?>{'listChanged': false},
        'resources': <String, Object?>{
          'subscribe': false,
          'listChanged': false,
        },
      },
      'serverInfo': <String, Object?>{
        'name': 'relgeo-mcp-protocol-fixture',
        'version': '0.1.0',
      },
    });
  }

  Map<String, Object?> _callTool(Object? id, Object? rawParams) {
    final params = _map(rawParams);
    if (params?['name'] != mcpFixtureToolName) {
      return _error(id, -32602, 'Unknown fixture tool');
    }
    final arguments = _map(params?['arguments']);
    final message = arguments?['message'];
    if (message is! String || message.isEmpty || message.length > 256) {
      return _error(id, -32602, 'message must be 1..256 characters');
    }
    return _result(id, <String, Object?>{
      'content': <Object?>[
        <String, Object?>{'type': 'text', 'text': message},
      ],
      'structuredContent': <String, Object?>{'echo': message},
      'isError': false,
    });
  }

  Map<String, Object?> _readResource(Object? id, Object? rawParams) {
    final params = _map(rawParams);
    if (params?['uri'] != mcpFixtureResourceUri) {
      return _error(id, -32602, 'Unknown fixture resource');
    }
    return _result(id, <String, Object?>{
      'contents': <Object?>[
        <String, Object?>{
          'uri': mcpFixtureResourceUri,
          'mimeType': 'application/json',
          'text': jsonEncode(<String, Object?>{
            'source': 'spec',
            'sourceUrl': 'https://github.com/relgeo/spec',
            'specVersion': '0.5.x',
            'revision': 'fixture-v1',
          }),
        },
      ],
    });
  }

  Map<String, Object?> _result(Object? id, Map<String, Object?> result) =>
      <String, Object?>{'jsonrpc': '2.0', 'id': id, 'result': result};

  Map<String, Object?> _error(
    Object? id,
    int code,
    String message, [
    Map<String, Object?>? data,
  ]) => <String, Object?>{
    'jsonrpc': '2.0',
    'id': id,
    'error': <String, Object?>{
      'code': code,
      'message': message,
      if (data != null) 'data': data,
    },
  };

  Map<String, Object?>? _map(Object? value) =>
      value is Map<String, Object?> ? value : null;
}
