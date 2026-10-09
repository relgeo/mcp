import 'dart:convert';
import 'dart:math';

/// The smallest source range understood by the session bridge.
///
/// Offsets use Dart string (UTF-16 code-unit) indices so the same range can be
/// applied without a parser or a filesystem. The MCP protocol adapter may add
/// line/column projections, but must retain these bounded offsets internally.
class SourceRange {
  const SourceRange({required this.start, required this.end})
    : assert(start >= 0),
      assert(end >= start);

  final int start;
  final int end;

  int get length => end - start;

  Map<String, Object> toJson() => <String, Object>{'start': start, 'end': end};
}

class DocumentDiagnostic {
  const DocumentDiagnostic({
    required this.code,
    required this.message,
    required this.severity,
    this.range,
  });

  final String code;
  final String message;
  final DiagnosticSeverity severity;
  final SourceRange? range;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'message': message,
    'severity': severity.name,
    'range': range?.toJson(),
  };
}

enum DiagnosticSeverity { error, warning, info }

enum DocumentationSource { spec, website, example }

/// Provenance attached to every future spec/example resource result.
class DocumentationProvenance {
  const DocumentationProvenance({
    required this.source,
    required this.sourceUrl,
    required this.specVersion,
    required this.revision,
    this.fetchedAt,
  });

  final DocumentationSource source;
  final String sourceUrl;
  final String specVersion;
  final String revision;
  final DateTime? fetchedAt;

  /// Website content may explain a rule, but never becomes the norm.
  bool get isNormative => source == DocumentationSource.spec;

  Map<String, Object?> toJson() => <String, Object?>{
    'source': source.name,
    'sourceUrl': sourceUrl,
    'specVersion': specVersion,
    'revision': revision,
    'fetchedAt': fetchedAt?.toUtc().toIso8601String(),
  };
}

class DocumentationResult {
  const DocumentationResult({
    required this.title,
    required this.content,
    required this.provenance,
  });

  final String title;
  final String content;
  final DocumentationProvenance provenance;

  DocumentationSource get source => provenance.source;
  String get sourceUrl => provenance.sourceUrl;
  String get specVersion => provenance.specVersion;
  String get revision => provenance.revision;

  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'content': content,
    'provenance': provenance.toJson(),
  };
}

/// A read-only view of the one document that a desktop bridge exposes.
class ActiveDocumentSnapshot {
  const ActiveDocumentSnapshot({
    required this.documentId,
    required this.name,
    required this.source,
    required this.revision,
    required this.dirty,
    this.path,
    this.diagnostics = const <DocumentDiagnostic>[],
  }) : assert(documentId != ''),
       assert(revision >= 0);

  final String documentId;
  final String name;
  final String? path;
  final String source;
  final int revision;
  final bool dirty;
  final List<DocumentDiagnostic> diagnostics;

  Map<String, Object?> toJson() => <String, Object?>{
    'documentId': documentId,
    'name': name,
    'path': path,
    'source': source,
    'revision': revision,
    'dirty': dirty,
    'diagnostics': diagnostics.map((item) => item.toJson()).toList(),
  };
}

class DocumentEdit {
  const DocumentEdit({required this.range, required this.replacement});

  final SourceRange range;
  final String replacement;

  Map<String, Object> toJson() => <String, Object>{
    'range': range.toJson(),
    'replacement': replacement,
  };
}

/// Limits prevent an agent call from becoming an unbounded document write.
class DocumentEditBounds {
  const DocumentEditBounds._();

  static const int maxEdits = 64;
  static const int maxReplacementCodeUnits = 16 * 1024;
  static const int maxTotalReplacementCodeUnits = 64 * 1024;
  static const int maxSourceCodeUnits = 1024 * 1024;
  static const int maxSummaryCodeUnits = 400;
  static const int maxRationaleCodeUnits = 2 * 1024;
}

class DocumentEditProposal {
  const DocumentEditProposal({
    required this.baseDocumentId,
    required this.baseRevision,
    required this.edits,
    required this.summary,
    this.rationale,
  }) : assert(baseDocumentId != ''),
       assert(baseRevision >= 0),
       assert(edits.length > 0),
       assert(summary != '');

  final String baseDocumentId;
  final int baseRevision;
  final List<DocumentEdit> edits;
  final String summary;
  final String? rationale;

  Map<String, Object?> toJson() => <String, Object?>{
    'baseDocumentId': baseDocumentId,
    'baseRevision': baseRevision,
    'edits': edits.map((item) => item.toJson()).toList(),
    'summary': summary,
    'rationale': rationale,
  };

  /// Returns all guard failures without touching the active document.
  List<String> validateAgainst(ActiveDocumentSnapshot snapshot) {
    final errors = <String>[];
    if (baseDocumentId != snapshot.documentId) {
      errors.add('baseDocumentId does not identify the active document');
    }
    if (baseRevision != snapshot.revision) {
      errors.add('baseRevision is stale');
    }
    if (snapshot.source.length > DocumentEditBounds.maxSourceCodeUnits) {
      errors.add('active source exceeds the MCP edit size bound');
    }
    if (edits.isEmpty) errors.add('at least one edit is required');
    if (edits.length > DocumentEditBounds.maxEdits) {
      errors.add('too many edits');
    }
    if (summary.isEmpty ||
        summary.length > DocumentEditBounds.maxSummaryCodeUnits) {
      errors.add('summary is empty or exceeds its size bound');
    }
    if (rationale != null &&
        rationale!.length > DocumentEditBounds.maxRationaleCodeUnits) {
      errors.add('rationale exceeds its size bound');
    }

    var totalReplacementLength = 0;
    final sorted = List<DocumentEdit>.of(edits)
      ..sort((a, b) => a.range.start.compareTo(b.range.start));
    SourceRange? previous;
    for (final edit in sorted) {
      final range = edit.range;
      if (range.start < 0 ||
          range.end < range.start ||
          range.end > snapshot.source.length) {
        errors.add('edit range is outside the active source');
      }
      if (previous != null && range.start < previous.end) {
        errors.add('edit ranges overlap');
      }
      previous = range;
      if (edit.replacement.length >
          DocumentEditBounds.maxReplacementCodeUnits) {
        errors.add('replacement exceeds its size bound');
      }
      totalReplacementLength += edit.replacement.length;
    }
    if (totalReplacementLength >
        DocumentEditBounds.maxTotalReplacementCodeUnits) {
      errors.add('total replacement exceeds its size bound');
    }
    return List<String>.unmodifiable(errors);
  }

  /// Applies only a proposal that has already passed [validateAgainst].
  String applyTo(ActiveDocumentSnapshot snapshot) {
    final errors = validateAgainst(snapshot);
    if (errors.isNotEmpty) {
      throw ArgumentError(
        'Cannot apply invalid proposal: ${errors.join('; ')}',
      );
    }
    final sorted = List<DocumentEdit>.of(edits)
      ..sort((a, b) => b.range.start.compareTo(a.range.start));
    var result = snapshot.source;
    for (final edit in sorted) {
      result = result.replaceRange(
        edit.range.start,
        edit.range.end,
        edit.replacement,
      );
    }
    return result;
  }
}

enum DocumentEditStatus { applied, stale, rejected, failed }

class DocumentEditResult {
  const DocumentEditResult({
    required this.status,
    this.newRevision,
    this.message,
    this.snapshot,
    this.diagnostics = const <DocumentDiagnostic>[],
  });

  const DocumentEditResult.applied({
    required int newRevision,
    ActiveDocumentSnapshot? snapshot,
    List<DocumentDiagnostic> diagnostics = const <DocumentDiagnostic>[],
  }) : this(
         status: DocumentEditStatus.applied,
         newRevision: newRevision,
         snapshot: snapshot,
         diagnostics: diagnostics,
       );

  const DocumentEditResult.stale({
    String? message,
    List<DocumentDiagnostic> diagnostics = const <DocumentDiagnostic>[],
  }) : this(
         status: DocumentEditStatus.stale,
         message: message,
         diagnostics: diagnostics,
       );

  const DocumentEditResult.rejected({
    String? message,
    List<DocumentDiagnostic> diagnostics = const <DocumentDiagnostic>[],
  }) : this(
         status: DocumentEditStatus.rejected,
         message: message,
         diagnostics: diagnostics,
       );

  const DocumentEditResult.failed({
    String? message,
    List<DocumentDiagnostic> diagnostics = const <DocumentDiagnostic>[],
  }) : this(
         status: DocumentEditStatus.failed,
         message: message,
         diagnostics: diagnostics,
       );

  final DocumentEditStatus status;
  final int? newRevision;
  final String? message;
  final ActiveDocumentSnapshot? snapshot;
  final List<DocumentDiagnostic> diagnostics;

  Map<String, Object?> toJson() => <String, Object?>{
    'status': status.name,
    'newRevision': newRevision,
    'message': message,
    'snapshot': snapshot?.toJson(),
    'diagnostics': diagnostics.map((item) => item.toJson()).toList(),
  };
}

/// Protocol-independent bridge owned by the host integration, not by widgets.
abstract interface class RelGeoAgentBridge {
  Future<ActiveDocumentSnapshot?> getActiveDocument();

  Future<List<DocumentDiagnostic>> getDiagnostics();

  Future<DocumentEditResult> applyDocumentEdit(DocumentEditProposal proposal);
}

enum McpPermission { readOnly, readWrite }

class McpSessionToken {
  const McpSessionToken({
    required this.value,
    required this.permission,
    required this.issuedAt,
    required this.expiresAt,
  });

  final String value;
  final McpPermission permission;
  final DateTime issuedAt;
  final DateTime expiresAt;

  bool isExpired(DateTime now) => !now.isBefore(expiresAt);
}

/// In-memory lifecycle model for one local MCP server instance.
///
/// The server must discard this store when it stops. Tokens are opaque to the
/// protocol adapter and are never persisted to a document or preferences.
class McpSessionTokenStore {
  McpSessionTokenStore({Random? random}) : _random = random ?? Random.secure();

  final Random _random;
  final Map<String, McpSessionToken> _tokens = <String, McpSessionToken>{};

  McpSessionToken issue({
    required McpPermission permission,
    Duration ttl = const Duration(minutes: 30),
    DateTime? now,
  }) {
    final issuedAt = now ?? DateTime.now().toUtc();
    if (ttl <= Duration.zero) throw ArgumentError.value(ttl, 'ttl');
    final value = _newValue();
    final token = McpSessionToken(
      value: value,
      permission: permission,
      issuedAt: issuedAt,
      expiresAt: issuedAt.add(ttl),
    );
    _tokens[value] = token;
    return token;
  }

  McpSessionToken? validate(
    String value, {
    required McpPermission requiredPermission,
    DateTime? now,
  }) {
    final token = _tokens[value];
    if (token == null) return null;
    final current = now ?? DateTime.now().toUtc();
    if (token.isExpired(current)) {
      _tokens.remove(value);
      return null;
    }
    if (requiredPermission == McpPermission.readWrite &&
        token.permission != McpPermission.readWrite) {
      return null;
    }
    return token;
  }

  bool revoke(String value) => _tokens.remove(value) != null;

  void revokeAll() => _tokens.clear();

  String _newValue() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

/// Security defaults for the desktop-connected server.
class McpSecurityPolicy {
  const McpSecurityPolicy({
    this.enabled = false,
    this.bindAddress = '127.0.0.1',
    this.allowRemoteClients = false,
    this.allowFilesystemWrites = false,
    this.allowAutosave = false,
  });

  final bool enabled;
  final String bindAddress;
  final bool allowRemoteClients;
  final bool allowFilesystemWrites;
  final bool allowAutosave;

  bool acceptsConnectionFrom(String address) =>
      !allowRemoteClients &&
      bindAddress == '127.0.0.1' &&
      address == '127.0.0.1';

  List<String> validate() {
    final errors = <String>[];
    if (bindAddress != '127.0.0.1') {
      errors.add('desktop MCP must bind to 127.0.0.1');
    }
    if (allowRemoteClients) errors.add('remote MCP is out of scope for MVP');
    if (allowFilesystemWrites) {
      errors.add('arbitrary filesystem writes are out of scope for MVP');
    }
    if (allowAutosave) errors.add('MCP direct apply must not autosave');
    return List<String>.unmodifiable(errors);
  }
}
