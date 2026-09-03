import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:leb2_watch/src/core/network/backend_runtime_identity.dart';
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
    this.accessKey = '00000000-0000-4000-8000-000000000001',
    this.sessionCookie = '<SESSION_COOKIE>',
    this.credentials,
    this.readFailure,
    this.accessKeyReadFailure,
  });

  String? accessKey;
  String? sessionCookie;
  StoredCredentials? credentials;
  Object? readFailure;
  Object? accessKeyReadFailure;
  var sessionReadCount = 0;
  var accessKeyReadCount = 0;
  var sessionWriteCount = 0;
  var accessKeyWriteCount = 0;
  var credentialReadCount = 0;
  var credentialWriteCount = 0;
  var mutationCount = 0;

  @override
  Future<String?> readAccessKey() async {
    accessKeyReadCount += 1;
    final failure = accessKeyReadFailure;
    if (failure != null) {
      throw failure;
    }
    return accessKey;
  }

  @override
  Future<void> saveAccessKey(String value) async {
    accessKey = value;
    accessKeyWriteCount += 1;
    mutationCount += 1;
  }

  @override
  Future<void> deleteAccessKey() async {
    accessKey = null;
    mutationCount += 1;
  }

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
    accessKey = null;
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

final class FixedBackendClientIdentityProvider
    implements BackendClientIdentityProvider {
  const FixedBackendClientIdentityProvider({
    this.id = 'device-A',
    this.platform = 'android',
    this.name,
    this.osVersion,
    this.version = '0.5.0',
  });

  final String id;
  final String platform;
  final String? name;
  final String? osVersion;
  final String version;

  @override
  Future<BackendClientIdentity> read() async => BackendClientIdentity(
    device: DeviceIdentity(
      id: id,
      platform: platform,
      name: name,
      osVersion: osVersion,
    ),
    clientVersion: version,
  );
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
