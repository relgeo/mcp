import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'protocol_conformance.dart';

Future<void> main(List<String> args) async {
  await _runStdio();
  stdout.writeln('stdio fixture conformance: PASS');
  if (args.contains('--stdio-only')) return;
  try {
    await _runHttp();
  } catch (error) {
    stderr.writeln('streamable-http fixture conformance: NOT RUN: $error');
    exitCode = 2;
    return;
  }
  stdout.writeln('stdio + streamable-http fixture conformance: PASS');
}

Future<void> _runStdio() async {
  final process = await Process.start(Platform.resolvedExecutable, <String>[
    '--suppress-analytics',
    'run',
    'tool/mcp_fixture_server.dart',
    '--transport',
    'stdio',
  ], workingDirectory: Directory.current.path);
  final lines = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  final responses = StreamIterator<String>(lines);
  final stderr = process.stderr.transform(utf8.decoder).join();

  Future<Map<String, Object?>> sendRequest(Map<String, Object?> request) async {
    process.stdin.writeln(jsonEncode(request));
    await process.stdin.flush();
    if (!await responses.moveNext()) {
      throw StateError(
        'stdio fixture exited before response '
        '(code ${await process.exitCode}): ${await stderr}',
      );
    }
    return Map<String, Object?>.from(
      (jsonDecode(responses.current) as Map).cast<String, Object?>(),
    );
  }

  Future<void> sendNotification(Map<String, Object?> notification) async {
    process.stdin.writeln(jsonEncode(notification));
    await process.stdin.flush();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  try {
    await runFixtureConformance(
      sendRequest: sendRequest,
      sendNotification: sendNotification,
    );
  } finally {
    await process.stdin.close();
    await process.exitCode;
  }
}

Future<void> _runHttp() async {
  final process = await Process.start(Platform.resolvedExecutable, <String>[
    '--suppress-analytics',
    'run',
    'tool/mcp_fixture_server.dart',
    '--transport',
    'http',
    '--host',
    '127.0.0.1',
    '--port',
    '0',
  ], workingDirectory: Directory.current.path);
  final stderr = process.stderr.transform(utf8.decoder).join();
  final lines = StreamIterator<String>(
    process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
  );
  String? ready;
  while (await lines.moveNext()) {
    if (lines.current.startsWith('MCP_FIXTURE_READY ')) {
      ready = lines.current;
      break;
    }
  }
  if (ready == null) {
    throw StateError(
      'HTTP fixture exited with code ${await process.exitCode}: ${await stderr}',
    );
  }
  final endpoint = ready.substring('MCP_FIXTURE_READY '.length);
  final client = HttpClient();

  Future<Map<String, Object?>> sendRequest(Map<String, Object?> request) async {
    final httpRequest = await client.postUrl(Uri.parse(endpoint));
    httpRequest.headers
      ..set('Accept', 'application/json, text/event-stream')
      ..set('Content-Type', 'application/json')
      ..set('MCP-Protocol-Version', '2025-11-25');
    httpRequest.write(jsonEncode(request));
    final response = await httpRequest.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('HTTP fixture status ${response.statusCode}: $body');
    }
    return Map<String, Object?>.from(
      (jsonDecode(body) as Map).cast<String, Object?>(),
    );
  }

  Future<void> sendNotification(Map<String, Object?> notification) async {
    final httpRequest = await client.postUrl(Uri.parse(endpoint));
    httpRequest.headers
      ..set('Accept', 'application/json, text/event-stream')
      ..set('Content-Type', 'application/json')
      ..set('MCP-Protocol-Version', '2025-11-25');
    httpRequest.write(jsonEncode(notification));
    final response = await httpRequest.close();
    if (response.statusCode != HttpStatus.accepted) {
      throw StateError('HTTP notification status ${response.statusCode}');
    }
    await response.drain<void>();
  }

  try {
    await runFixtureConformance(
      sendRequest: sendRequest,
      sendNotification: sendNotification,
    );
  } finally {
    client.close(force: true);
    process.kill(ProcessSignal.sigterm);
    await process.exitCode;
  }
}
