import 'package:relgeo_mcp/relgeo_mcp.dart';
import 'package:test/test.dart';

void main() {
  const specProvenance = McpProvenance(
    source: McpProvenanceSource.spec,
    sourceUrl: 'https://github.com/relgeo/spec/tree/main/id',
    specVersion: '0.5',
    revision: 'fixture-spec-rev',
  );

  test('typed inputs preserve input kind and bounded fields in JSON', () {
    const input = ValidateSourceInput(
      source: 'objects:\n  p1:\n    type: point\n',
      sourceKind: SourceArtifactKind.proposal,
    );

    expect(input.toJson(), <String, Object>{
      'source': input.source,
      'sourceKind': 'proposal',
      'specVersion': '0.5',
      'includeInfo': false,
    });
    expect(
      const SourceProposal(
        source: 'version: 0.5',
        summary: 'Use the active version',
        basedOn: <McpProvenance>[specProvenance],
      ).toJson()['kind'],
      'proposal',
    );
  });

  test(
    'validation result keeps diagnostics distinct from the input source',
    () {
      const diagnostic = RelGeoDiagnostic(
        code: 'RG001',
        message: 'Invalid object type',
        severity: DiagnosticSeverity.error,
        origin: McpProvenanceSource.languageService,
        range: TextRange(
          start: TextPosition(line: 1, character: 4),
          end: TextPosition(line: 1, character: 8),
        ),
        provenance: specProvenance,
      );
      const result = ValidationResult(
        source: 'objects: {}',
        sourceKind: SourceArtifactKind.input,
        valid: false,
        specVersion: '0.5',
        diagnostics: <RelGeoDiagnostic>[diagnostic],
        provenance: specProvenance,
      );

      final json = result.toJson();
      expect(json['sourceKind'], 'input');
      expect(json['valid'], isFalse);
      expect((json['diagnostics'] as List<Object?>).single, isA<Map>());
      expect(
        ((json['diagnostics'] as List<Object?>).single as Map)['origin'],
        'languageService',
      );
    },
  );

  test('resource URI parser accepts only canonical resources', () {
    final rule = RelGeoResourceUri.parse(
      'relgeo://spec/rules/14-geometry-objects',
    );
    expect(rule.kind, RelGeoResourceKind.specRule);
    expect(rule.id, '14-geometry-objects');
    expect(rule.toString(), 'relgeo://spec/rules/14-geometry-objects');
    expect(
      RelGeoResourceUri.activeDiagnostics().toString(),
      'relgeo://document/active/diagnostics',
    );
    expect(
      () => RelGeoResourceUri.parse('relgeo://spec/../../etc/passwd'),
      throwsFormatException,
    );
    expect(
      () => RelGeoResourceUri.parse('relgeo://document/other'),
      throwsFormatException,
    );
  });

  test('MVP catalog exposes typed read-only tools and resource templates', () {
    expect(relGeoMvpToolContracts, hasLength(7));
    expect(
      relGeoMvpToolContracts.every(
        (contract) => contract.access == McpToolAccess.readOnly,
      ),
      isTrue,
    );
    expect(
      relGeoMvpToolContracts.map((contract) => contract.name),
      containsAll(<String>[
        'relgeo_find_syntax',
        'relgeo_get_syntax_rule',
        'relgeo_get_examples',
        'relgeo_complete_source',
        'relgeo_validate_source',
        'relgeo_explain_diagnostic',
        'relgeo_render_source',
      ]),
    );
    expect(relGeoMvpResourceUris, contains('relgeo://document/active'));
    expect(relGeoMvpResourceUris, contains('relgeo://spec/rules/{ruleId}'));
  });

  test('advertised schemas match bounded DTO fields', () {
    final schemas = <String, Map<String, Object?>>{
      for (final contract in relGeoMvpToolContracts)
        contract.name: contract.inputSchema,
    };
    final examples = schemas['relgeo_get_examples']!;
    expect(examples['additionalProperties'], isFalse);
    expect(
      (examples['properties'] as Map<String, Object?>).keys,
      containsAll(<String>['query', 'exampleId', 'specVersion', 'maxResults']),
    );
    expect(
      ((schemas['relgeo_complete_source']!['properties']
              as Map<String, Object?>)['specVersion']
          as Map<String, Object?>)['minLength'],
      1,
    );
    expect(
      ((schemas['relgeo_render_source']!['properties']
              as Map<String, Object?>)['specVersion']
          as Map<String, Object?>)['default'],
      '0.5',
    );
  });

  test('website provenance cannot become normative', () {
    const website = McpProvenance(
      source: McpProvenanceSource.website,
      sourceUrl: 'https://relgeo.github.io/docs/language-spec',
      specVersion: '0.5',
      revision: 'site-rev',
    );
    expect(website.isNormative, isFalse);
    expect(specProvenance.isNormative, isTrue);
  });

  test('full-spec section IDs are stable, relative, and URI-safe', () {
    const id = SpecSectionId(
      relativePath: 'geometry/14-geometry-objects.md',
      anchor: '143-rect',
    );
    expect(id.value, 'geometry/14-geometry-objects.md#143-rect');
    expect(SpecSectionId.parse(id.value), id);
    expect(
      () => SpecSectionId.parse('../14-geometry-objects.md#143-rect'),
      throwsFormatException,
    );
    expect(
      () => SpecSectionId.parse('geometry/14-geometry-objects.md#bad anchor'),
      throwsFormatException,
    );

    final uri = RelGeoResourceUri.specSection(id.value);
    expect(uri.kind, RelGeoResourceKind.specSection);
    expect(RelGeoResourceUri.parse(uri.value).id, id.value);
  });

  test('full-spec provenance distinguishes normative and informative source', () {
    const snapshot = SpecSnapshotMetadata(
      specVersion: '0.5',
      revision: 'spec-main-2026-10-30',
      digest: 'sha256:fixture',
      sourceUrl: 'https://github.com/relgeo/spec/tree/main/id',
      fileCount: 34,
    );
    const normative = SpecProvenance(
      status: SpecDocumentStatus.normative,
      sourceUrl:
          'https://github.com/relgeo/spec/blob/main/id/geometry/14-geometry-objects.md#143-rect',
      specVersion: '0.5',
      revision: 'spec-main-2026-10-30',
      digest: 'sha256:fixture',
    );
    const informative = SpecProvenance(
      status: SpecDocumentStatus.informative,
      sourceUrl: 'https://github.com/relgeo/spec/blob/main/id/README.md',
      specVersion: '0.5',
      revision: 'spec-main-2026-10-30',
      digest: 'sha256:fixture',
    );

    expect(normative.isNormative, isTrue);
    expect(informative.isNormative, isFalse);
    expect(normative.toJson()['status'], 'normative');
    expect(informative.toJson()['normative'], isFalse);
    expect(snapshot.toJson(), containsPair('digest', 'sha256:fixture'));
    expect(snapshot.toJson(), containsPair('fileCount', 34));
  });

  test(
    'full-spec search contract preserves bounds, parent headings, and no-result behavior',
    () {
      const input = SearchSpecInput(
        query: 'parameters constants',
        maxResults: 12,
      );
      expect(input.toJson(), <String, Object>{
        'query': 'parameters constants',
        'specVersion': '0.5',
        'maxResults': 12,
      });

      const provenance = SpecProvenance(
        status: SpecDocumentStatus.normative,
        sourceUrl:
            'https://github.com/relgeo/spec/blob/main/id/syntax/08-parameters.md#8-parameters',
        specVersion: '0.5',
        revision: 'spec-main-2026-10-30',
        digest: 'sha256:fixture',
      );
      const snapshot = SpecSnapshotMetadata(
        specVersion: '0.5',
        revision: 'spec-main-2026-10-30',
        digest: 'sha256:fixture',
        sourceUrl: 'https://github.com/relgeo/spec/tree/main/id',
        fileCount: 34,
      );
      final match = SearchSpecMatch(
        sectionId: const SpecSectionId(
          relativePath: 'syntax/08-parameters.md',
          anchor: '8-parameters',
        ),
        title: '8. Parameters',
        parentHeadings: const <String>['Syntax'],
        snippet: 'Parameters define named inputs.',
        score: 4.5,
        provenance: provenance,
      );
      final result = SearchSpecResult(
        query: input.query,
        matches: <SearchSpecMatch>[match],
        snapshot: snapshot,
      );
      expect(result.noResults, isFalse);
      expect((result.toJson()['matches'] as List), hasLength(1));
      expect(
        ((result.toJson()['matches'] as List).single as Map)['parentHeadings'],
        <String>['Syntax'],
      );

      final empty = SearchSpecResult(
        query: 'unmatched',
        matches: const <SearchSpecMatch>[],
        snapshot: snapshot,
      );
      expect(empty.noResults, isTrue);
      expect(empty.toJson()['noResults'], isTrue);
      expect((empty.toJson()['matches'] as List), isEmpty);
    },
  );

  test(
    'full-spec tool contracts and fixture catalog are bounded and explicit',
    () {
      expect(relGeoSpecRetrievalToolContracts, hasLength(2));
      final search = relGeoSpecRetrievalToolContracts.first;
      final section = relGeoSpecRetrievalToolContracts.last;
      expect(search.name, 'relgeo_search_spec');
      expect(search.compatibilityAliases, contains('relgeo_find_syntax'));
      expect(
        ((search.inputSchema['properties'] as Map)['maxResults']
            as Map)['maximum'],
        32,
      );
      expect(section.name, 'relgeo_get_spec_section');
      expect((section.inputSchema['required'] as List), contains('sectionId'));
      expect(relGeoSpecRetrievalResourceUris, contains('relgeo://spec/index'));
      expect(
        relGeoSpecRetrievalResourceUris,
        contains('relgeo://spec/sections/{sectionId}'),
      );
      expect(relGeoSpecSearchFixtures, hasLength(5));
      expect(
        relGeoSpecSearchFixtures
            .singleWhere((fixture) => fixture.id == 'no-result')
            .expectsNoResults,
        isTrue,
      );
      for (final fixture in relGeoSpecSearchFixtures) {
        for (final id in fixture.expectedSectionIds) {
          expect(() => SpecSectionId.parse(id), returnsNormally);
        }
      }
    },
  );
}
