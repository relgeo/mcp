import 'package:relgeo_mcp/relgeo_mcp.dart';
import 'package:test/test.dart';

const _specProvenance = McpProvenance(
  source: McpProvenanceSource.spec,
  sourceUrl: 'https://github.com/relgeo/spec',
  specVersion: '0.5',
  revision: 'test-spec-revision',
);

const _specSnapshot = SpecSnapshotMetadata(
  specVersion: '0.5',
  revision: 'test-spec-revision',
  digest: 'sha256:fixture',
  sourceUrl: 'https://github.com/relgeo/spec/tree/test-spec-revision/id',
  fileCount: 1,
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
  final specIndex = SpecSectionIndex.fromDocuments(
    snapshot: _specSnapshot,
    documents: const <SpecMarkdownDocument>[
      SpecMarkdownDocument(
        relativePath: 'geometry/14-geometry-objects.md',
        content: '''# 14. Geometry Objects

Status dokumen: `Normative`

## 14.3 Rect

Rect uses width and height.''',
      ),
    ],
  );

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

  test(
    'dispatcher and resource store use the supplied full spec index',
    () async {
      final dispatcher = RelGeoMcpToolDispatcher(
        _handlers(),
        specIndex: specIndex,
      );
      expect(dispatcher.listTools(), hasLength(10));
      expect(dispatcher.listTools().first['name'], 'relgeo_get_capabilities');

      final search = await dispatcher.call('relgeo_search_spec', {
        'query': 'rect width',
      });
      expect(search['noResults'], isFalse);
      expect((search['matches'] as List), isNotEmpty);

      final section = await dispatcher.call('relgeo_get_spec_section', {
        'sectionId': 'geometry/14-geometry-objects.md#143-rect',
      });
      expect(
        (section['section'] as Map)['content'],
        contains('Rect uses width and height'),
      );
      final alias = await dispatcher.call('relgeo_find_syntax', {
        'query': 'rect',
      });
      expect(alias['noResults'], isFalse);

      final capabilities = await dispatcher.call(
        'relgeo_get_capabilities',
        const <String, Object?>{},
      );
      expect(capabilities['sourceOfTruth'], 'spec/id');
      expect(capabilities['specCoverage'], 'full spec/id Markdown snapshot');
      expect((capabilities['specSnapshot'] as Map)['digest'], 'sha256:fixture');

      final noResults = await dispatcher.call('relgeo_search_spec', {
        'query': 'not-in-the-fixture',
      });
      expect(noResults['noResults'], isTrue);
      expect(noResults['matches'], isEmpty);

      await expectLater(
        dispatcher.call('relgeo_search_spec', {
          'query': 'rect',
          'specVersion': '0.6',
        }),
        throwsA(
          isA<McpDispatchException>()
              .having((error) => error.code, 'code', -32602)
              .having(
                (error) => error.data?['availableSpecVersion'],
                'available version',
                '0.5',
              ),
        ),
      );
    await expectLater(
      dispatcher.call('relgeo_get_spec_section', {
        'sectionId': 'geometry/14-geometry-objects.md#143-rect',
        'specVersion': '0.6',
      }),
      throwsA(isA<McpDispatchException>()),
    );
    await expectLater(
      dispatcher.call('relgeo_get_spec_section', {
        'sectionId': 'geometry/missing.md#missing',
      }),
      throwsA(
        isA<McpDispatchException>()
            .having((error) => error.code, 'code', -32004)
            .having(
              (error) => error.data?['sectionId'],
              'section id',
              'geometry/missing.md#missing',
            ),
      ),
    );

      final store = RelGeoMcpResourceStore(specIndex: specIndex);
      expect(store.listResources(includeUnavailable: false), hasLength(1));
      expect(store.listResourceTemplates(), hasLength(1));
      expect(
        store.listResourceTemplates().single['uriTemplate'],
        relGeoSpecSectionResourceTemplate,
      );
      expect(
        (await store.read('relgeo://spec/index')).text,
        contains('143-rect'),
      );
      expect(
        (await store.read(
          'relgeo://spec/sections/geometry%2F14-geometry-objects.md%23143-rect',
        )).text,
        contains('Rect uses width and height'),
      );
      await expectLater(
        store.read('relgeo://spec/sections/geometry%2Fmissing.md%23missing'),
        throwsA(isA<McpDispatchException>()),
      );
    },
  );

  test('spec-only dispatcher advertises only loaded retrieval capabilities', () {
    final dispatcher = RelGeoMcpToolDispatcher(null, specIndex: specIndex);
    final names = dispatcher.listTools().map((tool) => tool['name']);

    expect(
      names,
      containsAll(<String>[
        'relgeo_get_capabilities',
        'relgeo_search_spec',
        'relgeo_get_spec_section',
        'relgeo_find_syntax',
      ]),
    );
    expect(names, isNot(contains('relgeo_validate_source')));
  });

  test('desktop bridge keeps examples separate from normative retrieval', () async {
    final router = RelGeoMcpJsonRpcRouter(
      dispatcher: RelGeoMcpToolDispatcher(null, specIndex: specIndex),
      activeBridge: _Bridge(),
      resources: RelGeoMcpResourceStore(
        activeBridge: _Bridge(),
        specIndex: specIndex,
      ),
    );
    await router.handle(<String, Object?>{
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': <String, Object?>{
        'protocolVersion': RelGeoMcpJsonRpcRouter.protocolVersion,
      },
    });
    await router.handle(<String, Object?>{
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
    });

    final tools = await router.handle(<String, Object?>{
      'jsonrpc': '2.0',
      'id': 2,
      'method': 'tools/list',
    });
    expect(
      ((tools?['result'] as Map)['tools'] as List)
          .map((tool) => (tool as Map)['name']),
      contains('relgeo_get_examples'),
    );

    final examples = await router.handle(<String, Object?>{
      'jsonrpc': '2.0',
      'id': 3,
      'method': 'tools/call',
      'params': <String, Object?>{
        'name': 'relgeo_get_examples',
        'arguments': <String, Object?>{'query': 'square'},
      },
    });
    final example = (((examples?['result'] as Map)['structuredContent']
        as Map)['examples'] as List).single as Map;
    expect((example['provenance'] as Map)['source'], 'example');
    expect((example['provenance'] as Map)['normative'], isFalse);

    final capabilities = await router.handle(<String, Object?>{
      'jsonrpc': '2.0',
      'id': 4,
      'method': 'tools/call',
      'params': <String, Object?>{
        'name': 'relgeo_get_capabilities',
        'arguments': const <String, Object?>{},
      },
    });
    expect(
      ((capabilities?['result'] as Map)['structuredContent'] as Map)['tools'],
      contains('relgeo_get_examples'),
    );
  });

  test(
    'JSON-RPC full-spec boundary exposes tools, resources, and errors',
    () async {
      final router = RelGeoMcpJsonRpcRouter(
        dispatcher: RelGeoMcpToolDispatcher(_handlers(), specIndex: specIndex),
        resources: RelGeoMcpResourceStore(specIndex: specIndex),
      );

      final initialize = await router.handle(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': <String, Object?>{
          'protocolVersion': RelGeoMcpJsonRpcRouter.protocolVersion,
        },
      });
      expect((initialize?['result'] as Map)['serverInfo'], isNotNull);
      await router.handle(<String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      });

      final tools = await router.handle(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/list',
      });
      final listed = ((tools?['result'] as Map)['tools'] as List).cast<Map>();
      expect(
        listed.map((tool) => tool['name']),
        containsAll(<String>[
          'relgeo_search_spec',
          'relgeo_get_spec_section',
          'relgeo_find_syntax',
          'relgeo_get_capabilities',
        ]),
      );

      final search = await router.handle(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': 'relgeo_search_spec',
          'arguments': <String, Object?>{'query': 'width'},
        },
      });
      final searchResult = search?['result'] as Map;
      expect(searchResult['isError'], isFalse);
      expect(
        ((searchResult['structuredContent'] as Map)['snapshot']
            as Map)['revision'],
        'test-spec-revision',
      );

      final mismatch = await router.handle(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 4,
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': 'relgeo_search_spec',
          'arguments': <String, Object?>{
            'query': 'width',
            'specVersion': '0.6',
          },
        },
      });
      expect((mismatch?['error'] as Map)['code'], -32602);
      expect(
        ((mismatch?['error'] as Map)['data'] as Map)['availableSpecVersion'],
        '0.5',
      );

      final resourceList = await router.handle(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 5,
        'method': 'resources/list',
      });
      expect(
        ((resourceList?['result'] as Map)['resources'] as List),
        hasLength(1),
      );

      final templateList = await router.handle(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 6,
        'method': 'resources/templates/list',
      });
      final templates =
          ((templateList?['result'] as Map)['resourceTemplates'] as List);
      expect(templates, hasLength(1));
      expect(
        (templates.single as Map)['uriTemplate'],
        relGeoSpecSectionResourceTemplate,
      );
    },
  );

  test('canonical retrieval reports unavailable without a snapshot', () async {
    final dispatcher = RelGeoMcpToolDispatcher(_handlers());
    await expectLater(
      dispatcher.call('relgeo_search_spec', {'query': 'rect'}),
      throwsA(
        isA<McpDispatchException>()
            .having((error) => error.code, 'code', -32001)
            .having(
              (error) => error.data?['required'],
              'required snapshot marker',
              'pinned local Markdown snapshot',
            ),
      ),
    );
  });

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
