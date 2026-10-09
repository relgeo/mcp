# relgeo_mcp

Target repository: `relgeo/mcp`. This workspace directory is the private
staging package for the MCP contract spike.

Pure-Dart contract package for the RelGeo MCP server and desktop session
bridge. It deliberately has no Flutter, widget, filesystem, or transport
dependency.

This package currently defines the session/security boundary spike:

- `ActiveDocumentSnapshot` is the read boundary for the active document;
- `DocumentEditProposal` is a bounded, range-based patch guarded by
  `baseDocumentId` and `baseRevision`;
- `DocumentEditResult` makes stale and rejected writes explicit;
- `McpSessionTokenStore` models per-server token issuance, scope, expiry, and
  revocation;
- `McpSecurityPolicy` records the localhost-only, no-filesystem-write, and
  no-autosave defaults.
- `mcp_schema.dart` defines the typed MVP tool/resource contract, bounded
  inputs, source proposals, validation results, diagnostics, and provenance.

The package does not select an MCP SDK or transport. That decision belongs to
the conformance spike described in `docs/plans/11-mcp-agent-integration.md`.

The transport fixture lives under `tool/`. Run the dependency-free stdio
round-trip with:

```text
dart run tool/run_transport_conformance.dart --stdio-only
```

The full command also starts a loopback Streamable HTTP endpoint on an
ephemeral port and sends the same sequence:

```text
dart run tool/run_transport_conformance.dart
```

See `docs/mcp/02-sdk-transport-spike.md` for candidate comparison, Inspector
validation, protocol version choice, and the Flutter toolchain baseline.
See `docs/mcp/04-mvp-tool-resource-contract.md` for the tool/resource mapping
and the evidence boundary to `spec/id`, core, language-service, and renderer.
