import 'package:relgeo_mcp/relgeo_mcp.dart';
import 'package:test/test.dart';

const _snapshot = SpecSnapshotMetadata(
  specVersion: '0.5',
  revision: 'spec-revision',
  digest: 'sha256:fixture',
  sourceUrl: 'https://github.com/relgeo/spec/tree/spec-revision/id',
  fileCount: 2,
);

SpecSectionIndex _index() => SpecSectionIndex.fromDocuments(
  snapshot: _snapshot,
  documents: const <SpecMarkdownDocument>[
    SpecMarkdownDocument(
      relativePath: 'geometry/14-geometry-objects.md',
      content: '''# 14. Geometry Objects

Status dokumen: `Normative`

Introductory geometry rules.

## 14.3 Rect

Rect represents a rectangle with width and height.

### Placement

The rect can be placed at a point.

```md
## Not a section
```

## 14.4 Circle

Circle content.''',
    ),
    SpecMarkdownDocument(
      relativePath: 'syntax/08-parameters.md',
      content: '''# 8. Parameters

Status dokumen: `Normative`

Parameters define named inputs.''',
    ),
  ],
);

void main() {
  test('parses stable anchors, parent headings, and complete section content', () {
    final index = _index();
    final rect = index.sections.singleWhere(
      (section) => section.id.value == 'geometry/14-geometry-objects.md#143-rect',
    );

    expect(rect.parentHeadings, <String>['14. Geometry Objects']);
    expect(rect.content, contains('Rect represents a rectangle'));
    expect(rect.content, isNot(contains('14.4 Circle')));
    expect(rect.content, contains('## Not a section'));
    expect(rect.provenance.isNormative, isTrue);
    expect(rect.provenance.revision, 'spec-revision');
  });

  test('normalizes query terms and returns deterministic ranked matches', () {
    final index = _index();
    final result = index.search(
      const SearchSpecInput(query: 'RECT, width', maxResults: 4),
    );

    expect(result.matches, isNotEmpty);
    expect(result.matches.first.sectionId.value, contains('#143-rect'));
    expect(result.matches.first.snippet.length, lessThanOrEqualTo(320));
    expect(result.matches.first.score, greaterThan(0));
    expect(result.snapshot.digest, 'sha256:fixture');
  });

  test('returns no result without dumping the corpus', () {
    final result = _index().search(
      const SearchSpecInput(query: 'no-such-relgeo-term'),
    );

    expect(result.noResults, isTrue);
    expect(result.matches, isEmpty);
  });

  test('serves bounded index and complete section resources', () {
    final index = _index();
    final resource = index.indexResourceJson();
    final sections = resource['sections'] as List<Object?>;
    expect(sections, hasLength(5));
    expect(resource['snapshot'], containsPair('digest', 'sha256:fixture'));

    final section = index.sectionResourceJson(
      'syntax/08-parameters.md#8-parameters',
    );
    expect(section['section'], containsPair('content', contains('Parameters')));
    expect(
      () => index.sectionResourceJson('syntax/missing.md#missing'),
      throwsA(isA<SpecSectionNotFoundException>()),
    );
  });
}
