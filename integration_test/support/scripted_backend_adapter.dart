import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

const integrationBackendBaseUrl = 'https://backend.example.test';
const integrationBackendCanonicalBaseUrl = '$integrationBackendBaseUrl/';

final class ScriptedBackendExchange {
  ScriptedBackendExchange({
    required this.method,
    required this.path,
    required this.accessKey,
    required this.authorization,
    required this.body,
    this.requestBody,
    this.userId,
    this.statusCode = 200,
    this.additionalHeaders = const {},
    this.release,
    this.repeatable = false,
  });

  final String method;
  final String path;
  final String? accessKey;
  final String? authorization;
  final String? userId;
  final Object body;
  final Object? requestBody;
  final int statusCode;
  final Map<String, List<String>> additionalHeaders;
  final Future<void>? release;

  /// Serves every matching repeat of this request instead of being consumed
  /// once. Independent callers may each admit their own synchronization when
  /// they do not overlap, so the trailing exchange must stay replayable.
  final bool repeatable;
}

final class ScriptedBackendAdapter implements HttpClientAdapter {
  ScriptedBackendAdapter(Iterable<ScriptedBackendExchange> exchanges)
    : _exchanges = Queue.of(exchanges);

  final Queue<ScriptedBackendExchange> _exchanges;
  final Set<ScriptedBackendExchange> _served = {};
  Object? _failure;
  int _requestCount = 0;

  int get requestCount => _requestCount;
  Object? get failure => _failure;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    _requestCount += 1;
    if (_exchanges.isEmpty) {
      return _fail('Unexpected backend request after the script completed.');
    }
    final exchange = _exchanges.first;
    if (!exchange.repeatable) {
      _exchanges.removeFirst();
    }
    try {
      _require(
        options.baseUrl == integrationBackendCanonicalBaseUrl,
        'The request did not use the reserved integration-test backend.',
      );
      _require(options.method == exchange.method, 'Unexpected request method.');
      _require(options.path == exchange.path, 'Unexpected request route.');
      _require(
        options.headers['access-key'] == exchange.accessKey,
        'Unexpected access-key header.',
      );
      _require(
        options.headers['Authorization'] == exchange.authorization,
        'Unexpected authorization placeholder.',
      );
      _require(
        options.headers['X-LEB2-USER-ID'] == exchange.userId,
        'Unexpected LEB2 user ID header.',
      );
      _require(
        options.headers['X-Device-ID'] == 'integration-device',
        'Unexpected device identity header.',
      );
      _require(
        options.headers['X-Device-Platform'] == 'android',
        'Unexpected device platform header.',
      );
      _require(
        options.headers['X-Client-Version'] == '0.5.0',
        'Unexpected client version header.',
      );
      final expectedRequestBody = exchange.requestBody;
      if (expectedRequestBody == null) {
        _require(requestStream == null, 'Unexpected request body stream.');
      } else {
        _require(requestStream != null, 'Expected a request body stream.');
        final bytes = await requestStream!.fold<List<int>>(
          <int>[],
          (value, chunk) => value..addAll(chunk),
        );
        final actualRequestBody = jsonDecode(utf8.decode(bytes));
        _require(
          _jsonMatches(actualRequestBody, expectedRequestBody),
          'Unexpected sanitized request body.',
        );
      }
      await exchange.release;
      _served.add(exchange);
      return ResponseBody.fromString(
        jsonEncode(exchange.body),
        exchange.statusCode,
        headers: {
          Headers.contentTypeHeader: const ['application/json'],
          ...exchange.additionalHeaders,
        },
      );
    } on Object catch (error) {
      _failure ??= error;
      rethrow;
    }
  }

  Never _fail(String message) {
    final error = StateError(message);
    _failure ??= error;
    throw error;
  }

  void _require(bool condition, String message) {
    if (!condition) {
      _fail(message);
    }
  }

  bool _jsonMatches(Object? actual, Object? expected) {
    if (actual is Map && expected is Map) {
      if (actual.length != expected.length) {
        return false;
      }
      return expected.entries.every(
        (entry) =>
            actual.containsKey(entry.key) &&
            _jsonMatches(actual[entry.key], entry.value),
      );
    }
    if (actual is List && expected is List) {
      return actual.length == expected.length &&
          List.generate(
            actual.length,
            (index) => _jsonMatches(actual[index], expected[index]),
          ).every((matches) => matches);
    }
    return actual == expected;
  }

  void verifyComplete() {
    final priorFailure = _failure;
    if (priorFailure != null) {
      throw StateError(
        'The scripted backend observed an invalid request: $priorFailure',
      );
    }
    if (_exchanges.any((exchange) => !_served.contains(exchange))) {
      throw StateError('The scripted backend has unconsumed exchanges.');
    }
  }

  @override
  void close({bool force = false}) {}
}
