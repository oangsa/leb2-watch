part of 'backend_api_client.dart';

const _maximumInt32 = 2147483647;
const _authorizationHeader = 'Authorization';
const _userIdHeader = 'X-LEB2-USER-ID';

final class DioBackendApiClient
    implements BackendApiClient, BackendSessionClient {
  factory DioBackendApiClient({
    required AppConfiguration configuration,
    required CredentialStore credentialStore,
    HttpClientAdapter? httpClientAdapter,
    BackendTransportEventSink? eventSink,
    DateTime Function()? utcNow,
  }) {
    final baseUrl = _validatedBaseUrl(configuration);
    final dio = _createDio(baseUrl);
    final sessionDio = _createDio(baseUrl);
    if (httpClientAdapter != null) {
      dio.httpClientAdapter = httpClientAdapter;
      sessionDio.httpClientAdapter = httpClientAdapter;
    }
    dio.interceptors.add(_CredentialInterceptor(credentialStore));

    return DioBackendApiClient._(
      dio: dio,
      sessionDio: sessionDio,
      eventSink: configuration.environment == AppEnvironment.development
          ? eventSink ?? _developmentEventSink
          : null,
      utcNow: utcNow ?? DateTime.now,
    );
  }

  DioBackendApiClient._({
    required this._dio,
    required this._sessionDio,
    required this._eventSink,
    required this._utcNow,
  });

  final Dio _dio;
  final Dio _sessionDio;
  final BackendTransportEventSink? _eventSink;
  final DateTime Function() _utcNow;

  @override
  Future<List<Semester>> getSemesters({
    BackendRequestCancellation? cancellation,
  }) {
    return _execute(
      route: BackendTransportRoute.semesters,
      path: '/Semester',
      cancellation: cancellation,
      mapSuccess: _mapSemesters,
    );
  }

  @override
  Future<List<Semester>> verifySessionCookie({
    required String candidateCookie,
    BackendRequestCancellation? cancellation,
  }) {
    _requireNonblankRequest(candidateCookie, 'candidateCookie');
    return _execute(
      dio: _sessionDio,
      route: BackendTransportRoute.sessionVerification,
      path: '/Semester',
      headers: {_authorizationHeader: 'Bearer $candidateCookie'},
      cancellation: cancellation,
      mapSuccess: _mapSemesters,
    );
  }

  @override
  Future<BackendUserIdentity> authenticateUser({
    required String username,
    required String password,
    BackendRequestCancellation? cancellation,
  }) {
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
      path: '/User/login',
      data: request.toJson(),
      cancellation: cancellation,
      mapSuccess: _mapUserIdentity,
    );
  }

  @override
  Future<BackendSessionCookie> acquireSessionCookie({
    required String username,
    required String password,
    BackendRequestCancellation? cancellation,
  }) {
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
      path: '/User/cookie',
      data: request.toJson(),
      cancellation: cancellation,
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
      path: '/Class/$semesterId',
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
      path: '/Activity/$semesterId/snapshot',
      headers: {_userIdHeader: userId.toString()},
      cancellation: cancellation,
      mapSuccess: (json) => _mapSnapshot(json, semesterId),
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
  }) async {
    final stopwatch = Stopwatch()..start();
    int? statusCode;
    var outcome = BackendTransportOutcome.unknownFailure;

    try {
      if (cancellation?.isCancelled ?? false) {
        throw const BackendTransportException(
          kind: BackendTransportFailureKind.cancelled,
        );
      }

      final cancelToken = CancelToken();
      if (cancellation != null) {
        unawaited(
          cancellation._whenCancelled.then((_) {
            if (!cancelToken.isCancelled) {
              cancelToken.cancel();
            }
          }),
        );
      }

      final client = dio ?? _dio;
      final options = Options(
        method: method.name.toUpperCase(),
        headers: {
          if (method == BackendTransportMethod.post)
            Headers.contentTypeHeader: Headers.jsonContentType,
          ...?headers,
        },
      );
      final response = await client.request<List<int>>(
        path,
        data: data,
        options: options,
        cancelToken: cancelToken,
      );
      statusCode = response.statusCode;
      if (statusCode == null) {
        throw const BackendTransportException(
          kind: BackendTransportFailureKind.invalidResponse,
          invalidResponseReason: BackendInvalidResponseReason.wrongShape,
        );
      }

      final decoded = _decodeResponse(response);
      if (statusCode != 200) {
        throw _mapHttpError(response, decoded, statusCode);
      }

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

      return BackendTransportException(
        kind: BackendTransportFailureKind.httpResponse,
        httpError: BackendHttpErrorEvidence(
          statusCode: statusCode,
          responseCode: responseCode,
          envelopeKind: envelopeKind,
          retryAfter: _parseRetryAfterHeader(response.headers),
          hasBearerChallenge: _hasBearerChallenge(response.headers),
        ),
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

final class _CredentialInterceptor extends Interceptor {
  _CredentialInterceptor(this._credentialStore);

  final CredentialStore _credentialStore;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
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

    if (cookie == null) {
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

List<Semester> _mapSemesters(Object? json) {
  final values = _asJsonList(json);
  final seen = <int>{};
  final semesters = <Semester>[];

  for (final value in values) {
    final dto = SemesterDto.fromJson(value);
    _requireResponsePositiveInt32(dto.id);
    if (!seen.add(dto.id)) {
      throw const _ResponseInvariantException();
    }
    semesters.add(Semester(id: dto.id));
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
  _requireIsoDate(dto.startDate);
  _requireIsoDate(dto.dueDate);
  _requireIsoDate(dto.createdAt);
  _requireIsoDate(dto.lastDueDateNotificationDate);
  _requireIsoDate(dto.lastStatusChangeNotificationDate);

  final submittedAtDto = dto.activitySubmissionSubmittedAt;
  final ActivitySubmissionTimestamp? submittedAt;
  if (submittedAtDto == null) {
    submittedAt = null;
  } else {
    _requireIsoDate(submittedAtDto.date);
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

void _requireResponsePositiveInt32(int value) {
  if (value <= 0 || value > _maximumInt32) {
    throw const _ResponseInvariantException();
  }
}

void _requireNonblank(String value) {
  if (value.trim().isEmpty) {
    throw const _ResponseInvariantException();
  }
}

final _isoDatePattern = RegExp(
  r'^[+-]?\d{4,6}-\d{2}-\d{2}T\d{2}:\d{2}'
  r'(?::\d{2}(?:\.\d{1,9})?)?(?:Z|[+-]\d{2}:\d{2})?$',
);

void _requireIsoDate(String? value) {
  if (value == null) {
    return;
  }
  if (!_isoDatePattern.hasMatch(value) || DateTime.tryParse(value) == null) {
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
