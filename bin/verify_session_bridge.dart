import 'dart:math';

import 'package:relgeo_mcp/relgeo_mcp.dart';

void main() {
  final snapshot = ActiveDocumentSnapshot(
    documentId: 'doc-1',
    name: 'drawing.relgeo',
    source: 'scene: old\n',
    revision: 7,
    dirty: true,
  );
  final proposal = DocumentEditProposal(
    baseDocumentId: 'doc-1',
    baseRevision: 7,
    summary: 'Update scene and add a note',
    edits: const <DocumentEdit>[
      DocumentEdit(range: SourceRange(start: 7, end: 10), replacement: 'new'),
      DocumentEdit(
        range: SourceRange(start: 11, end: 11),
        replacement: '# agent edit\n',
      ),
    ],
  );
  _check(proposal.validateAgainst(snapshot).isEmpty, 'valid proposal');
  _check(
    proposal.applyTo(snapshot) == 'scene: new\n# agent edit\n',
    'multi-edit application',
  );

  final stale = DocumentEditProposal(
    baseDocumentId: 'doc-1',
    baseRevision: 6,
    summary: 'Stale proposal',
    edits: const <DocumentEdit>[
      DocumentEdit(range: SourceRange(start: 0, end: 0), replacement: 'x'),
    ],
  );
  _check(
    stale.validateAgainst(snapshot).contains('baseRevision is stale'),
    'stale revision rejection',
  );

  final store = McpSessionTokenStore(random: Random(3));
  final issuedAt = DateTime.utc(2026, 10, 8);
  final readOnly = store.issue(
    permission: McpPermission.readOnly,
    ttl: const Duration(minutes: 5),
    now: issuedAt,
  );
  _check(
    store.validate(
          readOnly.value,
          requiredPermission: McpPermission.readOnly,
          now: issuedAt.add(const Duration(minutes: 1)),
        ) !=
        null,
    'read-only token validation',
  );
  _check(
    store.validate(
          readOnly.value,
          requiredPermission: McpPermission.readWrite,
          now: issuedAt.add(const Duration(minutes: 1)),
        ) ==
        null,
    'read-only cannot write',
  );
  _check(
    store.validate(
          readOnly.value,
          requiredPermission: McpPermission.readOnly,
          now: issuedAt.add(const Duration(minutes: 5)),
        ) ==
        null,
    'expired token rejection',
  );

  const policy = McpSecurityPolicy();
  _check(policy.validate().isEmpty, 'secure policy defaults');
  _check(
    !policy.acceptsConnectionFrom('192.0.2.1'),
    'remote connection rejection',
  );
  print('session bridge contract fixture: PASS');
}

void _check(bool condition, String label) {
  if (!condition) throw StateError('fixture failed: $label');
}
