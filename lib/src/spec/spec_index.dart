import 'dart:convert';

import '../contract/mcp_schema.dart';

/// A Markdown document supplied by the host. The MCP package receives bytes
/// through this boundary; it never opens a repository path or reads an asset
/// itself.
class SpecMarkdownDocument {
  const SpecMarkdownDocument({
    required this.relativePath,
    required this.content,
    this.status,
  }) : assert(relativePath != ''),
       assert(content != '');

  final String relativePath;
  final String content;
  final SpecDocumentStatus? status;
}

/// A lookup miss is explicit so an adapter can map it to a protocol not-found
/// error without fabricating a section or falling back to a hardcoded rule.
class SpecSectionNotFoundException implements Exception {
  const SpecSectionNotFoundException(this.sectionId);

  final String sectionId;

  @override
  String toString() => 'Spec section not found: $sectionId';
}

/// The requested version does not match the pinned snapshot supplied by the
/// host. The adapter maps this to an explicit invalid-params response rather
/// than silently answering from a different compatibility line.
class SpecVersionMismatchException implements Exception {
  const SpecVersionMismatchException({
    required this.requested,
    required this.available,
  });

  final String requested;
  final String available;

  @override
  String toString() =>
      'Spec version mismatch: requested $requested, available $available';
}

/// Bounds shared by the pure-Dart index. Full section retrieval remains
/// complete, but pathological sections are rejected instead of becoming an
/// unbounded MCP response.
class SpecIndexBounds {
  const SpecIndexBounds._();

  static const int maxSnippetCodeUnits = 320;
  static const int maxSectionCodeUnits = 64 * 1024;
  static const int maxDocuments = 512;
}

class _Heading {
  const _Heading({
    required this.level,
    required this.title,
    required this.line,
  });

  final int level;
  final String title;
  final int line;
}

/// A complete local Markdown section index with deterministic lexical search.
class SpecSectionIndex {
  SpecSectionIndex._({
    required this.snapshot,
    required List<SpecSection> sections,
  }) : _sections = List<SpecSection>.unmodifiable(sections),
       _byId = <String, SpecSection>{
         for (final section in sections) section.id.value: section,
       };

  factory SpecSectionIndex.fromDocuments({
    required SpecSnapshotMetadata snapshot,
    required List<SpecMarkdownDocument> documents,
  }) {
    if (documents.length > SpecIndexBounds.maxDocuments) {
      throw ArgumentError.value(
        documents.length,
        'documents',
        'exceeds ${SpecIndexBounds.maxDocuments}',
      );
    }
    final sortedDocuments = List<SpecMarkdownDocument>.of(documents)
      ..sort((a, b) => a.relativePath.compareTo(b.relativePath));
    final sections = <SpecSection>[];
    for (final document in sortedDocuments) {
      _validateDocumentPath(document.relativePath);
      sections.addAll(_parseDocument(document, snapshot));
    }
    sections.sort((a, b) => a.id.value.compareTo(b.id.value));
    return SpecSectionIndex._(snapshot: snapshot, sections: sections);
  }

  final SpecSnapshotMetadata snapshot;
  final List<SpecSection> _sections;
  final Map<String, SpecSection> _byId;

  List<SpecSection> get sections => _sections;

  SearchSpecResult search(SearchSpecInput input) {
    _requireVersion(input.specVersion);
    final query = _normalize(input.query);
    if (query.isEmpty) {
      return SearchSpecResult(
        query: input.query,
        matches: const <SearchSpecMatch>[],
        snapshot: snapshot,
      );
    }
    final terms = query.split(' ');
    final scored = <_ScoredSection>[];
    for (final section in _sections) {
      final score = _score(section, query, terms);
      if (score > 0) {
        scored.add(_ScoredSection(section: section, score: score));
      }
    }
    scored.sort((a, b) {
      final score = b.score.compareTo(a.score);
      if (score != 0) return score;
      final path = a.section.id.relativePath.compareTo(
        b.section.id.relativePath,
      );
      if (path != 0) return path;
      return a.section.id.value.compareTo(b.section.id.value);
    });
    final matches = scored
        .take(input.maxResults)
        .map(
          (item) => SearchSpecMatch(
            sectionId: item.section.id,
            title: item.section.title,
            parentHeadings: item.section.parentHeadings,
            snippet: _snippet(item.section, terms),
            score: item.score,
            provenance: item.section.provenance,
          ),
        )
        .toList(growable: false);
    return SearchSpecResult(
      query: input.query,
      matches: matches,
      snapshot: snapshot,
    );
  }

  GetSpecSectionResult getSection(GetSpecSectionInput input) {
    _requireVersion(input.specVersion);
    final section = _byId[input.sectionId.value];
    if (section == null) {
      throw SpecSectionNotFoundException(input.sectionId.value);
    }
    return GetSpecSectionResult(section: section, snapshot: snapshot);
  }

  /// Resource payload for `relgeo://spec/index`; it contains metadata and
  /// section descriptors only, never the complete corpus.
  Map<String, Object?> indexResourceJson() => <String, Object?>{
    'snapshot': snapshot.toJson(),
    'sections': _sections
        .map(
          (section) => <String, Object?>{
            'sectionId': section.id.value,
            'relativePath': section.id.relativePath,
            'anchor': section.id.anchor,
            'title': section.title,
            'parentHeadings': section.parentHeadings,
            'provenance': section.provenance.toJson(),
          },
        )
        .toList(growable: false),
  };

  String indexResourceText() => jsonEncode(indexResourceJson());

  Map<String, Object?> sectionResourceJson(String sectionId) {
    final input = GetSpecSectionInput(
      sectionId: SpecSectionId.parse(sectionId),
      specVersion: snapshot.specVersion,
    );
    return getSection(input).toJson();
  }

  String sectionResourceText(String sectionId) =>
      jsonEncode(sectionResourceJson(sectionId));

  void _requireVersion(String requested) {
    if (requested != snapshot.specVersion) {
      throw SpecVersionMismatchException(
        requested: requested,
        available: snapshot.specVersion,
      );
    }
  }

  static List<SpecSection> _parseDocument(
    SpecMarkdownDocument document,
    SpecSnapshotMetadata snapshot,
  ) {
    final lines = document.content.split('\n');
    final lineStarts = <int>[0];
    for (final line in lines) {
      lineStarts.add(lineStarts.last + line.length + 1);
    }
    final headings = <_Heading>[];
    var inFence = false;
    for (var line = 0; line < lines.length; line++) {
      final value = lines[line];
      final trimmed = value.trimLeft();
      if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
        inFence = !inFence;
        continue;
      }
      if (inFence) continue;
      final match = RegExp(r'^(#{1,6})[ \t]+(.+?)\s*#*\s*$').firstMatch(value);
      if (match == null) continue;
      final title = match.group(2)!.trim();
      if (title.isNotEmpty) {
        headings.add(
          _Heading(level: match.group(1)!.length, title: title, line: line),
        );
      }
    }
    final status = document.status ?? _statusFromContent(lines);
    final provenanceBase = SpecProvenance(
      status: status,
      sourceUrl:
          '${snapshot.sourceUrl}/${document.relativePath.replaceAll(' ', '%20')}',
      specVersion: snapshot.specVersion,
      revision: snapshot.revision,
      digest: snapshot.digest,
    );
    final seenAnchors = <String, int>{};
    final result = <SpecSection>[];
    for (var index = 0; index < headings.length; index++) {
      final heading = headings[index];
      final normalizedAnchor = _anchor(heading.title);
      final anchorBase = normalizedAnchor.isEmpty
          ? 'section-${heading.line + 1}'
          : normalizedAnchor;
      final occurrence = (seenAnchors[anchorBase] ?? 0) + 1;
      seenAnchors[anchorBase] = occurrence;
      final anchor = occurrence == 1 ? anchorBase : '$anchorBase-$occurrence';
      final end = _sectionEnd(headings, index, lines.length);
      final content = document.content.substring(
        lineStarts[heading.line],
        end < lines.length ? lineStarts[end] : document.content.length,
      );
      if (content.length > SpecIndexBounds.maxSectionCodeUnits) {
        throw ArgumentError(
          'Section exceeds ${SpecIndexBounds.maxSectionCodeUnits} code units: '
          '${document.relativePath}#$anchor',
        );
      }
      final parents = <String>[];
      var childLevel = heading.level;
      for (var previous = index - 1; previous >= 0; previous--) {
        final candidate = headings[previous];
        if (candidate.level < childLevel) {
          parents.insert(0, candidate.title);
          childLevel = candidate.level;
        }
      }
      result.add(
        SpecSection(
          id: SpecSectionId(
            relativePath: document.relativePath,
            anchor: anchor,
          ),
          title: heading.title,
          parentHeadings: parents,
          content: content,
          provenance: provenanceBase,
        ),
      );
    }
    return result;
  }

  static int _sectionEnd(List<_Heading> headings, int index, int lineCount) {
    final level = headings[index].level;
    for (var next = index + 1; next < headings.length; next++) {
      if (headings[next].level <= level) return headings[next].line;
    }
    return lineCount;
  }

  static SpecDocumentStatus _statusFromContent(List<String> lines) {
    for (final line in lines.take(24)) {
      final match = RegExp(
        r'^\s*Status dokumen:\s*`?([^`]+)`?',
        caseSensitive: false,
      ).firstMatch(line);
      if (match == null) continue;
      final value = match.group(1)!.trim().toLowerCase();
      if (value.startsWith('normative')) return SpecDocumentStatus.normative;
      if (value.startsWith('informative'))
        return SpecDocumentStatus.informative;
      if (value.startsWith('implementation')) {
        return SpecDocumentStatus.implementationNote;
      }
    }
    return SpecDocumentStatus.informative;
  }

  static String _anchor(String title) {
    final withoutPunctuation = title.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9\u0080-\uffff\s-]'),
      '',
    );
    return withoutPunctuation
        .trim()
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
  }

  static void _validateDocumentPath(String path) {
    final parts = path.split('/');
    if (path.isEmpty ||
        path.startsWith('/') ||
        !path.endsWith('.md') ||
        path.contains('\\') ||
        parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw FormatException('Invalid spec document path', path);
    }
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u0080-\uffff\s-]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static double _score(SpecSection section, String query, List<String> terms) {
    final title = _normalize(section.title);
    final parents = _normalize(section.parentHeadings.join(' '));
    final path = _normalize(section.id.relativePath);
    final content = _normalize(section.content);
    var score = 0.0;
    for (final term in terms) {
      if (title.contains(term)) score += 8;
      if (parents.contains(term)) score += 3;
      if (path.contains(term)) score += 4;
      if (content.contains(term)) score += 1;
    }
    if (title.contains(query)) score += 12;
    if (content.contains(query)) score += 5;
    return score;
  }

  static String _snippet(SpecSection section, List<String> terms) {
    final lines = section.content.split('\n');
    final normalizedTerms = terms.map(_normalize).toList();
    var selected = lines
        .firstWhere(
          (line) =>
              normalizedTerms.any((term) => _normalize(line).contains(term)),
          orElse: () => section.title,
        )
        .trim();
    if (selected.isEmpty) selected = section.title;
    if (selected.length <= SpecIndexBounds.maxSnippetCodeUnits) return selected;
    return '${selected.substring(0, SpecIndexBounds.maxSnippetCodeUnits - 1)}…';
  }
}

class _ScoredSection {
  const _ScoredSection({required this.section, required this.score});

  final SpecSection section;
  final double score;
}
