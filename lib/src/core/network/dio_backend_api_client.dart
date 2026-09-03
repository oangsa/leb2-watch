part of 'backend_api_client.dart';

const _maximumInt32 = 2147483647;
const _authorizationHeader = 'Authorization';
const _accessKeyHeader = 'access-key';
const _userIdHeader = 'X-LEB2-USER-ID';
const _deviceIdHeader = 'X-Device-ID';
const _deviceNameHeader = 'X-Device-Name';
const _devicePlatformHeader = 'X-Device-Platform';
const _deviceOsVersionHeader = 'X-Device-OS-Version';
const _clientVersionHeader = 'X-Client-Version';
const _apiV1Prefix = '/api/v1';

final class DioBackendApiClient
    implements
        BackendApiClient,
        BackendLearningActivityClient,
        BackendSessionClient,
        BackendSessionLifecycleClient,
        BackendCompatibilityClient {
  factory DioBackendApiClient({
    required AppConfiguration configuration,
    required CredentialStore credentialStore,
    HttpClientAdapter? httpClientAdapter,
    BackendTransportEventSink? eventSink,
    DateTime Function()? utcNow,
    BackendClientIdentityProvider? runtimeIdentityProvider,
    void Function()? onClientUpdateRequired,
    void Function(Duration skew)? onClockSkewObserved,
  }) {
    final baseUrl = _validatedBaseUrl(configuration);
    final dio = _createDio(baseUrl);
    final sessionDio = _createDio(baseUrl);
    final publicDio = _createDio(baseUrl);
    final runtime =
        runtimeIdentityProvider ??
        RuntimeBackendClientIdentityProvider(
          device: PlatformDeviceIdentityProvider(),
          clientVersion: PackageInfoClientVersionProvider(),
        );
    if (httpClientAdapter != null) {
      dio.httpClientAdapter = httpClientAdapter;
      sessionDio.httpClientAdapter = httpClientAdapter;
      publicDio.httpClientAdapter = httpClientAdapter;
    }
    dio.interceptors.add(_CredentialInterceptor(credentialStore, runtime));
    final now = utcNow ?? DateTime.now;
    for (final client in [dio, sessionDio, publicDio]) {
      client.interceptors.add(_SendTimeInterceptor(now));
    }

    return DioBackendApiClient._(
      dio: dio,
      sessionDio: sessionDio,
      publicDio: publicDio,
      runtimeIdentityProvider: runtime,
      eventSink: configuration.environment == AppEnvironment.development
          ? eventSink ?? _developmentEventSink
          : null,
      utcNow: now,
      onClientUpdateRequired: onClientUpdateRequired,
      onClockSkewObserved: onClockSkewObserved,
    );
  }

  DioBackendApiClient._({
    required this._dio,
    required this._sessionDio,
    required this._publicDio,
    required this._runtimeIdentityProvider,
    required this._eventSink,
    required this._utcNow,
    required this._onClientUpdateRequired,
    required this._onClockSkewObserved,
  });

  final Dio _dio;
  final Dio _sessionDio;
  final Dio _publicDio;
  final BackendClientIdentityProvider _runtimeIdentityProvider;
  final BackendTransportEventSink? _eventSink;
  final DateTime Function() _utcNow;
  final void Function()? _onClientUpdateRequired;
  final void Function(Duration skew)? _onClockSkewObserved;

  @override
  Future<List<Semester>> getSemesters({
    BackendRequestCancellation? cancellation,
  }) {
    return _execute(
      route: BackendTransportRoute.semesters,
      path: '$_apiV1Prefix/Semester',
      cancellation: cancellation,
      mapSuccess: _mapSemesters,
    );
  }

  @override
  Future<List<Semester>> verifySessionCookie({
    required String accessKey,
    required String candidateCookie,
    BackendRequestCancellation? cancellation,
  }) {
    final candidateAccessKey = _requireAccessKey(accessKey);
    _requireNonblankRequest(candidateCookie, 'candidateCookie');
    return _execute(
      dio: _sessionDio,
      route: BackendTransportRoute.sessionVerification,
      path: '$_apiV1Prefix/Semester',
      headers: {
        _accessKeyHeader: candidateAccessKey,
        _authorizationHeader: 'Bearer $candidateCookie',
      },
      cancellation: cancellation,
      requiresRuntimeIdentity: true,
      mapSuccess: _mapSemesters,
    );
  }

  @override
  Future<BackendUserIdentity> authenticateUser({
    required String accessKey,
    required String username,
    required String password,
    BackendRequestCancellation? cancellation,
  }) {
    final candidateAccessKey = _requireAccessKey(accessKey);
    _requireNonblankRequest(username, 'username');
    _requireNonblankRequest(password, 'password');
    final request = BackendCredentialsRequestDto(
      username: username,
      password: password,
    );
    return _execute(
      dio: _sessionDio,
      method: BackendTransportMethod.post,
      route: BackendTransportRoute.userLogin,
      path: '$_apiV1Prefix/User/login',
      headers: {_accessKeyHeader: candidateAccessKey},
      data: request.toJson(),
      cancellation: cancellation,
      requiresRuntimeIdentity: true,
      mapSuccess: _mapUserIdentity,
    );
  }

  @override
  Future<BackendSessionCookie> acquireSessionCookie({
    required String accessKey,
    required String username,
    required String password,
    BackendRequestCancellation? cancellation,
  }) {
    final candidateAccessKey = _requireAccessKey(accessKey);
    _requireNonblankRequest(username, 'username');
    _requireNonblankRequest(password, 'password');
    final request = BackendCredentialsRequestDto(
      username: username,
      password: password,
    );
    return _execute(
      dio: _sessionDio,
      method: BackendTransportMethod.post,
      route: BackendTransportRoute.sessionCookieAcquisition,
      path: '$_apiV1Prefix/User/cookie',
      headers: {_accessKeyHeader: candidateAccessKey},
      data: request.toJson(),
      cancellation: cancellation,
      requiresRuntimeIdentity: true,
      mapSuccess: _mapSessionCookie,
    );
  }

  @override
  Future<List<Course>> getCourses({
    required int semesterId,
    BackendRequestCancellation? cancellation,
  }) {
    _requirePositiveInt32(semesterId, 'semesterId');
    return _execute(
      route: BackendTransportRoute.courses,
      path: '$_apiV1Prefix/Class/$semesterId',
      cancellation: cancellation,
      mapSuccess: (json) => _mapCourses(json, semesterId),
    );
  }

  @override
  Future<AssignmentSnapshot> getSemesterSnapshot({
    required int semesterId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) {
    _requirePositiveInt32(semesterId, 'semesterId');
    _requirePositiveInt32(userId, 'userId');
    return _execute(
      route: BackendTransportRoute.semesterSnapshot,
      path: '/api/v2/Activity/$semesterId/snapshot',
      headers: {_userIdHeader: userId.toString()},
      cancellation: cancellation,
      mapSuccess: (json) => _mapSnapshot(json, semesterId),
    );
  }

  @override
  Future<BackendFileDownload> downloadActivityAttachment({
    required int semesterId,
    required int classId,
    required int activityId,
    required int attachmentId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) {
    _requirePositiveInt32(semesterId, 'semesterId');
    _requirePositiveInt32(classId, 'classId');
    _requirePositiveInt32(activityId, 'activityId');
    _requirePositiveInt32(attachmentId, 'attachmentId');
    _requirePositiveInt32(userId, 'userId');
    return _execute(
      route: BackendTransportRoute.activityAttachment,
      path:
          '/api/v2/Activity/$semesterId/$classId/$activityId'
          '/attachment/$attachmentId',
      headers: {_userIdHeader: userId.toString()},
      cancellation: cancellation,
      mapSuccess: _unusedJsonMapper,
      mapResponse: (response) =>
          _mapDownload(response, fallbackName: 'attachment-$attachmentId'),
    );
  }

  @override
  Future<BackendFileDownload> downloadActivityAttachmentArchive({
    required int semesterId,
    required int classId,
    required int activityId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) {
    _requirePositiveInt32(semesterId, 'semesterId');
    _requirePositiveInt32(classId, 'classId');
    _requirePositiveInt32(activityId, 'activityId');
    _requirePositiveInt32(userId, 'userId');
    return _execute(
      route: BackendTransportRoute.activityAttachmentArchive,
      path:
          '/api/v2/Activity/$semesterId/$classId/$activityId'
          '/attachments/archive',
      headers: {_userIdHeader: userId.toString()},
      cancellation: cancellation,
      mapSuccess: _unusedJsonMapper,
      mapResponse: (response) =>
          _mapDownload(response, fallbackName: 'activity-$activityId.zip'),
    );
  }

  @override
  Future<List<LearningMaterial>> getLearningMaterials({
    required int semesterId,
    required int classId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) {
    _requirePositiveInt32(semesterId, 'semesterId');
    _requirePositiveInt32(classId, 'classId');
    _requirePositiveInt32(userId, 'userId');
    return _execute(
      route: BackendTransportRoute.learningMaterials,
      path: '/api/v2/LearningActivity/$semesterId/$classId',
      headers: {_userIdHeader: userId.toString()},
      cancellation: cancellation,
      mapSuccess: (json) => _mapLearningMaterials(json, classId),
    );
  }

  @override
  Future<BackendFileDownload> downloadLearningMaterialAttachment({
    required int semesterId,
    required int classId,
    required int materialId,
    required int attachmentId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) {
    _requirePositiveInt32(semesterId, 'semesterId');
    _requirePositiveInt32(classId, 'classId');
    _requirePositiveInt32(materialId, 'materialId');
    _requirePositiveInt32(attachmentId, 'attachmentId');
    _requirePositiveInt32(userId, 'userId');
    return _execute(
      route: BackendTransportRoute.learningMaterialAttachment,
      path:
          '/api/v2/LearningActivity/$semesterId/$classId/$materialId'
          '/attachment/$attachmentId',
      headers: {_userIdHeader: userId.toString()},
      cancellation: cancellation,
      mapSuccess: _unusedJsonMapper,
      mapResponse: (response) =>
          _mapDownload(response, fallbackName: 'attachment-$attachmentId'),
    );
  }

  @override
  Future<BackendFileDownload> downloadLearningMaterialAttachmentArchive({
    required int semesterId,
    required int classId,
    required int materialId,
    required int userId,
    BackendRequestCancellation? cancellation,
  }) {
    _requirePositiveInt32(semesterId, 'semesterId');
    _requirePositiveInt32(classId, 'classId');
    _requirePositiveInt32(materialId, 'materialId');
    _requirePositiveInt32(userId, 'userId');
    return _execute(
      route: BackendTransportRoute.learningMaterialAttachmentArchive,
      path:
          '/api/v2/LearningActivity/$semesterId/$classId/$materialId'
          '/attachments/archive',
      headers: {_userIdHeader: userId.toString()},
      cancellation: cancellation,
      mapSuccess: _unusedJsonMapper,
      mapResponse: (response) =>
          _mapDownload(response, fallbackName: 'material-$materialId.zip'),
    );
  }

  @override
  Future<void> logout({
    required String accessKey,
    BackendRequestCancellation? cancellation,
  }) {
    final candidateAccessKey = _requireAccessKey(accessKey);
    return _execute<void>(
      dio: _sessionDio,
      method: BackendTransportMethod.post,
      route: BackendTransportRoute.userLogout,
      path: '$_apiV1Prefix/User/logout',
      headers: {_accessKeyHeader: candidateAccessKey},
      cancellation: cancellation,
      requiresRuntimeIdentity: true,
      expectedStatusCode: 204,
      mapSuccess: (_) {},
    );
  }

  @override
  Future<BackendApiMetadata> getMetadata({
    BackendRequestCancellation? cancellation,
  }) {
    return _execute(
      dio: _publicDio,
      route: BackendTransportRoute.metadata,
      path: '$_apiV1Prefix/meta',
      cancellation: cancellation,
      mapSuccess: _mapMetadata,
    );
  }

  Future<T> _execute<T>({
    required BackendTransportRoute route,
    required String path,
    required T Function(Object? json) mapSuccess,
    Dio? dio,
    BackendTransportMethod method = BackendTransportMethod.get,
    Map<String, Object?>? headers,
    Object? data,
    BackendRequestCancellation? cancellation,
    bool requiresRuntimeIdentity = false,
    int expectedStatusCode = 200,
    // Set for responses that are not JSON, such as file downloads, so the body
    // is read as bytes instead of being decoded. Failures still map through the
    // same error path, which does decode the body.
    T Function(Response<List<int>> response)? mapResponse,
  }) async {
    final stopwatch = Stopwatch()..start();
    int? statusCode;
    var outcome = BackendTransportOutcome.unknownFailure;
    void Function()? disposeCancellationListener;

    try {
      if (cancellation?.isCancelled ?? false) {
        throw const BackendTransportException(
          kind: BackendTransportFailureKind.cancelled,
        );
      }

      final cancelToken = CancelToken();
      if (cancellation != null) {
        disposeCancellationListener = cancellation._registerListener(() {
          if (!cancelToken.isCancelled) {
            cancelToken.cancel();
          }
        });
      }

      final client = dio ?? _dio;
      final runtimeHeaders = requiresRuntimeIdentity
          ? await _readRuntimeHeaders(_runtimeIdentityProvider)
          : const <String, String>{};
      final options = Options(
        method: method.name.toUpperCase(),
        headers: {
          if (method == BackendTransportMethod.post)
            Headers.contentTypeHeader: Headers.jsonContentType,
          ...runtimeHeaders,
          ...?headers,
        },
      );
      final response = await client.request<List<int>>(
        path,
        data: data,
        options: options,
        cancelToken: cancelToken,
      );
      _observeServerClock(response);
      statusCode = response.statusCode;
      if (statusCode == null) {
        throw const BackendTransportException(
          kind: BackendTransportFailureKind.invalidResponse,
          invalidResponseReason: BackendInvalidResponseReason.wrongShape,
        );
      }

      if (statusCode == expectedStatusCode && expectedStatusCode == 204) {
        if (response.data != null && response.data!.isNotEmpty) {
          throw const BackendTransportException(
            kind: BackendTransportFailureKind.invalidResponse,
            invalidResponseReason: BackendInvalidResponseReason.wrongShape,
          );
        }
        final result = mapSuccess(null);
        outcome = BackendTransportOutcome.success;
        return result;
      }
      if (statusCode != expectedStatusCode) {
        if (statusCode >= 200 && statusCode < 400) {
          throw const BackendTransportException(
            kind: BackendTransportFailureKind.invalidResponse,
            invalidResponseReason: BackendInvalidResponseReason.wrongShape,
          );
        }
        final decoded = _decodeResponse(response);
        throw _mapHttpError(response, decoded, statusCode);
      }

      if (mapResponse != null) {
        try {
          final result = mapResponse(response);
          outcome = BackendTransportOutcome.success;
          return result;
        } on Object {
          throw const BackendTransportException(
            kind: BackendTransportFailureKind.invalidResponse,
            invalidResponseReason: BackendInvalidResponseReason.wrongShape,
          );
        }
      }

      final decoded = _decodeResponse(response);

      try {
        final result = mapSuccess(decoded);
        outcome = BackendTransportOutcome.success;
        return result;
      } on _ResponseShapeException {
        throw const BackendTransportException(
          kind: BackendTransportFailureKind.invalidResponse,
          invalidResponseReason: BackendInvalidResponseReason.wrongShape,
        );
      } on _ResponseInvariantException {
        throw const BackendTransportException(
          kind: BackendTransportFailureKind.invalidResponse,
          invalidResponseReason:
              BackendInvalidResponseReason.invariantViolation,
        );
      } on Object {
        throw const BackendTransportException(
          kind: BackendTransportFailureKind.invalidResponse,
          invalidResponseReason: BackendInvalidResponseReason.wrongShape,
        );
      }
    } on BackendTransportException catch (error) {
      outcome = _eventOutcome(error.kind);
      rethrow;
    } on DioException catch (error) {
      final mapped = _mapDioFailure(error);
      outcome = _eventOutcome(mapped.kind);
      throw mapped;
    } on Object {
      outcome = BackendTransportOutcome.unknownFailure;
      throw const BackendTransportException(
        kind: BackendTransportFailureKind.unknownFailure,
      );
    } finally {
      disposeCancellationListener?.call();
      stopwatch.stop();
      _emitEvent(
        BackendTransportEvent(
          method: method,
          route: route,
          statusCode: statusCode,
          elapsed: stopwatch.elapsed,
          outcome: outcome,
        ),
      );
    }
  }

  /// Reports how far this device's clock sits from the backend's, measured
  /// against the round-trip midpoint. Every response carries a `Date` header,
  /// so this needs no extra request. Non-2xx responses are measured too: the
  /// client accepts every status, so they arrive here rather than as a
  /// [DioException], and their `Date` header is just as good.
  void _observeServerClock(Response<List<int>> response) {
    final observer = _onClockSkewObserved;
    if (observer == null) {
      return;
    }
    final sentAtUtc = response.requestOptions.extra[_sentAtUtcExtraKey];
    if (sentAtUtc is! DateTime) {
      return;
    }
    // A cache serves the `Date` it stored the response under, so the reading
    // would report how stale the entry is rather than how wrong this clock is.
    // A cache that reveals itself at all does so through `Age`.
    //
    // Tested for a positive value rather than for presence: a CDN that stamps
    // `Age: 0` on every miss is common, and skipping those would disable the
    // measurement everywhere, silently, with nothing downstream able to tell
    // "this clock is fine" from "this clock was never read". A zero age is a
    // response served fresh, and it can be off by at most the whole second
    // the header is truncated to — far inside [clockSkewMinimumCorrection].
    final age = int.tryParse(response.headers.value('age') ?? '');
    if (age != null && age > 0) {
      return;
    }
    final header = response.headers.value('date');
    if (header == null) {
      return;
    }
    final DateTime serverUtc;
    try {
      serverUtc = HttpDate.parse(header);
    } on Object {
      return;
    }
    final skew = resolveClockSkew(
      sentAtUtc: sentAtUtc,
      receivedAtUtc: _utcNow().toUtc(),
      serverUtc: serverUtc,
    );
    if (skew == null) {
      return;
    }
    try {
      observer(skew);
    } on Object {
      // Clock correction is an optimisation; it must never fail a request.
    }
  }

  Object? _decodeResponse(Response<List<int>> response) {
    final contentTypes = response.headers[Headers.contentTypeHeader];
    if (contentTypes == null || contentTypes.isEmpty) {
      throw const BackendTransportException(
        kind: BackendTransportFailureKind.invalidResponse,
        invalidResponseReason: BackendInvalidResponseReason.missingContentType,
      );
    }
    if (contentTypes.length != 1) {
      throw const BackendTransportException(
        kind: BackendTransportFailureKind.invalidResponse,
        invalidResponseReason:
            BackendInvalidResponseReason.multipleContentTypes,
      );
    }

    final DioMediaType mediaType;
    try {
      mediaType = DioMediaType.parse(contentTypes.single);
    } on Object {
      throw const BackendTransportException(
        kind: BackendTransportFailureKind.invalidResponse,
        invalidResponseReason:
            BackendInvalidResponseReason.malformedContentType,
      );
    }

    final type = mediaType.type.toLowerCase();
    final subtype = mediaType.subtype.toLowerCase();
    final isStructuredJson =
        subtype.endsWith('+json') && subtype.length > '+json'.length;
    if (type != 'application' || (subtype != 'json' && !isStructuredJson)) {
      throw const BackendTransportException(
        kind: BackendTransportFailureKind.invalidResponse,
        invalidResponseReason:
            BackendInvalidResponseReason.unsupportedContentType,
      );
    }

    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw const BackendTransportException(
        kind: BackendTransportFailureKind.invalidResponse,
        invalidResponseReason: BackendInvalidResponseReason.emptyBody,
      );
    }

    final String source;
    try {
      source = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw const BackendTransportException(
        kind: BackendTransportFailureKind.invalidResponse,
        invalidResponseReason: BackendInvalidResponseReason.malformedUtf8,
      );
    }

    try {
      final decoded = jsonDecode(source);
      if (decoded == null) {
        throw const BackendTransportException(
          kind: BackendTransportFailureKind.invalidResponse,
          invalidResponseReason: BackendInvalidResponseReason.wrongShape,
        );
      }
      return decoded;
    } on BackendTransportException {
      rethrow;
    } on FormatException {
      throw const BackendTransportException(
        kind: BackendTransportFailureKind.invalidResponse,
        invalidResponseReason: BackendInvalidResponseReason.malformedJson,
      );
    }
  }

  BackendTransportException _mapHttpError(
    Response<List<int>> response,
    Object? decoded,
    int statusCode,
  ) {
    try {
      final map = _asJsonObject(decoded);
      final String responseCode;
      final BackendErrorEnvelopeKind envelopeKind;

      if (map.containsKey('statusCode') ||
          map.containsKey('validationErrors')) {
        final error = ValidationBackendErrorDto.fromJson(map);
        _validateValidationError(error, statusCode);
        responseCode = error.responseCode;
        envelopeKind = BackendErrorEnvelopeKind.validation;
      } else {
        final error = StandardBackendErrorDto.fromJson(map);
        _validateStandardError(error);
        responseCode = error.responseCode;
        envelopeKind = BackendErrorEnvelopeKind.standard;
      }

      final evidence = BackendHttpErrorEvidence(
        statusCode: statusCode,
        responseCode: responseCode,
        envelopeKind: envelopeKind,
        retryAfter: _parseRetryAfterHeader(response.headers),
        hasBearerChallenge: _hasBearerChallenge(response.headers),
      );
      if (statusCode == 426 && responseCode == 'CLIENT_UPDATE_REQUIRED') {
        try {
          _onClientUpdateRequired?.call();
        } on Object {
          // Compatibility state must never change transport behavior.
        }
      }
      return BackendTransportException(
        kind: BackendTransportFailureKind.httpResponse,
        httpError: evidence,
      );
    } on BackendTransportException {
      rethrow;
    } on Object {
      return const BackendTransportException(
        kind: BackendTransportFailureKind.invalidResponse,
        invalidResponseReason:
            BackendInvalidResponseReason.invalidErrorEnvelope,
      );
    }
  }

  Duration? _parseRetryAfterHeader(Headers headers) {
    final values = headers['retry-after'];
    if (values == null || values.length != 1) {
      return null;
    }
    return parseRetryAfter(values.single, nowUtc: _utcNow().toUtc());
  }

  bool _hasBearerChallenge(Headers headers) {
    final values = headers['www-authenticate'];
    if (values == null) {
      return false;
    }
    return values.any((value) {
      final match = RegExp(
        r'^\s*Bearer(?:\s|$)',
        caseSensitive: false,
      ).firstMatch(value);
      return match != null;
    });
  }

  BackendTransportException _mapDioFailure(DioException error) {
    final marker = error.error;
    if (marker is _CredentialFailure) {
      return BackendTransportException(kind: marker.kind);
    }

    final kind = switch (error.type) {
      DioExceptionType.connectionTimeout =>
        BackendTransportFailureKind.connectionTimeout,
      DioExceptionType.sendTimeout => BackendTransportFailureKind.sendTimeout,
      DioExceptionType.receiveTimeout =>
        BackendTransportFailureKind.receiveTimeout,
      DioExceptionType.transformTimeout =>
        BackendTransportFailureKind.transformTimeout,
      DioExceptionType.connectionError =>
        BackendTransportFailureKind.connectionError,
      DioExceptionType.badCertificate =>
        BackendTransportFailureKind.badCertificate,
      DioExceptionType.cancel => BackendTransportFailureKind.cancelled,
      DioExceptionType.badResponse =>
        BackendTransportFailureKind.invalidResponse,
      DioExceptionType.unknown => BackendTransportFailureKind.unknownFailure,
    };
    return BackendTransportException(
      kind: kind,
      invalidResponseReason: error.type == DioExceptionType.badResponse
          ? BackendInvalidResponseReason.wrongShape
          : null,
    );
  }

  void _emitEvent(BackendTransportEvent event) {
    try {
      _eventSink?.call(event);
    } on Object {
      // Observability must never change transport behavior.
    }
  }

  @override
  String toString() => 'DioBackendApiClient(redacted: true)';
}

Dio _createDio(String baseUrl) {
  return Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      responseType: ResponseType.bytes,
      followRedirects: false,
      maxRedirects: 0,
      headers: const {Headers.acceptHeader: 'application/json'},
      validateStatus: (_) => true,
    ),
  );
}

const _sentAtUtcExtraKey = 'leb2_watch_sent_at_utc';

/// Stamps the moment a request actually goes out, for the clock-skew reading.
///
/// Added last, so it runs after [_CredentialInterceptor] and its two OS
/// secure-storage reads — work that happens entirely on this device before a
/// byte is sent. Timing from before the interceptor chain would fold that into
/// the measured round trip, which both biases the midpoint towards "backend
/// ahead" and eats the round-trip budget the reading is judged against.
final class _SendTimeInterceptor extends Interceptor {
  _SendTimeInterceptor(this._utcNow);

  final DateTime Function() _utcNow;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_sentAtUtcExtraKey] = _utcNow().toUtc();
    handler.next(options);
  }
}

final class _CredentialInterceptor extends Interceptor {
  _CredentialInterceptor(this._credentialStore, this._runtimeIdentityProvider);

  final CredentialStore _credentialStore;
  final BackendClientIdentityProvider _runtimeIdentityProvider;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final String? accessKey;
    try {
      accessKey = await _credentialStore.readAccessKey();
    } on Object {
      handler.reject(
        DioException(
          requestOptions: options,
          error: const _CredentialFailure(
            BackendTransportFailureKind.accessKeyStoreUnavailable,
          ),
        ),
      );
      return;
    }

    if (accessKey == null || accessKey.trim().isEmpty) {
      handler.reject(
        DioException(
          requestOptions: options,
          error: const _CredentialFailure(
            BackendTransportFailureKind.missingAccessKey,
          ),
        ),
      );
      return;
    }
    if (normalizeAccessKey(accessKey) == null) {
      handler.reject(
        DioException(
          requestOptions: options,
          error: const _CredentialFailure(
            BackendTransportFailureKind.invalidAccessKey,
          ),
        ),
      );
      return;
    }

    final String? cookie;
    try {
      cookie = await _credentialStore.readSessionCookie();
    } on Object {
      handler.reject(
        DioException(
          requestOptions: options,
          error: const _CredentialFailure(
            BackendTransportFailureKind.credentialAccessFailed,
          ),
        ),
      );
      return;
    }

    if (cookie == null || cookie.trim().isEmpty) {
      handler.reject(
        DioException(
          requestOptions: options,
          error: const _CredentialFailure(
            BackendTransportFailureKind.missingCredential,
          ),
        ),
      );
      return;
    }

    try {
      final runtimeHeaders = await _readRuntimeHeaders(
        _runtimeIdentityProvider,
      );
      options.headers.addAll(runtimeHeaders);
    } on BackendTransportException catch (error) {
      handler.reject(
        DioException(
          requestOptions: options,
          error: _CredentialFailure(error.kind),
        ),
      );
      return;
    } on Object {
      handler.reject(
        DioException(
          requestOptions: options,
          error: const _CredentialFailure(
            BackendTransportFailureKind.deviceIdentityUnavailable,
          ),
        ),
      );
      return;
    }

    options.headers[_accessKeyHeader] = accessKey.trim();
    options.headers[_authorizationHeader] = 'Bearer $cookie';
    handler.next(options);
  }
}

final class _CredentialFailure {
  const _CredentialFailure(this.kind);

  final BackendTransportFailureKind kind;

  @override
  String toString() => '_CredentialFailure(redacted: true)';
}

Future<Map<String, String>> _readRuntimeHeaders(
  BackendClientIdentityProvider provider,
) async {
  final BackendClientIdentity identity;
  try {
    identity = await provider.read();
  } on DeviceIdentityException catch (error) {
    throw BackendTransportException(
      kind: switch (error.reason) {
        DeviceIdentityFailureReason.missing =>
          BackendTransportFailureKind.deviceIdentityMissing,
        DeviceIdentityFailureReason.invalid =>
          BackendTransportFailureKind.deviceIdentityInvalid,
        DeviceIdentityFailureReason.unavailable =>
          BackendTransportFailureKind.deviceIdentityUnavailable,
      },
    );
  } on ClientVersionException catch (error) {
    throw BackendTransportException(
      kind: switch (error.reason) {
        ClientVersionFailureReason.missing =>
          BackendTransportFailureKind.clientVersionMissing,
        ClientVersionFailureReason.invalid =>
          BackendTransportFailureKind.clientVersionInvalid,
        ClientVersionFailureReason.unavailable =>
          BackendTransportFailureKind.clientVersionUnavailable,
      },
    );
  } on Object {
    throw const BackendTransportException(
      kind: BackendTransportFailureKind.deviceIdentityUnavailable,
    );
  }

  final deviceId = identity.device.id.trim();
  final platform = identity.device.platform.trim();
  if (deviceId.isEmpty || platform.isEmpty) {
    throw const BackendTransportException(
      kind: BackendTransportFailureKind.deviceIdentityInvalid,
    );
  }

  final SemanticVersion version;
  try {
    version = SemanticVersion.parse(identity.clientVersion);
  } on FormatException {
    throw const BackendTransportException(
      kind: BackendTransportFailureKind.clientVersionInvalid,
    );
  }
  final clientVersion =
      version.coreVersion +
      (version.prerelease.isEmpty ? '' : '-${version.prerelease.join('.')}');
  final name = identity.device.name?.trim();
  final osVersion = identity.device.osVersion?.trim();
  return {
    _deviceIdHeader: deviceId,
    _devicePlatformHeader: platform,
    _clientVersionHeader: clientVersion,
    if (name != null && name.isNotEmpty) _deviceNameHeader: name,
    if (osVersion != null && osVersion.isNotEmpty)
      _deviceOsVersionHeader: osVersion,
  };
}

List<Semester> _mapSemesters(Object? json) {
  final values = _asJsonList(json);
  final seen = <int>{};
  final semesters = <Semester>[];

  for (final value in values) {
    final dto = SemesterDto.fromJson(_asJsonObject(value));
    _requireResponsePositiveInt32(dto.id);
    final name = dto.name.trim();
    _requireNonblank(name);
    if (!seen.add(dto.id)) {
      throw const _ResponseInvariantException();
    }
    semesters.add(Semester(id: dto.id, name: name));
  }
  return List<Semester>.unmodifiable(semesters);
}

BackendUserIdentity _mapUserIdentity(Object? json) {
  final dto = BackendUserProfileDto.fromJson(_asJsonObject(json));
  _requireResponsePositiveInt32(dto.id);
  _requireNonblank(dto.kmuttId);
  return BackendUserIdentity(id: dto.id);
}

BackendSessionCookie _mapSessionCookie(Object? json) {
  final dto = BackendCookieDto.fromJson(_asJsonObject(json));
  _requireNonblank(dto.cookie);
  return BackendSessionCookie(dto.cookie);
}

BackendApiMetadata _mapMetadata(Object? json) {
  final map = _asJsonObject(json);
  final apiVersion = map['apiVersion'];
  final minimumSource = map['minimumClientVersion'];
  final latestSource = map['latestClientVersion'];
  final downloadSource = map['downloadUrl'];
  if (apiVersion is! int ||
      minimumSource is! String ||
      latestSource is! String ||
      downloadSource is! String) {
    throw const _ResponseShapeException();
  }

  final SemanticVersion minimum;
  final SemanticVersion latest;
  try {
    minimum = SemanticVersion.parse(minimumSource);
    latest = SemanticVersion.parse(latestSource);
  } on FormatException {
    throw const _ResponseInvariantException();
  }
  final downloadUrl = Uri.tryParse(downloadSource);
  if (downloadUrl == null ||
      !downloadUrl.isAbsolute ||
      downloadUrl.host.isEmpty ||
      downloadUrl.userInfo.isNotEmpty ||
      (downloadUrl.scheme != 'http' && downloadUrl.scheme != 'https') ||
      minimum > latest) {
    throw const _ResponseInvariantException();
  }

  return BackendApiMetadata(
    apiVersion: apiVersion,
    minimumClientVersion: minimum,
    latestClientVersion: latest,
    downloadUrl: downloadUrl,
  );
}

List<Course> _mapCourses(Object? json, int semesterId) {
  final values = _asJsonList(json);
  final seen = <int>{};
  final courses = <Course>[];

  for (final value in values) {
    final dto = CourseDto.fromJson(_asJsonObject(value));
    _requireResponsePositiveInt32(dto.id);
    _requireNonblank(dto.name);
    if (!seen.add(dto.id)) {
      throw const _ResponseInvariantException();
    }
    courses.add(Course(semesterId: semesterId, id: dto.id, name: dto.name));
  }
  return List<Course>.unmodifiable(courses);
}

List<LearningMaterial> _mapLearningMaterials(
  Object? json,
  int requestedClassId,
) {
  final values = _asJsonList(json);
  final seenMaterials = <int>{};
  final materials = <LearningMaterial>[];

  for (final value in values) {
    final map = _asJsonObject(value);
    final id = _requiredJsonInt(map['id']);
    final classId = _requiredJsonInt(map['classId']);
    final title = _requiredJsonString(map['title']).trim();
    final description = _requiredJsonString(map['description']);
    final fileCount = _requiredJsonInt(map['fileCount']);
    final fileValues = _asJsonList(map['fileMaterials']);

    _requireResponsePositiveInt32(id);
    _requireResponsePositiveInt32(classId);
    if (classId != requestedClassId ||
        !_isNonblank(title) ||
        fileCount < 0 ||
        !seenMaterials.add(id)) {
      throw const _ResponseInvariantException();
    }

    final seenFiles = <int>{};
    final files = <LearningMaterialFile>[];
    for (final fileValue in fileValues) {
      final fileMap = _asJsonObject(fileValue);
      final fileId = _requiredJsonInt(fileMap['id']);
      final displayName = _requiredJsonString(fileMap['displayName']).trim();
      final fileSize = _requiredJsonString(fileMap['fileSize']).trim();
      final fileType = _requiredJsonString(fileMap['fileType']).trim();

      _requireResponsePositiveInt32(fileId);
      if (!_isNonblank(displayName) || !seenFiles.add(fileId)) {
        throw const _ResponseInvariantException();
      }
      files.add(
        LearningMaterialFile(
          id: fileId,
          displayName: displayName,
          fileSize: fileSize,
          fileType: fileType,
        ),
      );
    }

    materials.add(
      LearningMaterial(
        id: id,
        classId: classId,
        title: title,
        description: description,
        fileCount: fileCount,
        fileMaterials: List<LearningMaterialFile>.unmodifiable(files),
      ),
    );
  }

  return List<LearningMaterial>.unmodifiable(materials);
}

AssignmentSnapshot _mapSnapshot(Object? json, int requestedSemesterId) {
  final dto = SemesterSnapshotDto.fromJson(_asJsonObject(json));
  _requireResponsePositiveInt32(dto.semesterId);
  if (dto.semesterId != requestedSemesterId) {
    throw const _ResponseInvariantException();
  }

  final seenCourses = <int>{};
  final seenActivities = <int>{};
  final courses = <CourseAssignments>[];

  for (final courseDto in dto.classes) {
    _requireResponsePositiveInt32(courseDto.id);
    _requireNonblank(courseDto.name);
    if (!seenCourses.add(courseDto.id)) {
      throw const _ResponseInvariantException();
    }

    final activities = <AssignmentActivity>[];
    for (final activityDto in courseDto.activities) {
      _requireResponsePositiveInt32(activityDto.id);
      _requireNonblank(activityDto.title);
      if (activityDto.classId != courseDto.id ||
          !seenActivities.add(activityDto.id)) {
        throw const _ResponseInvariantException();
      }
      activities.add(_mapActivity(activityDto, dto.semesterId));
    }

    courses.add(
      CourseAssignments(
        course: Course(
          semesterId: dto.semesterId,
          id: courseDto.id,
          name: courseDto.name,
        ),
        activities: activities,
      ),
    );
  }

  return AssignmentSnapshot(semesterId: dto.semesterId, courses: courses);
}

AssignmentActivity _mapActivity(ActivityDto dto, int semesterId) {
  _requireNullableUtcTimestamp(dto.startDate);
  _requireNullableUtcTimestamp(dto.dueDate);
  _requireUtcTimestamp(dto.createdAt);
  _requireNullableUtcTimestamp(dto.lastDueDateNotificationDate);
  _requireNullableUtcTimestamp(dto.lastStatusChangeNotificationDate);

  final submittedAtDto = dto.activitySubmissionSubmittedAt;
  final ActivitySubmissionTimestamp? submittedAt;
  if (submittedAtDto == null) {
    submittedAt = null;
  } else {
    _requireSubmissionTimestampDate(submittedAtDto.date);
    submittedAt = ActivitySubmissionTimestamp(
      date: submittedAtDto.date,
      timezoneType: submittedAtDto.timezoneType,
      timezone: submittedAtDto.timezone,
    );
  }

  return AssignmentActivity(
    semesterId: semesterId,
    id: dto.id,
    userId: dto.userId,
    classId: dto.classId,
    advStarred: dto.advStarred,
    groupType: dto.groupType,
    type: dto.type,
    peerAssessment: dto.peerAssessment,
    isAllowRepeat: dto.isAllowRepeat,
    title: dto.title,
    description: dto.description,
    startDate: dto.startDate,
    dueDate: dto.dueDate,
    editGroupMode: dto.editGroupMode,
    createdAt: dto.createdAt,
    user: dto.user,
    activitySubmissionId: dto.activitySubmissionId,
    classUserId: dto.classUserId,
    activityGroupId: dto.activityGroupId,
    activityGroupName: dto.activityGroupName,
    activitySubmissionSubmittedAt: submittedAt,
    dueDateExceed: dto.dueDateExceed,
    quizSubmissionIsSubmitted: dto.quizSubmissionIsSubmitted,
    countGroupMember: dto.countGroupMember,
    activitySubmissionIsLate: dto.activitySubmissionIsLate,
    fileActivitiesJson: _canonicalJsonArray(dto.fileActivities),
    questions: dto.questions,
    submissionsJson: _canonicalJsonArray(dto.submissions),
    lastDueDateNotificationDate: dto.lastDueDateNotificationDate,
    lastStatusChangeNotificationDate: dto.lastStatusChangeNotificationDate,
    previousSubmissionStatus: dto.previousSubmissionStatus,
  );
}

List<Object?> _asJsonList(Object? value) {
  if (value is! List<Object?>) {
    throw const _ResponseShapeException();
  }
  return value;
}

Map<String, dynamic> _asJsonObject(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const _ResponseShapeException();
  }
  return value;
}

void _requirePositiveInt32(int value, String name) {
  if (value <= 0 || value > _maximumInt32) {
    throw ArgumentError('$name must be a positive int32.');
  }
}

void _requireNonblankRequest(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError('$name must not be blank.');
  }
}

String _requireAccessKey(String value) {
  final normalized = normalizeAccessKey(value);
  if (normalized == null) {
    throw ArgumentError('accessKey must be one valid UUID.');
  }
  return normalized;
}

void _requireResponsePositiveInt32(int value) {
  if (value <= 0 || value > _maximumInt32) {
    throw const _ResponseInvariantException();
  }
}

int _requiredJsonInt(Object? value) {
  if (value is! int) {
    throw const _ResponseShapeException();
  }
  return value;
}

String _requiredJsonString(Object? value) {
  if (value is! String) {
    throw const _ResponseShapeException();
  }
  return value;
}

bool _isNonblank(String value) => value.trim().isNotEmpty;

void _requireNonblank(String value) {
  if (value.trim().isEmpty) {
    throw const _ResponseInvariantException();
  }
}

final _submissionTimestampDatePattern = RegExp(
  r'^[+-]?\d{4,6}-\d{2}-\d{2}[T ]\d{2}:\d{2}'
  r'(?::\d{2}(?:\.\d{1,9})?)?(?:Z|[+-]\d{2}:\d{2})?$',
);

void _requireSubmissionTimestampDate(String value) {
  if (!_submissionTimestampDatePattern.hasMatch(value) ||
      DateTime.tryParse(value) == null) {
    throw const _ResponseInvariantException();
  }
}

void _validateStandardError(StandardBackendErrorDto error) {
  _requireNonblank(error.message);
  _requireNonblank(error.responseCode);
  _requireUtcTimestamp(error.timestamp);
}

void _validateValidationError(
  ValidationBackendErrorDto error,
  int responseStatus,
) {
  _requireNonblank(error.message);
  _requireNonblank(error.responseCode);
  _requireUtcTimestamp(error.timestamp);
  if (error.statusCode != responseStatus) {
    throw const _ResponseInvariantException();
  }
}

void _requireUtcTimestamp(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null ||
      !RegExp(r'(?:Z|[+-]00:00)$', caseSensitive: false).hasMatch(value)) {
    throw const _ResponseInvariantException();
  }
}

void _requireNullableUtcTimestamp(String? value) {
  if (value != null) {
    _requireUtcTimestamp(value);
  }
}

String _canonicalJsonArray(List<Map<String, Object?>> values) {
  return jsonEncode(values.map<Object?>(_canonicalizeJson).toList());
}

Object? _canonicalizeJson(Object? value) {
  if (value == null || value is bool || value is String || value is int) {
    return value;
  }
  if (value is double && value.isFinite) {
    return value;
  }
  if (value is List<Object?>) {
    return value.map<Object?>(_canonicalizeJson).toList();
  }
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalizeJson(value[key]),
    };
  }
  throw const _ResponseShapeException();
}

BackendTransportOutcome _eventOutcome(BackendTransportFailureKind kind) {
  return switch (kind) {
    BackendTransportFailureKind.missingAccessKey =>
      BackendTransportOutcome.missingAccessKey,
    BackendTransportFailureKind.invalidAccessKey =>
      BackendTransportOutcome.invalidAccessKey,
    BackendTransportFailureKind.accessKeyStoreUnavailable =>
      BackendTransportOutcome.accessKeyStoreUnavailable,
    BackendTransportFailureKind.missingCredential =>
      BackendTransportOutcome.missingCredential,
    BackendTransportFailureKind.credentialAccessFailed =>
      BackendTransportOutcome.credentialAccessFailed,
    BackendTransportFailureKind.cancelled => BackendTransportOutcome.cancelled,
    BackendTransportFailureKind.connectionTimeout =>
      BackendTransportOutcome.connectionTimeout,
    BackendTransportFailureKind.sendTimeout =>
      BackendTransportOutcome.sendTimeout,
    BackendTransportFailureKind.receiveTimeout =>
      BackendTransportOutcome.receiveTimeout,
    BackendTransportFailureKind.transformTimeout =>
      BackendTransportOutcome.transformTimeout,
    BackendTransportFailureKind.connectionError =>
      BackendTransportOutcome.connectionError,
    BackendTransportFailureKind.badCertificate =>
      BackendTransportOutcome.badCertificate,
    BackendTransportFailureKind.invalidResponse =>
      BackendTransportOutcome.invalidResponse,
    BackendTransportFailureKind.httpResponse =>
      BackendTransportOutcome.httpResponse,
    BackendTransportFailureKind.deviceIdentityMissing =>
      BackendTransportOutcome.deviceIdentityMissing,
    BackendTransportFailureKind.deviceIdentityInvalid =>
      BackendTransportOutcome.deviceIdentityInvalid,
    BackendTransportFailureKind.deviceIdentityUnavailable =>
      BackendTransportOutcome.deviceIdentityUnavailable,
    BackendTransportFailureKind.clientVersionMissing =>
      BackendTransportOutcome.clientVersionMissing,
    BackendTransportFailureKind.clientVersionInvalid =>
      BackendTransportOutcome.clientVersionInvalid,
    BackendTransportFailureKind.clientVersionUnavailable =>
      BackendTransportOutcome.clientVersionUnavailable,
    BackendTransportFailureKind.unknownFailure =>
      BackendTransportOutcome.unknownFailure,
  };
}

String _validatedBaseUrl(AppConfiguration configuration) {
  if (configuration.backendBaseUrl.isEmpty) {
    throw const BackendApiConfigurationException(
      BackendApiConfigurationFailureReason.emptyBaseUrl,
    );
  }

  final Uri uri;
  try {
    uri = Uri.parse(configuration.backendBaseUrl);
  } on FormatException {
    throw const BackendApiConfigurationException(
      BackendApiConfigurationFailureReason.invalidBaseUrl,
    );
  }

  if (uri.scheme.isEmpty) {
    throw const BackendApiConfigurationException(
      BackendApiConfigurationFailureReason.invalidBaseUrl,
    );
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    throw const BackendApiConfigurationException(
      BackendApiConfigurationFailureReason.unsupportedScheme,
    );
  }
  if (uri.host.isEmpty) {
    throw const BackendApiConfigurationException(
      BackendApiConfigurationFailureReason.missingHost,
    );
  }
  if (uri.userInfo.isNotEmpty) {
    throw const BackendApiConfigurationException(
      BackendApiConfigurationFailureReason.userInfoNotAllowed,
    );
  }
  if (uri.hasQuery) {
    throw const BackendApiConfigurationException(
      BackendApiConfigurationFailureReason.queryNotAllowed,
    );
  }
  if (uri.hasFragment) {
    throw const BackendApiConfigurationException(
      BackendApiConfigurationFailureReason.fragmentNotAllowed,
    );
  }
  if (uri.path.isNotEmpty && uri.path != '/') {
    throw const BackendApiConfigurationException(
      BackendApiConfigurationFailureReason.pathNotAllowed,
    );
  }
  if (configuration.environment == AppEnvironment.production &&
      scheme != 'https') {
    throw const BackendApiConfigurationException(
      BackendApiConfigurationFailureReason.insecureProductionUrl,
    );
  }

  return uri.replace(path: '/').toString();
}

void _developmentEventSink(BackendTransportEvent event) {
  debugPrint(event.toString());
}

final class _ResponseShapeException implements Exception {
  const _ResponseShapeException();
}

final class _ResponseInvariantException implements Exception {
  const _ResponseInvariantException();
}

/// Placeholder for downloads, whose bodies are bytes rather than JSON and are
/// mapped from the response itself.
Never _unusedJsonMapper(Object? json) => throw const _ResponseShapeException();

BackendFileDownload _mapDownload(
  Response<List<int>> response, {
  required String fallbackName,
}) {
  final bytes = response.data;
  if (bytes == null || bytes.isEmpty) {
    throw const _ResponseShapeException();
  }
  final disposition = response.headers.value('content-disposition');
  return BackendFileDownload(
    bytes: Uint8List.fromList(bytes),
    fileName:
        parseContentDispositionFileName(disposition) ??
        sanitizeDownloadFileName(fallbackName),
    contentType:
        response.headers.value(Headers.contentTypeHeader) ??
        'application/octet-stream',
  );
}

/// Reads the server's file name from `Content-Disposition`, preferring the
/// RFC 5987 `filename*` form so non-ASCII course files keep their names.
///
/// The result is always sanitized: the name comes from an upstream system and
/// is about to become a path, so it must not carry separators or traversal.
String? parseContentDispositionFileName(String? headerValue) {
  if (headerValue == null || headerValue.isEmpty) {
    return null;
  }

  final extended = RegExp(
    r"filename\*\s*=\s*([^']*)'[^']*'([^;]+)",
    caseSensitive: false,
  ).firstMatch(headerValue);
  if (extended != null) {
    final charset = extended.group(1)?.toLowerCase();
    final rawValue = extended.group(2)!.trim();
    try {
      final decoded = Uri.decodeComponent(rawValue);
      if (charset == null || charset.isEmpty || charset == 'utf-8') {
        final sanitized = sanitizeDownloadFileName(decoded);
        if (sanitized.isNotEmpty) {
          return sanitized;
        }
      }
    } on Object {
      // Bad percent-encoding throws ArgumentError, not FormatException. Either
      // way the plain form is still worth trying: a broken extended name must
      // not fail a download the server was ready to serve.
    }
  }

  final plain = RegExp(
    r'filename\s*=\s*"([^"]*)"|filename\s*=\s*([^;]+)',
    caseSensitive: false,
  ).firstMatch(headerValue);
  if (plain != null) {
    final value = (plain.group(1) ?? plain.group(2) ?? '').trim();
    final sanitized = sanitizeDownloadFileName(value);
    if (sanitized.isNotEmpty) {
      return sanitized;
    }
  }

  return null;
}

/// Reduces a server-supplied name to a single safe path segment.
String sanitizeDownloadFileName(String value) {
  final withoutSeparators = value
      .replaceAll(RegExp(r'[\\/]+'), '_')
      .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '')
      .trim();
  final collapsed = withoutSeparators.replaceAll(RegExp(r'^\.+'), '');
  if (collapsed.isEmpty) {
    return '';
  }
  return collapsed.length > 180 ? collapsed.substring(0, 180) : collapsed;
}
