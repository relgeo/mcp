import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'protocol_fixture.dart';

Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  final transport = options['transport'];
  if (transport == 'stdio') {
    await _serveStdio();
    return;
  }
  if (transport == 'http') {
    await _serveHttp(host: options['host']!, port: int.parse(options['port']!));
    return;
  }
  stderr.writeln('usage: --transport stdio|http [--host 127.0.0.1] [--port 0]');
  exitCode = 64;
}

Future<void> _serveStdio() async {
  final fixture = McpProtocolFixture();
  await stdin.transform(utf8.decoder).transform(const LineSplitter()).forEach((
    line,
  ) {
    if (line.trim().isEmpty) return;
    final message = jsonDecode(line);
    if (message is! Map) return;
    final response = fixture.handle(
      Map<String, Object?>.from(message.cast<String, Object?>()),
    );
    if (response != null) {
      stdout.writeln(jsonEncode(response));
    }
  });
}

Future<void> _serveHttp({required String host, required int port}) async {
  if (host != '127.0.0.1') {
    stderr.writeln('remote HTTP is disabled; host must be 127.0.0.1');
    exitCode = 64;
    return;
  }

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('MCP_FIXTURE_READY http://127.0.0.1:${server.port}/mcp');
  await for (final request in server) {
    unawaited(_handleHttpRequest(request));
  }
}

Future<void> _handleHttpRequest(HttpRequest request) async {
  if (request.uri.path != '/mcp') {
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
    return;
  }
  if (request.method != 'POST') {
    request.response.statusCode = HttpStatus.methodNotAllowed;
    await request.response.close();
    return;
  }
  final accept = request.headers.value('accept') ?? '';
  if (!accept.contains('application/json') ||
      !accept.contains('text/event-stream')) {
    request.response.statusCode = HttpStatus.notAcceptable;
    await request.response.close();
    return;
  }
  final protocolHeader = request.headers.value('MCP-Protocol-Version');
  if (protocolHeader != null && protocolHeader != mcpFixtureProtocolVersion ||
      _httpFixture.initialized && protocolHeader != mcpFixtureProtocolVersion) {
    request.response.statusCode = HttpStatus.badRequest;
    await request.response.close();
    return;
  }
  final origin = request.headers.value('origin');
  if (origin != null &&
      origin != 'http://127.0.0.1' &&
      origin != 'http://localhost') {
    request.response.statusCode = HttpStatus.forbidden;
    await request.response.close();
    return;
  }

  final body = await utf8.decoder.bind(request).join();
  final decoded = jsonDecode(body);
  if (decoded is! Map) {
    request.response.statusCode = HttpStatus.badRequest;
    await request.response.close();
    return;
  }
  final response = _httpFixture.handle(
    Map<String, Object?>.from(decoded.cast<String, Object?>()),
  );
  if (response == null) {
    request.response.statusCode = HttpStatus.accepted;
    await request.response.close();
    return;
  }
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(response));
  await request.response.close();
}

final McpProtocolFixture _httpFixture = McpProtocolFixture();

Map<String, String> _parseArgs(List<String> args) {
  final result = <String, String>{
    'transport': 'stdio',
    'host': '127.0.0.1',
    'port': '0',
  };
  for (var index = 0; index < args.length; index += 1) {
    final argument = args[index];
    if (!argument.startsWith('--') || index + 1 >= args.length) continue;
    result[argument.substring(2)] = args[++index];
  }
  return result;
}
