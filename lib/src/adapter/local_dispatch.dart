import 'dart:async';
import 'dart:convert';

import '../contract/mcp_schema.dart';
import '../contract/session_bridge.dart';
import '../spec/spec_index.dart';

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
    this.specIndex,
  }) : _staticResources = Map<String, McpResourceContent>.unmodifiable(
         staticResources,
       );

  final Map<String, McpResourceContent> _staticResources;
  final RelGeoAgentBridge? activeBridge;
  final SpecSectionIndex? specIndex;

  List<Map<String, Object?>> listResources({bool includeUnavailable = true}) {
    final uris = <String>{
      if (includeUnavailable) ...relGeoMvpResourceUris,
      if (specIndex != null) ...relGeoSpecRetrievalResourceUris,
      ..._staticResources.keys,
      if (activeBridge != null) ...<String>[
        RelGeoResourceUri.activeDocument().value,
        RelGeoResourceUri.activeDiagnostics().value,
      ],
    };
    return uris
        .map(
          (uri) => <String, Object?>{
            'uri': uri,
            'name': _resourceName(uri),
            'mimeType': 'application/json',
          },
        )
        .toList(growable: false);
  }

  List<Map<String, Object?>> listResourceTemplates() {
    if (specIndex == null) return const <Map<String, Object?>>[];
    return const <Map<String, Object?>>[
      <String, Object?>{
        'uriTemplate': relGeoSpecSectionResourceTemplate,
        'name': 'RelGeo specification section',
        'description':
            'Read one complete section from the pinned RelGeo Markdown specification. Encode the sectionId path and anchor as one URI segment.',
        'mimeType': 'application/json',
      },
    ];
  }

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
      case RelGeoResourceKind.specSection:
      case RelGeoResourceKind.examplesIndex:
      case RelGeoResourceKind.example:
      case RelGeoResourceKind.diagnosticsCatalog:
        if (specIndex != null && uri.kind == RelGeoResourceKind.specIndex) {
          return McpResourceContent(
            uri: uri.value,
            mimeType: 'application/json',
            text: specIndex!.indexResourceText(),
          );
        }
        if (specIndex != null && uri.kind == RelGeoResourceKind.specSection) {
          late final GetSpecSectionResult section;
          try {
            section = specIndex!.getSection(
              GetSpecSectionInput(
                sectionId: SpecSectionId.parse(uri.id!),
                specVersion: specIndex!.snapshot.specVersion,
              ),
            );
          } on SpecSectionNotFoundException catch (error) {
            throw McpDispatchException(
              -32004,
              error.toString(),
              data: <String, Object?>{'sectionId': uri.id!},
            );
          }
          return McpResourceContent(
            uri: uri.value,
            mimeType: 'application/json',
            text: jsonEncode(section.toJson()),
            provenance: section.section.provenance.isNormative
                ? McpProvenance(
                    source: McpProvenanceSource.spec,
                    sourceUrl: section.section.provenance.sourceUrl,
                    specVersion: section.section.provenance.specVersion,
                    revision: section.section.provenance.revision,
                  )
                : null,
          );
        }
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
  const RelGeoMcpToolDispatcher(this.handlers, {this.specIndex});

  final RelGeoMcpToolHandlers? handlers;
  final SpecSectionIndex? specIndex;

  List<Map<String, Object?>> listTools() {
    final tools = <Map<String, Object?>>[
      ...<RelGeoToolContract>[
        if (handlers != null) ...relGeoMvpToolContracts,
        if (specIndex != null) ...relGeoSpecRetrievalToolContracts,
      ].map(
        (contract) => <String, Object?>{
          'name': contract.name,
          'description': contract.description,
          'inputSchema': contract.inputSchema,
        },
      ),
    ];
    if (specIndex != null) {
      tools.insert(0, _capabilitiesTool);
      if (handlers == null) {
        tools.insert(1, _specSearchCompatibilityAliasTool);
      }
    }
    return List<Map<String, Object?>>.unmodifiable(tools);
  }

  static const Map<String, Object?> _capabilitiesTool = <String, Object?>{
    'name': 'relgeo_get_capabilities',
    'description':
        'Report the read-only tools, resources, pinned spec snapshot, and limitations.',
    'inputSchema': <String, Object?>{
      'type': 'object',
      'additionalProperties': false,
      'properties': <String, Object?>{},
    },
  };

  static const Map<String, Object?> _specSearchCompatibilityAliasTool =
      <String, Object?>{
        'name': 'relgeo_find_syntax',
        'description':
            'Compatibility alias for searching the pinned local RelGeo specification.',
        'inputSchema': <String, Object?>{
          'type': 'object',
          'additionalProperties': false,
          'required': <String>['query'],
          'properties': <String, Object?>{
            'query': <String, Object?>{
              'type': 'string',
              'minLength': 1,
              'maxLength': 512,
            },
            'specVersion': <String, Object?>{
              'type': 'string',
              'minLength': 1,
              'default': relGeoMvpSpecVersion,
            },
            'maxResults': <String, Object?>{
              'type': 'integer',
              'minimum': 1,
              'maximum': 32,
              'default': 8,
            },
          },
        },
      };

  Map<String, Object?> capabilityMetadata() {
    final loaded = specIndex != null;
    return <String, Object?>{
      'server': 'relgeo-mcp',
      'mode': 'read-only desktop preview',
      'sourceOfTruth': 'spec/id',
      'tools': listTools().map((tool) => tool['name']).toList(growable: false),
      'resources': <String>[
        if (loaded) ...relGeoSpecRetrievalResourceUris,
        'relgeo://document/active',
        'relgeo://document/active/diagnostics',
      ],
      'specSnapshot': loaded ? specIndex!.snapshot.toJson() : null,
      'specCoverage': loaded ? 'full spec/id Markdown snapshot' : 'unavailable',
      'limitations': <String>[
        'Cannot create or edit drawings.',
        if (!loaded)
          'Full-spec retrieval is unavailable until the host supplies a pinned local Markdown snapshot.',
        'Examples remain illustrative and are not normative rules.',
      ],
    };
  }

  Future<Map<String, Object?>> call(String name, Object? rawArguments) async {
    switch (name) {
      case 'relgeo_search_spec':
        final index = specIndex;
        if (index == null) throw _specIndexUnavailable(name);
        try {
          return index.search(_searchSpec(rawArguments)).toJson();
        } on SpecVersionMismatchException catch (error) {
          throw _versionMismatch(error);
        }
      case 'relgeo_get_spec_section':
        final index = specIndex;
        if (index == null) throw _specIndexUnavailable(name);
        try {
          return index.getSection(_getSpecSection(rawArguments)).toJson();
        } on SpecSectionNotFoundException catch (error) {
          throw _sectionNotFound(error);
        } on SpecVersionMismatchException catch (error) {
          throw _versionMismatch(error);
        }
      case 'relgeo_get_capabilities':
        _requireNoArguments(rawArguments, name);
        return capabilityMetadata();
      case 'relgeo_find_syntax':
        if (specIndex != null) {
          try {
            return specIndex!.search(_searchSpec(rawArguments)).toJson();
          } on SpecVersionMismatchException catch (error) {
            throw _versionMismatch(error);
          }
        }
        return (await _requireHandlers(name).findSyntax(
          _findSyntax(rawArguments),
        )).toJson();
      case 'relgeo_get_syntax_rule':
        return (await _requireHandlers(name).getSyntaxRule(
          _getSyntaxRule(rawArguments),
        )).toJson();
      case 'relgeo_get_examples':
        return (await _requireHandlers(name).getExamples(
          _getExamples(rawArguments),
        )).toJson();
      case 'relgeo_complete_source':
        return (await _requireHandlers(name).completeSource(
          _completeSource(rawArguments),
        )).toJson();
      case 'relgeo_validate_source':
        return (await _requireHandlers(name).validateSource(
          _validateSource(rawArguments),
        )).toJson();
      case 'relgeo_explain_diagnostic':
        return (await _requireHandlers(name).explainDiagnostic(
          _explainDiagnostic(rawArguments),
        )).toJson();
      case 'relgeo_render_source':
        return (await _requireHandlers(name).renderSource(
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

  static McpDispatchException _specIndexUnavailable(String tool) =>
      McpDispatchException(
        -32001,
        'Full RelGeo spec snapshot is unavailable for $tool',
        data: <String, Object?>{
          'tool': tool,
          'sourceOfTruth': 'spec/id',
          'required': 'pinned local Markdown snapshot',
        },
      );

  RelGeoMcpToolHandlers _requireHandlers(String tool) {
    final value = handlers;
    if (value != null) return value;
    throw McpDispatchException(
      -32001,
      'RelGeo tool implementation is unavailable for $tool',
    );
  }

  static McpDispatchException _versionMismatch(
    SpecVersionMismatchException error,
  ) => McpDispatchException(
    -32602,
    error.toString(),
    data: <String, Object?>{
      'requestedSpecVersion': error.requested,
      'availableSpecVersion': error.available,
    },
  );

  static McpDispatchException _sectionNotFound(
    SpecSectionNotFoundException error,
  ) => McpDispatchException(
    -32004,
    error.toString(),
    data: <String, Object?>{'sectionId': error.sectionId},
  );

  static void _requireNoArguments(Object? raw, String tool) {
    if (raw is! Map || raw.isEmpty) return;
    throw McpDispatchException(-32602, '$tool does not accept arguments');
  }

  static SearchSpecInput _searchSpec(Object? raw) {
    final args = _arguments(raw, 'relgeo_search_spec');
    _rejectUnknown(args, const <String>{'query', 'specVersion', 'maxResults'});
    final query = _requiredString(args, 'query');
    if (query.length > 512) {
      throw const McpDispatchException(
        -32602,
        'query exceeds the 512 character limit',
      );
    }
    return SearchSpecInput(
      query: query,
      specVersion: _optionalVersion(args),
      maxResults: _optionalInt(args, 'maxResults', 8, 1, 32),
    );
  }

  static GetSpecSectionInput _getSpecSection(Object? raw) {
    final args = _arguments(raw, 'relgeo_get_spec_section');
    _rejectUnknown(args, const <String>{'sectionId', 'specVersion'});
    final value = _requiredString(args, 'sectionId');
    late final SpecSectionId sectionId;
    try {
      sectionId = SpecSectionId.parse(value);
    } on FormatException catch (error) {
      throw McpDispatchException(-32602, error.message);
    }
    return GetSpecSectionInput(
      sectionId: sectionId,
      specVersion: _optionalVersion(args),
    );
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
  RelGeoMcpJsonRpcRouter({
    this.dispatcher,
    this.activeBridge,
    required this.resources,
  });

  static const protocolVersion = '2025-11-25';
  static const supportedProtocolVersions = <String>[
    protocolVersion,
    '2025-06-18',
  ];

  final RelGeoMcpToolDispatcher? dispatcher;
  final RelGeoAgentBridge? activeBridge;
  final RelGeoMcpResourceStore resources;
  bool _initialized = false;
  String? _negotiatedProtocolVersion;

  bool get initialized => _initialized;
  String? get negotiatedProtocolVersion => _negotiatedProtocolVersion;

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
      if (requested is String &&
          !supportedProtocolVersions.contains(requested)) {
        return _response(
          hasId,
          id,
          error: McpDispatchException(
            -32602,
            'Unsupported protocol version',
            data: <String, Object?>{
              'supported': supportedProtocolVersions,
              'requested': requested,
            },
          ),
        );
      }
      _negotiatedProtocolVersion = requested is String
          ? requested
          : protocolVersion;
      return _response(
        hasId,
        id,
        result: <String, Object?>{
          'protocolVersion': _negotiatedProtocolVersion!,
          if (activeBridge != null)
            'instructions':
                'RelGeo MCP is a read-only desktop preview. For syntax and how-to questions, use the full local spec search when its snapshot is loaded, then retrieve the complete section before answering. Treat spec results as normative. You may then call relgeo_get_examples for an illustrative snippet, clearly labeled as an example. Use relgeo_get_active_document to inspect the open document. It cannot create or edit drawings.',
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
          final toolDispatcher = dispatcher;
          final exposeDesktopExamples = activeBridge != null &&
              (toolDispatcher == null || toolDispatcher.handlers == null);
          return _response(
            hasId,
            id,
            result: <String, Object?>{
              'tools': toolDispatcher == null
                  ? (activeBridge == null
                        ? const <Object?>[]
                        : <Map<String, Object?>>[
                            _capabilitiesTool,
                            _findSyntaxTool,
                            _getSyntaxRuleTool,
                            _examplesTool,
                            ..._activeDocumentTools,
                          ])
                  : <Map<String, Object?>>[
                      ...toolDispatcher.listTools(),
                      if (exposeDesktopExamples) _examplesTool,
                      if (activeBridge != null) ..._activeDocumentTools,
                    ],
            },
          );
        case 'tools/call':
          final toolDispatcher = dispatcher;
          if (toolDispatcher == null && activeBridge == null) {
            throw const McpDispatchException(
              -32601,
              'No RelGeo tools are enabled by this server',
            );
          }
          final params = _requiredParams(message, hasId, id);
          final name = params['name'];
          if (name is! String || name.isEmpty) {
            throw const McpDispatchException(
              -32602,
              'tools/call requires a non-empty name',
            );
          }
          late final Map<String, Object?> output;
          if (toolDispatcher == null && name == 'relgeo_get_capabilities') {
            _requireNoArguments(params['arguments'], 'relgeo_get_capabilities');
            output = _capabilities;
          } else if (toolDispatcher == null &&
              name == 'relgeo_find_syntax' &&
              activeBridge != null) {
            output = _findDesktopSyntax(params['arguments']);
          } else if (toolDispatcher == null &&
              name == 'relgeo_get_syntax_rule' &&
              activeBridge != null) {
            output = _getDesktopSyntaxRule(params['arguments']);
          } else if (toolDispatcher == null &&
              name == 'relgeo_get_examples' &&
              activeBridge != null) {
            output = _getDesktopExamples(params['arguments']);
          } else if (name == 'relgeo_get_examples' &&
              activeBridge != null &&
              (toolDispatcher == null || toolDispatcher.handlers == null)) {
            output = _getDesktopExamples(params['arguments']);
          } else if (name == 'relgeo_get_capabilities' &&
              toolDispatcher != null) {
            final metadata = toolDispatcher.capabilityMetadata();
            if (toolDispatcher.handlers == null && activeBridge != null) {
              final toolNames = <Object?>[
                ...(metadata['tools'] as List<Object?>),
                'relgeo_get_examples',
              ];
              output = <String, Object?>{
                ...metadata,
                'tools': toolNames,
              };
            } else {
              output = metadata;
            }
          } else if (name == 'relgeo_get_active_document' &&
              activeBridge != null) {
            _requireNoArguments(
              params['arguments'],
              'relgeo_get_active_document',
            );
            final bridge = activeBridge!;
            final snapshot = await bridge.getActiveDocument();
            if (snapshot == null) {
              throw const McpDispatchException(
                -32001,
                'No active document session is connected',
              );
            }
            output = snapshot.toJson();
          } else if (toolDispatcher != null) {
            output = await toolDispatcher.call(name, params['arguments']);
          } else {
            _requireNoArguments(
              params['arguments'],
              'relgeo_get_active_document',
            );
            if (name != 'relgeo_get_active_document') {
              throw McpDispatchException(
                -32601,
                'Unknown RelGeo tool: $name',
                data: <String, Object?>{'name': name},
              );
            }
            final snapshot = await activeBridge!.getActiveDocument();
            if (snapshot == null) {
              throw const McpDispatchException(
                -32001,
                'No active document session is connected',
              );
            }
            output = snapshot.toJson();
          }
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
            result: <String, Object?>{
              'resources': resources.listResources(includeUnavailable: false),
            },
          );
        case 'resources/templates/list':
          return _response(
            hasId,
            id,
            result: <String, Object?>{
              'resourceTemplates': resources.listResourceTemplates(),
            },
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

  static const List<Map<String, Object?>>
  _activeDocumentTools = <Map<String, Object?>>[
    <String, Object?>{
      'name': 'relgeo_get_active_document',
      'description':
          'Read the active RelGeo source, identity, revision, and dirty state. This tool never changes the document.',
      'inputSchema': <String, Object?>{
        'type': 'object',
        'additionalProperties': false,
        'properties': <String, Object?>{},
      },
    },
  ];

  static const Map<String, Object?> _capabilities = <String, Object?>{
    'server': 'relgeo-mcp',
    'mode': 'read-only desktop preview',
    'tools': <Map<String, String>>[
      <String, String>{
        'name': 'relgeo_get_capabilities',
        'description': 'Report the tools, resources, and current limitations.',
      },
      <String, String>{
        'name': 'relgeo_find_syntax',
        'description': 'Find matching normative rules in the RelGeo spec.',
      },
      <String, String>{
        'name': 'relgeo_get_syntax_rule',
        'description': 'Read a normative rule from the RelGeo spec.',
      },
      <String, String>{
        'name': 'relgeo_get_examples',
        'description': 'Provide secondary, illustrative shape examples.',
      },
      <String, String>{
        'name': 'relgeo_get_active_document',
        'description':
            'Read the active source, identity, revision, and dirty state.',
      },
    ],
    'resources': <String>[
      'relgeo://document/active',
      'relgeo://document/active/diagnostics',
    ],
    'limitations': <String>[
      'Cannot create or edit drawings.',
      'Full-spec search requires a pinned local Markdown snapshot supplied by the host.',
      'Includes beginner examples for a square and rectangle as illustrations, not as normative rules.',
      'Does not provide standalone validation or rendering.',
      'Can read only the active desktop document and its diagnostics.',
    ],
  };

  static const Map<String, Object?> _capabilitiesTool = <String, Object?>{
    'name': 'relgeo_get_capabilities',
    'description':
        'Use this tool when asked what RelGeo MCP can do. It reports available tools, resources, and limitations.',
    'inputSchema': <String, Object?>{
      'type': 'object',
      'additionalProperties': false,
      'properties': <String, Object?>{},
    },
  };

  static const Map<String, Object?> _findSyntaxTool = <String, Object?>{
    'name': 'relgeo_find_syntax',
    'description':
        'Search the pinned local RelGeo specification before giving syntax guidance. The result is unavailable until the host supplies the full snapshot.',
    'inputSchema': <String, Object?>{
      'type': 'object',
      'additionalProperties': false,
      'required': <String>['query'],
      'properties': <String, Object?>{
        'query': <String, Object?>{'type': 'string', 'minLength': 1},
        'specVersion': <String, Object?>{
          'type': 'string',
          'default': relGeoMvpSpecVersion,
        },
        'maxResults': <String, Object?>{
          'type': 'integer',
          'minimum': 1,
          'maximum': 32,
          'default': 8,
        },
      },
    },
  };

  static const Map<String, Object?> _getSyntaxRuleTool = <String, Object?>{
    'name': 'relgeo_get_syntax_rule',
    'description':
        'Read a currently indexed versioned normative rule from the RelGeo specification. Prefer this rule over examples when explaining valid syntax.',
    'inputSchema': <String, Object?>{
      'type': 'object',
      'additionalProperties': false,
      'required': <String>['ruleId'],
      'properties': <String, Object?>{
        'ruleId': <String, Object?>{'type': 'string', 'minLength': 1},
        'specVersion': <String, Object?>{
          'type': 'string',
          'default': relGeoMvpSpecVersion,
        },
      },
    },
  };

  static const Map<String, Object?> _examplesTool = <String, Object?>{
    'name': 'relgeo_get_examples',
    'description':
        'Find a beginner-friendly, copyable RelGeo example for a natural-language shape request. Use this to answer how to draw basic shapes. It only provides guidance and does not change the active document.',
    'inputSchema': <String, Object?>{
      'type': 'object',
      'additionalProperties': false,
      'anyOf': <Object?>[
        <String, Object?>{
          'required': <String>['query'],
        },
        <String, Object?>{
          'required': <String>['exampleId'],
        },
      ],
      'properties': <String, Object?>{
        'query': <String, Object?>{'type': 'string', 'minLength': 1},
        'exampleId': <String, Object?>{'type': 'string', 'minLength': 1},
        'specVersion': <String, Object?>{
          'type': 'string',
          'default': relGeoMvpSpecVersion,
        },
        'maxResults': <String, Object?>{
          'type': 'integer',
          'minimum': 1,
          'maximum': 24,
          'default': 6,
        },
      },
    },
  };

  static final List<ExampleResult> _desktopExamples = <ExampleResult>[
    ExampleResult(
      exampleId: 'square-basic',
      title: 'Persegi sederhana',
      description:
          'Gunakan type: rect dengan lebar dan tinggi sama. Ukuran mengikuti unit scene (mm pada contoh ini).',
      source: '''version: 0.5
scene:
  unit: mm
  padding: 10
  autoSize: true

objects:
  persegi:
    type: rect
    size: [50, 50]
    place:
      topLeft: [0, 0]
''',
      provenance: const McpProvenance(
        source: McpProvenanceSource.example,
        sourceUrl:
            'https://github.com/relgeo/workspace/blob/main/playground/src/assets/examples/basics/01_fundamentals.yaml',
        specVersion: relGeoMvpSpecVersion,
        revision: 'v0.5',
      ),
    ),
    ExampleResult(
      exampleId: 'rectangle-basic',
      title: 'Persegi panjang sederhana',
      description:
          'Gunakan type: rect; pasangan size berisi lebar lalu tinggi dalam unit scene.',
      source: '''version: 0.5
scene:
  unit: mm
  padding: 10
  autoSize: true

objects:
  persegi_panjang:
    type: rect
    size: [80, 50]
    place:
      topLeft: [0, 0]
''',
      provenance: const McpProvenance(
        source: McpProvenanceSource.example,
        sourceUrl:
            'https://github.com/relgeo/workspace/blob/main/playground/src/assets/examples/basics/01_fundamentals.yaml',
        specVersion: relGeoMvpSpecVersion,
        revision: 'v0.5',
      ),
    ),
  ];

  static Map<String, Object?> _getDesktopExamples(Object? rawArguments) {
    if (rawArguments is! Map ||
        rawArguments.keys.any((key) => key is! String)) {
      throw const McpDispatchException(
        -32602,
        'relgeo_get_examples arguments must be an object',
      );
    }
    final arguments = Map<String, Object?>.from(
      rawArguments.cast<String, Object?>(),
    );
    const allowed = <String>{'query', 'exampleId', 'specVersion', 'maxResults'};
    final unknown = arguments.keys.where((key) => !allowed.contains(key));
    if (unknown.isNotEmpty) {
      throw McpDispatchException(
        -32602,
        'Unknown relgeo_get_examples argument: ${unknown.first}',
      );
    }
    final query = arguments['query'];
    final exampleId = arguments['exampleId'];
    if ((query != null && (query is! String || query.trim().isEmpty)) ||
        (exampleId != null &&
            (exampleId is! String || exampleId.trim().isEmpty)) ||
        (query == null && exampleId == null)) {
      throw const McpDispatchException(
        -32602,
        'relgeo_get_examples requires a non-empty query or exampleId',
      );
    }
    final specVersion = arguments['specVersion'];
    if (specVersion != null && specVersion != relGeoMvpSpecVersion) {
      throw McpDispatchException(
        -32602,
        'Desktop examples support RelGeo $relGeoMvpSpecVersion only',
      );
    }
    final rawMaxResults = arguments['maxResults'];
    if (rawMaxResults != null &&
        (rawMaxResults is! int || rawMaxResults < 1 || rawMaxResults > 24)) {
      throw const McpDispatchException(
        -32602,
        'maxResults must be an integer from 1 to 24',
      );
    }
    final normalizedQuery = query is String ? query.toLowerCase().trim() : null;
    final normalizedId = exampleId is String
        ? exampleId.toLowerCase().trim()
        : null;
    final matches = _desktopExamples
        .where((example) {
          if (normalizedId != null) return example.exampleId == normalizedId;
          final haystack =
              '${example.exampleId} ${example.title} ${example.description}'
                  .toLowerCase();
          final aliases = <String, List<String>>{
            'square-basic': <String>['square', 'persegi', 'kotak'],
            'rectangle-basic': <String>[
              'rectangle',
              'persegi panjang',
              'kotak',
              'rect',
            ],
          }[example.exampleId]!;
          return haystack.contains(normalizedQuery!) ||
              aliases.any(normalizedQuery.contains);
        })
        .take(rawMaxResults as int? ?? 6)
        .toList(growable: false);
    return ExamplesResult(examples: matches).toJson();
  }

  static Map<String, Object?> _findDesktopSyntax(Object? rawArguments) {
    final arguments = _desktopArguments(rawArguments, 'relgeo_find_syntax');
    _rejectDesktopArguments(arguments, const <String>{
      'query',
      'specVersion',
      'maxResults',
    }, 'relgeo_find_syntax');
    final query = arguments['query'];
    if (query is! String || query.trim().isEmpty) {
      throw const McpDispatchException(
        -32602,
        'relgeo_find_syntax requires a non-empty query',
      );
    }
    _requireDesktopSpecVersion(arguments['specVersion']);
    final maxResults = arguments['maxResults'] ?? 8;
    if (maxResults is! int || maxResults < 1 || maxResults > 32) {
      throw const McpDispatchException(
        -32602,
        'maxResults must be an integer from 1 to 32',
      );
    }
    // The legacy desktop-only route has no corpus owner. It must not invent a
    // rule from a hardcoded preview; hosts with a snapshot use SpecSectionIndex
    // through RelGeoMcpToolDispatcher instead.
    return FindSyntaxResult(
      query: query,
      matches: const <SyntaxMatch>[],
    ).toJson();
  }

  static Map<String, Object?> _getDesktopSyntaxRule(Object? rawArguments) {
    final arguments = _desktopArguments(rawArguments, 'relgeo_get_syntax_rule');
    _rejectDesktopArguments(arguments, const <String>{
      'ruleId',
      'specVersion',
    }, 'relgeo_get_syntax_rule');
    final ruleId = arguments['ruleId'];
    if (ruleId is! String || ruleId.trim().isEmpty) {
      throw const McpDispatchException(
        -32602,
        'relgeo_get_syntax_rule requires a non-empty ruleId',
      );
    }
    _requireDesktopSpecVersion(arguments['specVersion']);
    throw McpDispatchException(
      -32601,
      'No desktop syntax rule is available until the full spec snapshot is loaded',
      data: <String, Object?>{'ruleId': ruleId},
    );
  }

  static Map<String, Object?> _desktopArguments(
    Object? rawArguments,
    String toolName,
  ) {
    if (rawArguments is! Map ||
        rawArguments.keys.any((key) => key is! String)) {
      throw McpDispatchException(
        -32602,
        '$toolName arguments must be an object',
      );
    }
    return Map<String, Object?>.from(rawArguments.cast<String, Object?>());
  }

  static void _rejectDesktopArguments(
    Map<String, Object?> arguments,
    Set<String> allowed,
    String toolName,
  ) {
    final unknown = arguments.keys.where((key) => !allowed.contains(key));
    if (unknown.isNotEmpty) {
      throw McpDispatchException(
        -32602,
        'Unknown $toolName argument: ${unknown.first}',
      );
    }
  }

  static void _requireDesktopSpecVersion(Object? specVersion) {
    if (specVersion != null && specVersion != relGeoMvpSpecVersion) {
      throw McpDispatchException(
        -32602,
        'Desktop syntax guidance supports RelGeo $relGeoMvpSpecVersion only',
      );
    }
  }

  static void _requireNoArguments(Object? value, String toolName) {
    if (value != null && (value is! Map || value.isNotEmpty)) {
      throw McpDispatchException(-32602, '$toolName accepts no arguments');
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
