import 'session_bridge.dart';

/// The version of the RelGeo language contract used by the MVP tools.
const relGeoMvpSpecVersion = '0.5';

/// A source range expressed in the line/character coordinate system used by
/// language-service consumers. It is deliberately separate from [SourceRange],
/// whose offsets are UTF-16 code-unit offsets for document edits.
class TextPosition {
  const TextPosition({required this.line, required this.character})
    : assert(line >= 0),
      assert(character >= 0);

  final int line;
  final int character;

  Map<String, Object> toJson() => <String, Object>{
    'line': line,
    'character': character,
  };
}

class TextRange {
  const TextRange({required this.start, required this.end});

  final TextPosition start;
  final TextPosition end;

  Map<String, Object> toJson() => <String, Object>{
    'start': start.toJson(),
    'end': end.toJson(),
  };
}

/// Identifies which kind of source a tool is operating on. This prevents an
/// adapter from silently presenting a generated proposal as the active source.
enum SourceArtifactKind { input, proposal, activeDocument }

/// The provenance of a result or diagnostic. Only [spec] is normative.
enum McpProvenanceSource {
  spec,
  website,
  example,
  languageService,
  core,
  renderer,
  activeDocument,
}

class McpProvenance {
  const McpProvenance({
    required this.source,
    required this.sourceUrl,
    required this.specVersion,
    required this.revision,
  });

  final McpProvenanceSource source;
  final String sourceUrl;
  final String specVersion;
  final String revision;

  bool get isNormative => source == McpProvenanceSource.spec;

  Map<String, Object> toJson() => <String, Object>{
    'source': source.name,
    'sourceUrl': sourceUrl,
    'specVersion': specVersion,
    'revision': revision,
    'normative': isNormative,
  };
}

class SourceProposal {
  const SourceProposal({
    required this.source,
    required this.summary,
    this.rationale,
    this.basedOn = const <McpProvenance>[],
  });

  final String source;
  final String summary;
  final String? rationale;
  final List<McpProvenance> basedOn;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': SourceArtifactKind.proposal.name,
    'source': source,
    'summary': summary,
    'rationale': rationale,
    'basedOn': basedOn.map((item) => item.toJson()).toList(),
  };
}

class FindSyntaxInput {
  const FindSyntaxInput({
    required this.query,
    this.specVersion = relGeoMvpSpecVersion,
    this.maxResults = 8,
  }) : assert(query != ''),
       assert(maxResults > 0 && maxResults <= 32);

  final String query;
  final String specVersion;
  final int maxResults;

  Map<String, Object> toJson() => <String, Object>{
    'query': query,
    'specVersion': specVersion,
    'maxResults': maxResults,
  };
}

class GetSyntaxRuleInput {
  const GetSyntaxRuleInput({
    required this.ruleId,
    this.specVersion = relGeoMvpSpecVersion,
  }) : assert(ruleId != '');

  final String ruleId;
  final String specVersion;

  Map<String, Object> toJson() => <String, Object>{
    'ruleId': ruleId,
    'specVersion': specVersion,
  };
}

class GetExamplesInput {
  const GetExamplesInput({
    this.query,
    this.exampleId,
    this.specVersion = relGeoMvpSpecVersion,
    this.maxResults = 6,
  }) : assert(query != null || exampleId != null),
       assert(maxResults > 0 && maxResults <= 24);

  final String? query;
  final String? exampleId;
  final String specVersion;
  final int maxResults;

  Map<String, Object?> toJson() => <String, Object?>{
    'query': query,
    'exampleId': exampleId,
    'specVersion': specVersion,
    'maxResults': maxResults,
  };
}

class CompleteSourceInput {
  const CompleteSourceInput({
    required this.source,
    required this.position,
    this.specVersion = relGeoMvpSpecVersion,
    this.maxResults = 32,
  }) : assert(maxResults > 0 && maxResults <= 64);

  final String source;
  final TextPosition position;
  final String specVersion;
  final int maxResults;

  Map<String, Object> toJson() => <String, Object>{
    'source': source,
    'position': position.toJson(),
    'specVersion': specVersion,
    'maxResults': maxResults,
  };
}

class ValidateSourceInput {
  const ValidateSourceInput({
    required this.source,
    this.sourceKind = SourceArtifactKind.input,
    this.specVersion = relGeoMvpSpecVersion,
    this.includeInfo = false,
  });

  final String source;
  final SourceArtifactKind sourceKind;
  final String specVersion;
  final bool includeInfo;

  Map<String, Object> toJson() => <String, Object>{
    'source': source,
    'sourceKind': sourceKind.name,
    'specVersion': specVersion,
    'includeInfo': includeInfo,
  };
}

class ExplainDiagnosticInput {
  const ExplainDiagnosticInput({required this.code, this.message})
    : assert(code != '');

  final String code;
  final String? message;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'message': message,
  };
}

enum RenderFormat { svg }

class RenderSourceInput {
  const RenderSourceInput({
    required this.source,
    this.format = RenderFormat.svg,
    this.sheetId,
    this.specVersion = relGeoMvpSpecVersion,
  });

  final String source;
  final RenderFormat format;
  final String? sheetId;
  final String specVersion;

  Map<String, Object?> toJson() => <String, Object?>{
    'source': source,
    'format': format.name,
    'sheetId': sheetId,
    'specVersion': specVersion,
  };
}

class RelGeoDiagnostic {
  const RelGeoDiagnostic({
    required this.code,
    required this.message,
    required this.severity,
    required this.origin,
    this.range,
    this.provenance,
  });

  final String code;
  final String message;
  final DiagnosticSeverity severity;
  final TextRange? range;
  final McpProvenanceSource origin;
  final McpProvenance? provenance;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'message': message,
    'severity': severity.name,
    'range': range?.toJson(),
    'origin': origin.name,
    'provenance': provenance?.toJson(),
  };
}

class SyntaxMatch {
  const SyntaxMatch({
    required this.ruleId,
    required this.title,
    required this.summary,
    required this.provenance,
  });

  final String ruleId;
  final String title;
  final String summary;
  final McpProvenance provenance;

  Map<String, Object> toJson() => <String, Object>{
    'ruleId': ruleId,
    'title': title,
    'summary': summary,
    'provenance': provenance.toJson(),
  };
}

class FindSyntaxResult {
  const FindSyntaxResult({required this.query, required this.matches});

  final String query;
  final List<SyntaxMatch> matches;

  Map<String, Object> toJson() => <String, Object>{
    'query': query,
    'matches': matches.map((item) => item.toJson()).toList(),
  };
}

class SyntaxRuleResult {
  const SyntaxRuleResult({required this.documentation});

  final DocumentationResult documentation;

  Map<String, Object> toJson() => <String, Object>{
    'documentation': documentation.toJson(),
    'normative': documentation.provenance.isNormative,
  };
}

class ExampleResult {
  const ExampleResult({
    required this.exampleId,
    required this.title,
    required this.source,
    required this.provenance,
    this.description,
  });

  final String exampleId;
  final String title;
  final String source;
  final String? description;
  final McpProvenance provenance;

  Map<String, Object?> toJson() => <String, Object?>{
    'exampleId': exampleId,
    'title': title,
    'source': source,
    'description': description,
    'provenance': provenance.toJson(),
  };
}

class ExamplesResult {
  const ExamplesResult({required this.examples});

  final List<ExampleResult> examples;

  Map<String, Object> toJson() => <String, Object>{
    'examples': examples.map((item) => item.toJson()).toList(),
  };
}

class CompletionProposal {
  const CompletionProposal({
    required this.label,
    required this.insertText,
    required this.kind,
    this.detail,
    this.documentation,
    this.replacementRange,
  });

  final String label;
  final String insertText;
  final String kind;
  final String? detail;
  final String? documentation;
  final TextRange? replacementRange;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'completion-proposal',
    'label': label,
    'insertText': insertText,
    'completionKind': kind,
    'detail': detail,
    'documentation': documentation,
    'replacementRange': replacementRange?.toJson(),
  };
}

class CompletionResult {
  const CompletionResult({required this.items});

  final List<CompletionProposal> items;

  Map<String, Object> toJson() => <String, Object>{
    'items': items.map((item) => item.toJson()).toList(),
  };
}

class ValidationResult {
  const ValidationResult({
    required this.source,
    required this.sourceKind,
    required this.valid,
    required this.specVersion,
    required this.diagnostics,
    required this.provenance,
  });

  final String source;
  final SourceArtifactKind sourceKind;
  final bool valid;
  final String specVersion;
  final List<RelGeoDiagnostic> diagnostics;
  final McpProvenance provenance;

  Map<String, Object> toJson() => <String, Object>{
    'source': source,
    'sourceKind': sourceKind.name,
    'valid': valid,
    'specVersion': specVersion,
    'diagnostics': diagnostics.map((item) => item.toJson()).toList(),
    'provenance': provenance.toJson(),
  };
}

class DiagnosticExplanationResult {
  const DiagnosticExplanationResult({required this.documentation});

  final DocumentationResult documentation;

  Map<String, Object> toJson() => <String, Object>{
    'documentation': documentation.toJson(),
  };
}

class RenderResult {
  const RenderResult({
    required this.format,
    required this.content,
    required this.provenance,
  });

  final RenderFormat format;
  final String content;
  final McpProvenance provenance;

  Map<String, Object> toJson() => <String, Object>{
    'format': format.name,
    'content': content,
    'provenance': provenance.toJson(),
  };
}

enum RelGeoResourceKind {
  specIndex,
  specRule,
  examplesIndex,
  example,
  diagnosticsCatalog,
  activeDocument,
  activeDiagnostics,
}

/// Canonical resource URI parser shared by transports. It never resolves a
/// file path, so resource access cannot become arbitrary filesystem access.
class RelGeoResourceUri {
  const RelGeoResourceUri._(this.kind, this.id);

  final RelGeoResourceKind kind;
  final String? id;

  factory RelGeoResourceUri.parse(String value) {
    final parsed = Uri.tryParse(value);
    if (parsed == null || parsed.scheme != 'relgeo' || parsed.query != '') {
      throw FormatException('Invalid RelGeo resource URI', value);
    }
    final segments = parsed.pathSegments;
    if (parsed.host == 'spec' && _matches(segments, ['index'])) {
      return const RelGeoResourceUri._(RelGeoResourceKind.specIndex, null);
    }
    if (parsed.host == 'spec' &&
        segments.length == 2 &&
        segments[0] == 'rules') {
      return RelGeoResourceUri._(RelGeoResourceKind.specRule, segments[1]);
    }
    if (parsed.host == 'examples' && _matches(segments, ['index'])) {
      return const RelGeoResourceUri._(RelGeoResourceKind.examplesIndex, null);
    }
    if (parsed.host == 'examples' && segments.length == 1) {
      return RelGeoResourceUri._(RelGeoResourceKind.example, segments[0]);
    }
    if (parsed.host == 'diagnostics' && _matches(segments, ['catalog'])) {
      return const RelGeoResourceUri._(
        RelGeoResourceKind.diagnosticsCatalog,
        null,
      );
    }
    if (parsed.host == 'document' && _matches(segments, ['active'])) {
      return const RelGeoResourceUri._(RelGeoResourceKind.activeDocument, null);
    }
    if (parsed.host == 'document' &&
        _matches(segments, ['active', 'diagnostics'])) {
      return const RelGeoResourceUri._(
        RelGeoResourceKind.activeDiagnostics,
        null,
      );
    }
    throw FormatException('Unsupported RelGeo resource URI', value);
  }

  factory RelGeoResourceUri.specIndex() =>
      const RelGeoResourceUri._(RelGeoResourceKind.specIndex, null);

  factory RelGeoResourceUri.specRule(String ruleId) =>
      RelGeoResourceUri._(RelGeoResourceKind.specRule, _requiredId(ruleId));

  factory RelGeoResourceUri.examplesIndex() =>
      const RelGeoResourceUri._(RelGeoResourceKind.examplesIndex, null);

  factory RelGeoResourceUri.example(String exampleId) =>
      RelGeoResourceUri._(RelGeoResourceKind.example, _requiredId(exampleId));

  factory RelGeoResourceUri.diagnosticsCatalog() =>
      const RelGeoResourceUri._(RelGeoResourceKind.diagnosticsCatalog, null);

  factory RelGeoResourceUri.activeDocument() =>
      const RelGeoResourceUri._(RelGeoResourceKind.activeDocument, null);

  factory RelGeoResourceUri.activeDiagnostics() =>
      const RelGeoResourceUri._(RelGeoResourceKind.activeDiagnostics, null);

  String get value {
    switch (kind) {
      case RelGeoResourceKind.specIndex:
        return 'relgeo://spec/index';
      case RelGeoResourceKind.specRule:
        return 'relgeo://spec/rules/${Uri.encodeComponent(id!)}';
      case RelGeoResourceKind.examplesIndex:
        return 'relgeo://examples/index';
      case RelGeoResourceKind.example:
        return 'relgeo://examples/${Uri.encodeComponent(id!)}';
      case RelGeoResourceKind.diagnosticsCatalog:
        return 'relgeo://diagnostics/catalog';
      case RelGeoResourceKind.activeDocument:
        return 'relgeo://document/active';
      case RelGeoResourceKind.activeDiagnostics:
        return 'relgeo://document/active/diagnostics';
    }
  }

  @override
  String toString() => value;

  static bool _matches(List<String> actual, List<String> expected) {
    if (actual.length != expected.length) return false;
    for (var index = 0; index < actual.length; index++) {
      if (actual[index] != expected[index]) return false;
    }
    return true;
  }

  static String _requiredId(String value) {
    if (value.isEmpty || value.contains('/')) {
      throw ArgumentError.value(value, 'id', 'must be a single URI segment');
    }
    return value;
  }
}

enum McpToolAccess { readOnly, readWrite }

class RelGeoToolContract {
  const RelGeoToolContract({
    required this.name,
    required this.description,
    required this.access,
    required this.inputType,
    required this.outputType,
    required this.inputSchema,
    this.requiresActiveDocument = false,
  });

  final String name;
  final String description;
  final McpToolAccess access;
  final String inputType;
  final String outputType;
  final Map<String, Object?> inputSchema;
  final bool requiresActiveDocument;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'description': description,
    'access': access.name,
    'inputType': inputType,
    'outputType': outputType,
    'inputSchema': inputSchema,
    'requiresActiveDocument': requiresActiveDocument,
  };
}

const relGeoMvpToolContracts = <RelGeoToolContract>[
  RelGeoToolContract(
    name: 'relgeo_find_syntax',
    description: 'Find normative RelGeo syntax rules for an authoring query.',
    access: McpToolAccess.readOnly,
    inputType: 'FindSyntaxInput',
    outputType: 'FindSyntaxResult',
    inputSchema: <String, Object?>{
      'type': 'object',
      'required': <String>['query'],
      'properties': <String, Object?>{
        'query': <String, Object?>{'type': 'string', 'minLength': 1},
        'specVersion': <String, Object?>{'type': 'string', 'default': '0.5'},
        'maxResults': <String, Object?>{
          'type': 'integer',
          'minimum': 1,
          'maximum': 32,
          'default': 8,
        },
      },
    },
  ),
  RelGeoToolContract(
    name: 'relgeo_get_syntax_rule',
    description: 'Read one normative rule from the versioned RelGeo spec.',
    access: McpToolAccess.readOnly,
    inputType: 'GetSyntaxRuleInput',
    outputType: 'SyntaxRuleResult',
    inputSchema: <String, Object?>{
      'type': 'object',
      'required': <String>['ruleId'],
      'properties': <String, Object?>{
        'ruleId': <String, Object?>{'type': 'string', 'minLength': 1},
        'specVersion': <String, Object?>{'type': 'string', 'default': '0.5'},
      },
    },
  ),
  RelGeoToolContract(
    name: 'relgeo_get_examples',
    description: 'Read versioned examples without treating them as normative.',
    access: McpToolAccess.readOnly,
    inputType: 'GetExamplesInput',
    outputType: 'ExamplesResult',
    inputSchema: <String, Object?>{
      'type': 'object',
      'anyOf': <Object?>[
        <String, Object?>{
          'required': <String>['query'],
        },
        <String, Object?>{
          'required': <String>['exampleId'],
        },
      ],
    },
  ),
  RelGeoToolContract(
    name: 'relgeo_complete_source',
    description: 'Return bounded completion proposals at one source position.',
    access: McpToolAccess.readOnly,
    inputType: 'CompleteSourceInput',
    outputType: 'CompletionResult',
    inputSchema: <String, Object?>{
      'type': 'object',
      'required': <String>['source', 'position'],
      'properties': <String, Object?>{
        'source': <String, Object?>{'type': 'string'},
        'position': <String, Object?>{
          'type': 'object',
          'required': <String>['line', 'character'],
        },
        'maxResults': <String, Object?>{
          'type': 'integer',
          'minimum': 1,
          'maximum': 64,
          'default': 32,
        },
      },
    },
  ),
  RelGeoToolContract(
    name: 'relgeo_validate_source',
    description: 'Parse and validate source using the shared core contract.',
    access: McpToolAccess.readOnly,
    inputType: 'ValidateSourceInput',
    outputType: 'ValidationResult',
    inputSchema: <String, Object?>{
      'type': 'object',
      'required': <String>['source'],
      'properties': <String, Object?>{
        'source': <String, Object?>{'type': 'string'},
        'sourceKind': <String, Object?>{
          'type': 'string',
          'enum': <String>['input', 'proposal', 'activeDocument'],
          'default': 'input',
        },
        'specVersion': <String, Object?>{'type': 'string', 'default': '0.5'},
        'includeInfo': <String, Object?>{'type': 'boolean', 'default': false},
      },
    },
  ),
  RelGeoToolContract(
    name: 'relgeo_explain_diagnostic',
    description: 'Explain a diagnostic using versioned documentation.',
    access: McpToolAccess.readOnly,
    inputType: 'ExplainDiagnosticInput',
    outputType: 'DiagnosticExplanationResult',
    inputSchema: <String, Object?>{
      'type': 'object',
      'required': <String>['code'],
      'properties': <String, Object?>{
        'code': <String, Object?>{'type': 'string', 'minLength': 1},
        'message': <String, Object?>{'type': 'string'},
      },
    },
  ),
  RelGeoToolContract(
    name: 'relgeo_render_source',
    description:
        'Render source to an in-memory SVG result; no file is written.',
    access: McpToolAccess.readOnly,
    inputType: 'RenderSourceInput',
    outputType: 'RenderResult',
    inputSchema: <String, Object?>{
      'type': 'object',
      'required': <String>['source'],
      'properties': <String, Object?>{
        'source': <String, Object?>{'type': 'string'},
        'format': <String, Object?>{
          'type': 'string',
          'enum': <String>['svg'],
          'default': 'svg',
        },
        'sheetId': <String, Object?>{'type': 'string'},
      },
    },
  ),
];

const relGeoMvpResourceUris = <String>[
  'relgeo://spec/index',
  'relgeo://spec/rules/{ruleId}',
  'relgeo://examples/index',
  'relgeo://examples/{exampleId}',
  'relgeo://diagnostics/catalog',
  'relgeo://document/active',
  'relgeo://document/active/diagnostics',
];
