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
    this.credentials,
    this.readFailure,
  });

  String? sessionCookie;
  StoredCredentials? credentials;
  Object? readFailure;
  var sessionReadCount = 0;
  var sessionWriteCount = 0;
  var credentialReadCount = 0;
  var credentialWriteCount = 0;
  var mutationCount = 0;

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
    credentials = null;
    mutationCount += 1;
  }

  @override
  Future<void> deleteCredentials() async {
    credentials = null;
    mutationCount += 1;
  }

  @override
  Future<void> deleteSessionCookie() async {
    sessionCookie = null;
    mutationCount += 1;
  }

  @override
  Future<StoredCredentials?> readCredentials() async {
    credentialReadCount += 1;
    return credentials;
  }

  @override
  Future<void> saveCredentials(StoredCredentials value) async {
    credentials = value;
    credentialWriteCount += 1;
    mutationCount += 1;
  }

  @override
  Future<void> saveSessionCookie(String value) async {
    sessionCookie = value;
    sessionWriteCount += 1;
    mutationCount += 1;
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
