import 'package:relgeo_mcp/relgeo_mcp.dart';
import 'package:test/test.dart';

const _specProvenance = McpProvenance(
  source: McpProvenanceSource.spec,
  sourceUrl: 'https://github.com/relgeo/spec',
  specVersion: '0.5',
  revision: 'test-spec-revision',
);

RelGeoMcpToolHandlers _handlers() => RelGeoMcpToolHandlers(
  findSyntax: (input) => FindSyntaxResult(
    query: input.query,
    matches: <SyntaxMatch>[
      SyntaxMatch(
        ruleId: 'core/objects',
        title: 'Objects',
        summary: 'Declare RelGeo objects.',
        provenance: _specProvenance,
      ),
    ],
  ),
  getSyntaxRule: (_) => const SyntaxRuleResult(
    documentation: DocumentationResult(
      title: 'Objects',
      content: 'objects: ...',
      provenance: DocumentationProvenance(
        source: DocumentationSource.spec,
        sourceUrl: 'https://github.com/relgeo/spec',
        specVersion: '0.5',
        revision: 'test-spec-revision',
      ),
    ),
  ),
  getExamples: (input) => ExamplesResult(
    examples: <ExampleResult>[
      ExampleResult(
        exampleId: input.exampleId ?? 'objects-minimal',
        title: 'Minimal objects',
        source: 'objects: {}',
        provenance: _specProvenance,
      ),
    ],
  ),
  completeSource: (_) => const CompletionResult(items: <CompletionProposal>[]),
  validateSource: (input) => ValidationResult(
    source: input.source,
    sourceKind: input.sourceKind,
    valid: true,
    specVersion: input.specVersion,
    diagnostics: const <RelGeoDiagnostic>[],
    provenance: _specProvenance,
  ),
  explainDiagnostic: (_) => const DiagnosticExplanationResult(
    documentation: DocumentationResult(
      title: 'Diagnostic',
      content: 'Read the source range and correct the value.',
      provenance: DocumentationProvenance(
        source: DocumentationSource.spec,
        sourceUrl: 'https://github.com/relgeo/spec',
        specVersion: '0.5',
        revision: 'test-spec-revision',
      ),
    ),
  ),
  renderSource: (_) => const RenderResult(
    format: RenderFormat.svg,
    content: '<svg />',
    provenance: _specProvenance,
  ),
);

class _Bridge implements RelGeoAgentBridge {
  @override
  Future<ActiveDocumentSnapshot?> getActiveDocument() async =>
      const ActiveDocumentSnapshot(
        documentId: 'doc-1',
        name: 'active.relgeo',
        source: 'objects: {}',
        revision: 3,
        dirty: true,
      );

  @override
  Future<List<DocumentDiagnostic>> getDiagnostics() async =>
      const <DocumentDiagnostic>[
        DocumentDiagnostic(
          code: 'RG001',
          message: 'Example diagnostic',
          severity: DiagnosticSeverity.warning,
        ),
      ];

  @override
  Future<DocumentEditResult> applyDocumentEdit(
    DocumentEditProposal proposal,
  ) async => DocumentEditResult.rejected(message: proposal.summary);
}

void main() {
  test(
    'dispatcher lists typed tools and preserves input/result boundaries',
    () async {
      final dispatcher = RelGeoMcpToolDispatcher(_handlers());

      expect(dispatcher.listTools(), hasLength(7));
      final examples = dispatcher.listTools().singleWhere(
        (tool) => tool['name'] == 'relgeo_get_examples',
      );
      final schema = examples['inputSchema'] as Map<String, Object?>;
      expect(schema['additionalProperties'], isFalse);
      expect((schema['properties'] as Map)['maxResults'], isNotNull);

      final result = await dispatcher.call('relgeo_validate_source', {
        'source': 'objects: {}',
        'sourceKind': 'proposal',
        'specVersion': '0.5',
      });
      expect(result['sourceKind'], 'proposal');
      expect(result['valid'], isTrue);
    },
  );

  test('dispatcher rejects invalid arguments before invoking owners', () async {
    final dispatcher = RelGeoMcpToolDispatcher(_handlers());

    await expectLater(
      dispatcher.call('relgeo_find_syntax', {
        'query': 'objects',
        'maxResults': 0,
      }),
      throwsA(
        isA<McpDispatchException>().having(
          (error) => error.code,
          'code',
          -32602,
        ),
      ),
    );
    await expectLater(
      dispatcher.call('relgeo_find_syntax', {
        'query': 'objects',
        'unexpected': true,
      }),
      throwsA(isA<McpDispatchException>()),
    );
    await expectLater(
      dispatcher.call('unknown_tool', const <String, Object?>{}),
      throwsA(
        isA<McpDispatchException>().having(
          (error) => error.code,
          'code',
          -32601,
        ),
      ),
    );
    await expectLater(
      dispatcher.call('relgeo_find_syntax', <Object, Object?>{1: 'objects'}),
      throwsA(isA<McpDispatchException>()),
    );
  });

  test(
    'JSON-RPC router owns initialize, discovery, call, and read flow',
    () async {
      final router = RelGeoMcpJsonRpcRouter(
        dispatcher: RelGeoMcpToolDispatcher(_handlers()),
        resources: RelGeoMcpResourceStore(
          staticResources: <String, McpResourceContent>{
            'relgeo://spec/index': const McpResourceContent(
              uri: 'relgeo://spec/index',
              mimeType: 'text/plain',
              text: 'core/objects',
            ),
          },
        ),
      );

      final beforeInitialize = await router.handle(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/list',
      });
      expect((beforeInitialize?['error'] as Map)['code'], -32002);

      final unsupported = await router.handle(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 99,
        'method': 'initialize',
        'params': <String, Object?>{'protocolVersion': 'unsupported'},
      });
      expect((unsupported?['error'] as Map)['code'], -32602);

      final initialize = await router.handle(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'initialize',
        'params': <String, Object?>{
          'protocolVersion': RelGeoMcpJsonRpcRouter.protocolVersion,
        },
      });
      expect(
        (initialize?['result'] as Map)['protocolVersion'],
        RelGeoMcpJsonRpcRouter.protocolVersion,
      );
      expect(router.initialized, isFalse);
      expect(
        await router.handle(<String, Object?>{
          'jsonrpc': '2.0',
          'method': 'notifications/initialized',
        }),
        isNull,
      );
      expect(router.initialized, isTrue);

      final tools = await router.handle(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/list',
      });
      expect((tools?['result'] as Map)['tools'], hasLength(7));

      final call = await router.handle(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 4,
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': 'relgeo_validate_source',
          'arguments': <String, Object?>{'source': 'objects: {}'},
        },
      });
      expect((call?['result'] as Map)['isError'], isFalse);
      expect(
        ((call?['result'] as Map)['structuredContent'] as Map)['valid'],
        isTrue,
      );

      final read = await router.handle(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 5,
        'method': 'resources/read',
        'params': <String, Object?>{'uri': 'relgeo://spec/index'},
      });
      expect(
        (((read?['result'] as Map)['contents'] as List).single as Map)['text'],
        'core/objects',
      );
    },
  );

  test(
    'resource store serves pinned resources and guards active session',
    () async {
      final store = RelGeoMcpResourceStore(
        activeBridge: _Bridge(),
        staticResources: <String, McpResourceContent>{
          'relgeo://spec/index': const McpResourceContent(
            uri: 'relgeo://spec/index',
            mimeType: 'text/plain',
            text: 'core/objects',
            provenance: _specProvenance,
          ),
        },
      );

      expect(store.listResources(), hasLength(7));
      final spec = await store.read('relgeo://spec/index');
      expect(spec.provenance?.isNormative, isTrue);
      expect(
        (await store.read('relgeo://document/active')).text,
        contains('doc-1'),
      );
      expect(
        (await store.read('relgeo://document/active/diagnostics')).text,
        contains('RG001'),
      );
      await expectLater(
        store.read('relgeo://spec/rules/missing'),
        throwsA(isA<McpDispatchException>()),
      );
      await expectLater(
        store.read('relgeo://spec/../../etc/passwd'),
        throwsA(isA<McpDispatchException>()),
      );
    },
  );

  test('server session is explicitly enabled and revokes tokens on stop', () {
    final session = McpServerSession(
      policy: const McpSecurityPolicy(enabled: true),
    );
    expect(session.isRunning, isFalse);
    session.start();
    final token = session.issueToken(permission: McpPermission.readOnly);
    expect(
      session.authorize(
        token.value,
        requiredPermission: McpPermission.readOnly,
      ),
      isNotNull,
    );
    expect(
      session.authorize(
        token.value,
        requiredPermission: McpPermission.readWrite,
      ),
      isNull,
    );
    session.stop();
    expect(session.isRunning, isFalse);
    expect(
      session.authorize(
        token.value,
        requiredPermission: McpPermission.readOnly,
      ),
      isNull,
    );
  });
}
