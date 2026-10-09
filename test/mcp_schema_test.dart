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
}
