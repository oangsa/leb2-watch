import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:leb2_watch/src/core/security/credential_store.dart';
import 'package:leb2_watch/src/core/security/stored_credentials.dart';

typedef AdapterCallback =
    FutureOr<ResponseBody> Function(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture,
    );

final class CallbackHttpClientAdapter implements HttpClientAdapter {
  CallbackHttpClientAdapter(this.callback);

  final AdapterCallback callback;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return callback(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}

final class MemoryCredentialStore implements CredentialStore {
  MemoryCredentialStore({
    this.sessionCookie = '<SESSION_COOKIE>',
    this.readFailure,
  });

  String? sessionCookie;
  Object? readFailure;
  var sessionReadCount = 0;

  @override
  Future<String?> readSessionCookie() async {
    sessionReadCount += 1;
    final failure = readFailure;
    if (failure != null) {
      throw failure;
    }
    return sessionCookie;
  }

  @override
  Future<void> clear() async {
    sessionCookie = null;
  }

  @override
  Future<void> deleteCredentials() async {}

  @override
  Future<void> deleteSessionCookie() async {
    sessionCookie = null;
  }

  @override
  Future<StoredCredentials?> readCredentials() async => null;

  @override
  Future<void> saveCredentials(StoredCredentials value) async {}

  @override
  Future<void> saveSessionCookie(String value) async {
    sessionCookie = value;
  }
}

ResponseBody jsonResponse(
  Object body, {
  int statusCode = 200,
  String contentType = 'application/json',
  Map<String, List<String>> headers = const {},
}) {
  return ResponseBody.fromString(
    body is String ? body : jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [contentType],
      ...headers,
    },
  );
}

ResponseBody byteResponse(
  List<int> bytes, {
  int statusCode = 200,
  Map<String, List<String>> headers = const {
    Headers.contentTypeHeader: ['application/json'],
  },
}) {
  return ResponseBody.fromBytes(bytes, statusCode, headers: headers);
}
