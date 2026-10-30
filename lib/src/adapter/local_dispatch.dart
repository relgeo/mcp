import 'dart:async';
import 'dart:convert';

import '../contract/mcp_schema.dart';
import '../contract/session_bridge.dart';

/// A protocol-level invalid request or method error.
class McpDispatchException implements Exception {
  const McpDispatchException(this.code, this.message, {this.data});

  final int code;
  final String message;
  final Map<String, Object?>? data;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'message': message,
    if (data != null) 'data': data,
  };

  @override
  String toString() => 'McpDispatchException($code): $message';
}

typedef FindSyntaxHandler =
    FutureOr<FindSyntaxResult> Function(FindSyntaxInput input);
typedef GetSyntaxRuleHandler =
    FutureOr<SyntaxRuleResult> Function(GetSyntaxRuleInput input);
typedef GetExamplesHandler =
    FutureOr<ExamplesResult> Function(GetExamplesInput input);
typedef CompleteSourceHandler =
    FutureOr<CompletionResult> Function(CompleteSourceInput input);
typedef ValidateSourceHandler =
    FutureOr<ValidationResult> Function(ValidateSourceInput input);
typedef ExplainDiagnosticHandler =
    FutureOr<DiagnosticExplanationResult> Function(
      ExplainDiagnosticInput input,
    );
typedef RenderSourceHandler =
    FutureOr<RenderResult> Function(RenderSourceInput input);

/// Typed owner callbacks used by the protocol adapter.
///
/// The adapter owns wire validation and result serialization. The callbacks
/// remain owned by `spec/id`, `core`, `language-service`, and `renderer-svg`
/// integrations, so the pure-Dart package does not invent a second semantic
/// engine.
class RelGeoMcpToolHandlers {
  const RelGeoMcpToolHandlers({
    required this.findSyntax,
    required this.getSyntaxRule,
    required this.getExamples,
    required this.completeSource,
    required this.validateSource,
    required this.explainDiagnostic,
    required this.renderSource,
  });

  final FindSyntaxHandler findSyntax;
  final GetSyntaxRuleHandler getSyntaxRule;
  final GetExamplesHandler getExamples;
  final CompleteSourceHandler completeSource;
  final ValidateSourceHandler validateSource;
  final ExplainDiagnosticHandler explainDiagnostic;
  final RenderSourceHandler renderSource;
}

/// The canonical resource payload returned by `resources/read`.
class McpResourceContent {
  const McpResourceContent({
    required this.uri,
    required this.mimeType,
    required this.text,
    this.provenance,
  });

  final String uri;
  final String mimeType;
  final String text;
  final McpProvenance? provenance;

  Map<String, Object?> toJson() => <String, Object?>{
    'uri': uri,
    'mimeType': mimeType,
    'text': text,
    if (provenance != null) 'provenance': provenance!.toJson(),
  };
}

/// Read-only resource resolver with explicit active-document handling.
class RelGeoMcpResourceStore {
  RelGeoMcpResourceStore({
    Map<String, McpResourceContent> staticResources =
        const <String, McpResourceContent>{},
    this.activeBridge,
  }) : _staticResources = Map<String, McpResourceContent>.unmodifiable(
         staticResources,
       );

  final Map<String, McpResourceContent> _staticResources;
  final RelGeoAgentBridge? activeBridge;

  List<Map<String, Object?>> listResources() => relGeoMvpResourceUris
      .map(
        (uri) => <String, Object?>{
          'uri': uri,
          'name': _resourceName(uri),
          'mimeType': 'application/json',
        },
      )
      .toList(growable: false);

  Future<McpResourceContent> read(String value) async {
    final uri = _parseUri(value);
    switch (uri.kind) {
      case RelGeoResourceKind.activeDocument:
        final bridge = activeBridge;
        if (bridge == null) {
          throw const McpDispatchException(
            -32001,
            'No active document session is connected',
          );
        }
        final snapshot = await bridge.getActiveDocument();
        if (snapshot == null) {
          throw const McpDispatchException(
            -32001,
            'No active document session is connected',
          );
        }
        return McpResourceContent(
          uri: uri.value,
          mimeType: 'application/json',
          text: jsonEncode(snapshot.toJson()),
        );
      case RelGeoResourceKind.activeDiagnostics:
        final bridge = activeBridge;
        if (bridge == null) {
          throw const McpDispatchException(
            -32001,
            'No active document session is connected',
          );
        }
        final diagnostics = await bridge.getDiagnostics();
        return McpResourceContent(
          uri: uri.value,
          mimeType: 'application/json',
          text: jsonEncode(
            diagnostics.map((diagnostic) => diagnostic.toJson()).toList(),
          ),
        );
      case RelGeoResourceKind.specIndex:
      case RelGeoResourceKind.specRule:
      case RelGeoResourceKind.examplesIndex:
      case RelGeoResourceKind.example:
      case RelGeoResourceKind.diagnosticsCatalog:
        final content = _staticResources[uri.value];
        if (content == null) {
          throw McpDispatchException(
            -32004,
            'Resource is not available in the pinned local snapshot',
            data: <String, Object?>{'uri': uri.value},
          );
        }
        return content;
    }
  }

  static RelGeoResourceUri _parseUri(String value) {
    try {
      return RelGeoResourceUri.parse(value);
    } on FormatException catch (error) {
      throw McpDispatchException(
        -32602,
        error.message,
        data: <String, Object?>{'uri': value},
      );
    }
  }

  static String _resourceName(String uri) {
    if (uri.startsWith('relgeo://spec')) return 'RelGeo specification';
    if (uri.startsWith('relgeo://examples')) return 'RelGeo examples';
    if (uri.startsWith('relgeo://diagnostics')) return 'RelGeo diagnostics';
    return 'Active RelGeo document';
  }
}

/// Typed tool dispatcher. It validates raw protocol arguments before invoking
/// an owner callback and serializes only the declared result type.
class RelGeoMcpToolDispatcher {
  const RelGeoMcpToolDispatcher(this.handlers);

  final RelGeoMcpToolHandlers handlers;

  List<Map<String, Object?>> listTools() => relGeoMvpToolContracts
      .map(
        (contract) => <String, Object?>{
          'name': contract.name,
          'description': contract.description,
          'inputSchema': contract.inputSchema,
        },
      )
      .toList(growable: false);

  Future<Map<String, Object?>> call(String name, Object? rawArguments) async {
    switch (name) {
      case 'relgeo_find_syntax':
        return (await handlers.findSyntax(_findSyntax(rawArguments))).toJson();
      case 'relgeo_get_syntax_rule':
        return (await handlers.getSyntaxRule(
          _getSyntaxRule(rawArguments),
        )).toJson();
      case 'relgeo_get_examples':
        return (await handlers.getExamples(
          _getExamples(rawArguments),
        )).toJson();
      case 'relgeo_complete_source':
        return (await handlers.completeSource(
          _completeSource(rawArguments),
        )).toJson();
      case 'relgeo_validate_source':
        return (await handlers.validateSource(
          _validateSource(rawArguments),
        )).toJson();
      case 'relgeo_explain_diagnostic':
        return (await handlers.explainDiagnostic(
          _explainDiagnostic(rawArguments),
        )).toJson();
      case 'relgeo_render_source':
        return (await handlers.renderSource(
          _renderSource(rawArguments),
        )).toJson();
      default:
        throw McpDispatchException(
          -32601,
          'Unknown RelGeo tool: $name',
          data: <String, Object?>{'name': name},
        );
    }
  }

  static FindSyntaxInput _findSyntax(Object? raw) {
    final args = _arguments(raw, 'relgeo_find_syntax');
    _rejectUnknown(args, const <String>{'query', 'specVersion', 'maxResults'});
    return FindSyntaxInput(
      query: _requiredString(args, 'query'),
      specVersion: _optionalVersion(args),
      maxResults: _optionalInt(args, 'maxResults', 8, 1, 32),
    );
  }

  static GetSyntaxRuleInput _getSyntaxRule(Object? raw) {
    final args = _arguments(raw, 'relgeo_get_syntax_rule');
    _rejectUnknown(args, const <String>{'ruleId', 'specVersion'});
    return GetSyntaxRuleInput(
      ruleId: _requiredString(args, 'ruleId'),
      specVersion: _optionalVersion(args),
    );
  }

  static GetExamplesInput _getExamples(Object? raw) {
    final args = _arguments(raw, 'relgeo_get_examples');
    _rejectUnknown(args, const <String>{
      'query',
      'exampleId',
      'specVersion',
      'maxResults',
    });
    final query = _optionalString(args, 'query');
    final exampleId = _optionalString(args, 'exampleId');
    if (query == null && exampleId == null) {
      throw const McpDispatchException(
        -32602,
        'relgeo_get_examples requires query or exampleId',
      );
    }
    return GetExamplesInput(
      query: query,
      exampleId: exampleId,
      specVersion: _optionalVersion(args),
      maxResults: _optionalInt(args, 'maxResults', 6, 1, 24),
    );
  }

  static CompleteSourceInput _completeSource(Object? raw) {
    final args = _arguments(raw, 'relgeo_complete_source');
    _rejectUnknown(args, const <String>{
      'source',
      'position',
      'specVersion',
      'maxResults',
    });
    final position = _object(args, 'position');
    _rejectUnknown(position, const <String>{'line', 'character'});
    return CompleteSourceInput(
      source: _requiredString(args, 'source'),
      position: TextPosition(
        line: _requiredInt(position, 'line', 0),
        character: _requiredInt(position, 'character', 0),
      ),
      specVersion: _optionalVersion(args),
      maxResults: _optionalInt(args, 'maxResults', 32, 1, 64),
    );
  }

  static ValidateSourceInput _validateSource(Object? raw) {
    final args = _arguments(raw, 'relgeo_validate_source');
    _rejectUnknown(args, const <String>{
      'source',
      'sourceKind',
      'specVersion',
      'includeInfo',
    });
    final kind = _optionalString(args, 'sourceKind') ?? 'input';
    final sourceKind = SourceArtifactKind.values.where(
      (item) => item.name == kind,
    );
    if (sourceKind.isEmpty) {
      throw McpDispatchException(
        -32602,
        'sourceKind must be input, proposal, or activeDocument',
        data: <String, Object?>{'sourceKind': kind},
      );
    }
    final includeInfo = args['includeInfo'];
    if (includeInfo != null && includeInfo is! bool) {
      throw const McpDispatchException(-32602, 'includeInfo must be a boolean');
    }
    return ValidateSourceInput(
      source: _requiredString(args, 'source'),
      sourceKind: sourceKind.first,
      specVersion: _optionalVersion(args),
      includeInfo: includeInfo as bool? ?? false,
    );
  }

  static ExplainDiagnosticInput _explainDiagnostic(Object? raw) {
    final args = _arguments(raw, 'relgeo_explain_diagnostic');
    _rejectUnknown(args, const <String>{'code', 'message'});
    return ExplainDiagnosticInput(
      code: _requiredString(args, 'code'),
      message: _optionalString(args, 'message'),
    );
  }

  static RenderSourceInput _renderSource(Object? raw) {
    final args = _arguments(raw, 'relgeo_render_source');
    _rejectUnknown(args, const <String>{
      'source',
      'format',
      'sheetId',
      'specVersion',
    });
    final format = _optionalString(args, 'format') ?? 'svg';
    if (format != 'svg') {
      throw McpDispatchException(
        -32602,
        'format must be svg',
        data: <String, Object?>{'format': format},
      );
    }
    return RenderSourceInput(
      source: _requiredString(args, 'source'),
      format: RenderFormat.svg,
      sheetId: _optionalString(args, 'sheetId'),
      specVersion: _optionalVersion(args),
    );
  }

  static Map<String, Object?> _arguments(Object? raw, String tool) {
    if (raw is! Map) {
      throw McpDispatchException(
        -32602,
        'Arguments for $tool must be an object',
      );
    }
    if (raw.keys.any((key) => key is! String)) {
      throw McpDispatchException(
        -32602,
        'Arguments for $tool must use string keys',
      );
    }
    return <String, Object?>{
      for (final entry in raw.entries) entry.key as String: entry.value,
    };
  }

  static Map<String, Object?> _object(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value is! Map) {
      throw McpDispatchException(-32602, '$key must be an object');
    }
    if (value.keys.any((item) => item is! String)) {
      throw McpDispatchException(-32602, '$key must use string keys');
    }
    return <String, Object?>{
      for (final entry in value.entries) entry.key as String: entry.value,
    };
  }

  static void _rejectUnknown(Map<String, Object?> args, Set<String> allowed) {
    final unknown = args.keys.where((key) => !allowed.contains(key)).toList();
    if (unknown.isNotEmpty) {
      throw McpDispatchException(
        -32602,
        'Unknown argument: ${unknown.first}',
        data: <String, Object?>{'unknown': unknown},
      );
    }
  }

  static String _requiredString(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value is! String || value.isEmpty) {
      throw McpDispatchException(-32602, '$key must be a non-empty string');
    }
    return value;
  }

  static String? _optionalString(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value == null) return null;
    if (value is! String || value.isEmpty) {
      throw McpDispatchException(
        -32602,
        '$key must be a non-empty string when provided',
      );
    }
    return value;
  }

  static String _optionalVersion(Map<String, Object?> args) =>
      _optionalString(args, 'specVersion') ?? relGeoMvpSpecVersion;

  static int _optionalInt(
    Map<String, Object?> args,
    String key,
    int fallback,
    int minimum,
    int maximum,
  ) {
    final value = args[key];
    if (value == null) return fallback;
    if (value is! int || value < minimum || value > maximum) {
      throw McpDispatchException(
        -32602,
        '$key must be an integer between $minimum and $maximum',
      );
    }
    return value;
  }

  static int _requiredInt(Map<String, Object?> args, String key, int minimum) {
    final value = args[key];
    if (value is! int || value < minimum) {
      throw McpDispatchException(
        -32602,
        '$key must be an integer greater than or equal to $minimum',
      );
    }
    return value;
  }
}

/// Transport-independent JSON-RPC router for the typed RelGeo adapter.
///
/// A stdio or HTTP host can frame messages around this router without
/// duplicating initialization, discovery, validation, or resource semantics.
/// The router deliberately has no socket, filesystem, or process dependency.
class RelGeoMcpJsonRpcRouter {
  RelGeoMcpJsonRpcRouter({required this.dispatcher, required this.resources});

  static const protocolVersion = '2025-11-25';

  final RelGeoMcpToolDispatcher dispatcher;
  final RelGeoMcpResourceStore resources;
  bool _initialized = false;

  bool get initialized => _initialized;

  Future<Map<String, Object?>?> handle(Map<String, Object?> message) async {
    final hasId = message.containsKey('id');
    final id = message['id'];
    final method = message['method'];
    if (method is! String || method.isEmpty) {
      return _response(
        hasId,
        id,
        error: const McpDispatchException(-32600, 'Invalid Request'),
      );
    }

    if (method == 'notifications/initialized' ||
        method == 'notifications/cancelled') {
      if (method == 'notifications/initialized') _initialized = true;
      return null;
    }

    if (method == 'initialize') {
      late final Map<String, Object?> params;
      try {
        params = _params(message);
      } on McpDispatchException catch (error) {
        return _response(hasId, id, error: error);
      }
      final requested = params['protocolVersion'];
      if (requested != null && requested is! String) {
        return _response(
          hasId,
          id,
          error: const McpDispatchException(
            -32602,
            'protocolVersion must be a string',
          ),
        );
      }
      if (requested is String && requested != protocolVersion) {
        return _response(
          hasId,
          id,
          error: McpDispatchException(
            -32602,
            'Unsupported protocol version',
            data: <String, Object?>{
              'supported': <String>[protocolVersion],
              'requested': requested,
            },
          ),
        );
      }
      return _response(
        hasId,
        id,
        result: <String, Object?>{
          'protocolVersion': protocolVersion,
          'capabilities': <String, Object?>{
            'tools': <String, Object?>{'listChanged': false},
            'resources': <String, Object?>{
              'subscribe': false,
              'listChanged': false,
            },
          },
          'serverInfo': <String, Object?>{
            'name': 'relgeo-mcp',
            'version': '0.1.0',
          },
        },
      );
    }

    if (!_initialized) {
      return _response(
        hasId,
        id,
        error: const McpDispatchException(-32002, 'Server not initialized'),
      );
    }

    try {
      switch (method) {
        case 'tools/list':
          return _response(
            hasId,
            id,
            result: <String, Object?>{'tools': dispatcher.listTools()},
          );
        case 'tools/call':
          final params = _requiredParams(message, hasId, id);
          final name = params['name'];
          if (name is! String || name.isEmpty) {
            throw const McpDispatchException(
              -32602,
              'tools/call requires a non-empty name',
            );
          }
          final output = await dispatcher.call(name, params['arguments']);
          return _response(
            hasId,
            id,
            result: <String, Object?>{
              'content': <Object?>[
                <String, Object?>{'type': 'text', 'text': jsonEncode(output)},
              ],
              'structuredContent': output,
              'isError': false,
            },
          );
        case 'resources/list':
          return _response(
            hasId,
            id,
            result: <String, Object?>{'resources': resources.listResources()},
          );
        case 'resources/read':
          final params = _requiredParams(message, hasId, id);
          final uri = params['uri'];
          if (uri is! String || uri.isEmpty) {
            throw const McpDispatchException(
              -32602,
              'resources/read requires a non-empty uri',
            );
          }
          final content = await resources.read(uri);
          return _response(
            hasId,
            id,
            result: <String, Object?>{
              'contents': <Object?>[content.toJson()],
            },
          );
        default:
          throw McpDispatchException(
            -32601,
            'Method not found: $method',
            data: <String, Object?>{'method': method},
          );
      }
    } on McpDispatchException catch (error) {
      return _response(hasId, id, error: error);
    }
  }

  static Map<String, Object?> _params(Map<String, Object?> message) {
    final raw = message['params'];
    if (raw == null) return <String, Object?>{};
    if (raw is! Map || raw.keys.any((key) => key is! String)) {
      throw const McpDispatchException(-32602, 'params must be an object');
    }
    return <String, Object?>{
      for (final entry in raw.entries) entry.key as String: entry.value,
    };
  }

  static Map<String, Object?> _requiredParams(
    Map<String, Object?> message,
    bool hasId,
    Object? id,
  ) {
    final raw = message['params'];
    if (raw is! Map || raw.keys.any((key) => key is! String)) {
      throw const McpDispatchException(-32602, 'params must be an object');
    }
    return <String, Object?>{
      for (final entry in raw.entries) entry.key as String: entry.value,
    };
  }

  static Map<String, Object?>? _response(
    bool hasId,
    Object? id, {
    Map<String, Object?>? result,
    McpDispatchException? error,
  }) {
    if (!hasId) return null;
    return <String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      if (result != null) 'result': result,
      if (error != null) 'error': error.toJson(),
    };
  }
}
