# relgeo_mcp

Repository: `relgeo/mcp`. This is the private, non-publishable package
repository for the RelGeo MCP contract and protocol adapter.

Pure-Dart contract and protocol package for the RelGeo MCP server and desktop
session bridge. It deliberately has no Flutter, widget, filesystem, or socket
transport dependency. The Flutter desktop host owns the local HTTP listener
and supplies the active-document bridge.

This package defines the session/security boundary and protocol-independent MCP
tool/resource contracts:

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
- `local_dispatch.dart` provides typed tool dispatch, full-spec search and
  section retrieval from a pinned in-memory index, desktop capability/example/
  active-document reads, and the opt-in bounded active-document edit route.
  Owner callbacks are
  injected so this package does not duplicate core, language-service, or
  renderer semantics. Desktop hosts supply the complete offline `spec/id`
  search index. Edit authorization is enforced by the desktop host's
  read-write token; the router exposes the edit tool only when the user enables
  editing in Flutter.

The package does not select an MCP SDK or implement socket transport. The
router is the SDK-neutral boundary; HTTP framing and host lifecycle are owned
by the Flutter desktop integration. Standalone stdio remains a separate
decision in the conformance spike described in
`docs/plans/11-mcp-agent-integration.md`.

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
