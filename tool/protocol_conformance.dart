import 'dart:convert';

import 'protocol_fixture.dart';

typedef RequestSender =
    Future<Map<String, Object?>> Function(Map<String, Object?> request);
typedef NotificationSender =
    Future<void> Function(Map<String, Object?> notification);

/// Sends the exact same request sequence through any transport adapter.
Future<void> runFixtureConformance({
  required RequestSender sendRequest,
  required NotificationSender sendNotification,
}) async {
  final initialize = await sendRequest(<String, Object?>{
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'initialize',
    'params': <String, Object?>{
      'protocolVersion': mcpFixtureProtocolVersion,
      'capabilities': <String, Object?>{},
      'clientInfo': <String, Object?>{
        'name': 'relgeo-fixture-conformance',
        'version': '0.1.0',
      },
    },
  });
  _expect(initialize['result'] is Map<String, Object?>, 'initialize result');
  _expect(
    _map(initialize['result'])?['protocolVersion'] == mcpFixtureProtocolVersion,
    'protocol version negotiation',
  );

  await sendNotification(<String, Object?>{
    'jsonrpc': '2.0',
    'method': 'notifications/initialized',
  });

  final tools = await sendRequest(<String, Object?>{
    'jsonrpc': '2.0',
    'id': 2,
    'method': 'tools/list',
    'params': <String, Object?>{},
  });
  final listedTools = _map(tools['result'])?['tools'];
  _expect(listedTools is List && listedTools.isNotEmpty, 'tools/list');
  final listedToolItems = listedTools as List<Object?>;
  _expect(
    _map(listedToolItems.first)?['name'] == mcpFixtureToolName,
    'fixture tool schema',
  );

  final toolCall = await sendRequest(<String, Object?>{
    'jsonrpc': '2.0',
    'id': 3,
    'method': 'tools/call',
    'params': <String, Object?>{
      'name': mcpFixtureToolName,
      'arguments': <String, Object?>{'message': 'same wire contract'},
    },
  });
  _expect(
    _map(_map(toolCall['result'])?['structuredContent'])?['echo'] ==
        'same wire contract',
    'tools/call structured content',
  );

  final resources = await sendRequest(<String, Object?>{
    'jsonrpc': '2.0',
    'id': 4,
    'method': 'resources/list',
    'params': <String, Object?>{},
  });
  final listedResources = _map(resources['result'])?['resources'];
  _expect(
    listedResources is List && listedResources.isNotEmpty,
    'resources/list',
  );

  final resource = await sendRequest(<String, Object?>{
    'jsonrpc': '2.0',
    'id': 5,
    'method': 'resources/read',
    'params': <String, Object?>{'uri': mcpFixtureResourceUri},
  });
  final contents = _map(resource['result'])?['contents'];
  _expect(contents is List && contents.isNotEmpty, 'resources/read');
  final contentItems = contents as List<Object?>;
  final provenance = jsonDecode(_map(contentItems.first)?['text'] as String);
  _expect(provenance['source'] == 'spec', 'resource provenance source');
  _expect(provenance['revision'] == 'fixture-v1', 'resource revision');
}

Map<String, Object?>? _map(Object? value) =>
    value is Map<String, Object?> ? value : null;

void _expect(bool condition, String label) {
  if (!condition) throw StateError('conformance failed: $label');
}
