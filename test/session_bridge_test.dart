import 'dart:math';

import 'package:relgeo_mcp/relgeo_mcp.dart';
import 'package:test/test.dart';

void main() {
  final snapshot = ActiveDocumentSnapshot(
    documentId: 'doc-1',
    name: 'drawing.relgeo',
    source: 'scene: old\n',
    revision: 7,
    dirty: true,
  );

  test('applies bounded non-overlapping edits from right to left', () {
    final proposal = DocumentEditProposal(
      baseDocumentId: 'doc-1',
      baseRevision: 7,
      summary: 'Update scene and add a note',
      edits: [
        const DocumentEdit(
          range: SourceRange(start: 7, end: 10),
          replacement: 'new',
        ),
        const DocumentEdit(
          range: SourceRange(start: 11, end: 11),
          replacement: '# agent edit\n',
        ),
      ],
    );

    expect(proposal.validateAgainst(snapshot), isEmpty);
    expect(proposal.applyTo(snapshot), 'scene: new\n# agent edit\n');
  });

  test('rejects stale revision and overlapping or out-of-bounds edits', () {
    final stale = DocumentEditProposal(
      baseDocumentId: 'doc-1',
      baseRevision: 6,
      summary: 'Stale proposal',
      edits: const <DocumentEdit>[
        DocumentEdit(range: SourceRange(start: 0, end: 0), replacement: 'x'),
      ],
    );
    expect(stale.validateAgainst(snapshot), contains('baseRevision is stale'));

    final invalid = DocumentEditProposal(
      baseDocumentId: 'doc-1',
      baseRevision: 7,
      summary: 'Invalid proposal',
      edits: const <DocumentEdit>[
        DocumentEdit(range: SourceRange(start: 0, end: 4), replacement: 'x'),
        DocumentEdit(range: SourceRange(start: 3, end: 20), replacement: 'y'),
      ],
    );
    expect(invalid.validateAgainst(snapshot), contains('edit ranges overlap'));
    expect(
      invalid.validateAgainst(snapshot),
      contains('edit range is outside the active source'),
    );
  });

  test('token lifecycle enforces scope, expiry, and revocation', () {
    final store = McpSessionTokenStore(random: Random(3));
    final issuedAt = DateTime.utc(2026, 10, 8);
    final readOnly = store.issue(
      permission: McpPermission.readOnly,
      ttl: const Duration(minutes: 5),
      now: issuedAt,
    );
    expect(
      store.validate(
        readOnly.value,
        requiredPermission: McpPermission.readOnly,
        now: issuedAt.add(const Duration(minutes: 1)),
      ),
      isNotNull,
    );
    expect(
      store.validate(
        readOnly.value,
        requiredPermission: McpPermission.readWrite,
        now: issuedAt.add(const Duration(minutes: 1)),
      ),
      isNull,
    );
    expect(
      store.validate(
        readOnly.value,
        requiredPermission: McpPermission.readOnly,
        now: issuedAt.add(const Duration(minutes: 5)),
      ),
      isNull,
    );

    final write = store.issue(
      permission: McpPermission.readWrite,
      now: issuedAt,
    );
    expect(store.revoke(write.value), isTrue);
    expect(
      store.validate(
        write.value,
        requiredPermission: McpPermission.readWrite,
        now: issuedAt,
      ),
      isNull,
    );
  });

  test('security policy defaults are localhost-only and non-writing', () {
    const policy = McpSecurityPolicy();
    expect(policy.enabled, isFalse);
    expect(policy.bindAddress, '127.0.0.1');
    expect(policy.acceptsConnectionFrom('127.0.0.1'), isTrue);
    expect(policy.acceptsConnectionFrom('192.0.2.1'), isFalse);
    expect(policy.allowFilesystemWrites, isFalse);
    expect(policy.allowAutosave, isFalse);
    expect(policy.validate(), isEmpty);
  });

  test('documentation provenance keeps website non-normative', () {
    const provenance = DocumentationProvenance(
      source: DocumentationSource.website,
      sourceUrl: 'https://relgeo.github.io/docs/language-spec',
      specVersion: '0.5.x',
      revision: 'site-2026-10-08',
    );
    expect(provenance.isNormative, isFalse);
    expect(
      const DocumentationProvenance(
        source: DocumentationSource.spec,
        sourceUrl: 'https://github.com/relgeo/spec',
        specVersion: '0.5.x',
        revision: 'v0.5.1',
      ).isNormative,
      isTrue,
    );
  });
}
