import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leb2_watch/src/core/config/app_configuration.dart';
import 'package:leb2_watch/src/core/network/backend_api_client.dart';
import 'package:leb2_watch/src/core/network/backend_transport_event.dart';
import 'package:leb2_watch/src/core/network/backend_transport_failure.dart';

import 'network_test_support.dart';

const _baseUrl = 'https://example.invalid';

void main() {
  group('configuration', () {
    test(
      'accepts root development HTTP and normalizes the trailing slash',
      () async {
        final adapter = CallbackHttpClientAdapter((options, _, _) {
          expect(options.baseUrl, 'http://localhost:5015/');
          return jsonResponse(const <int>[]);
        });
        final client = _client(
          adapter,
          backendBaseUrl: 'http://localhost:5015',
        );

        await client.getSemesters();
        expect(adapter.requests, hasLength(1));
      },
    );

    test('requires HTTPS in production', () {
      expect(
        () => _client(
          CallbackHttpClientAdapter((_, _, _) => jsonResponse(const <int>[])),
          environment: 'production',
          backendBaseUrl: 'http://example.invalid',
        ),
        throwsA(
          isA<BackendApiConfigurationException>().having(
            (error) => error.reason,
            'reason',
            BackendApiConfigurationFailureReason.insecureProductionUrl,
          ),
        ),
      );
    });

    test('rejects invalid base URL forms with fixed redacted failures', () {
      final cases = <(String, BackendApiConfigurationFailureReason)>[
        ('', BackendApiConfigurationFailureReason.emptyBaseUrl),
        ('relative/path', BackendApiConfigurationFailureReason.invalidBaseUrl),
        (
          'ftp://example.invalid',
          BackendApiConfigurationFailureReason.unsupportedScheme,
        ),
        ('http:///path', BackendApiConfigurationFailureReason.missingHost),
        (
          'https://user:private@example.invalid',
          BackendApiConfigurationFailureReason.userInfoNotAllowed,
        ),
        (
          'https://example.invalid?private=value',
          BackendApiConfigurationFailureReason.queryNotAllowed,
        ),
        (
          'https://example.invalid#private',
          BackendApiConfigurationFailureReason.fragmentNotAllowed,
        ),
        (
          'https://example.invalid/api',
          BackendApiConfigurationFailureReason.pathNotAllowed,
        ),
      ];

      for (final (value, reason) in cases) {
        BackendApiConfigurationException? failure;
        try {
          _client(
            CallbackHttpClientAdapter((_, _, _) => jsonResponse(const [])),
            backendBaseUrl: value,
          );
        } on BackendApiConfigurationException catch (error) {
          failure = error;
        }
        expect(failure?.reason, reason);
        expect(failure.toString(), isNot(contains('private')));
        if (value.isNotEmpty) {
          expect(failure.toString(), isNot(contains(value)));
        }
      }
    });
  });

  group('request construction and authentication', () {
    test(
      'uses exact routes, headers, options, and one request per method',
      () async {
        final adapter = CallbackHttpClientAdapter((options, _, _) {
          return switch (options.path) {
            '/Semester' => _fixtureResponse('semesters_success.json'),
            '/Class/101' => _fixtureResponse('classes_success.json'),
            '/Activity/101/snapshot' => _fixtureResponse(
              'snapshot_success.json',
            ),
            _ => throw StateError('Unexpected test route.'),
          };
        });
        final credentials = MemoryCredentialStore();
        final client = _client(adapter, credentials: credentials);

        await client.getSemesters();
        await client.getCourses(semesterId: 101);
        await client.getSemesterSnapshot(semesterId: 101, userId: 2001);

        expect(credentials.sessionReadCount, 3);
        expect(adapter.requests.map((request) => request.path), [
          '/Semester',
          '/Class/101',
          '/Activity/101/snapshot',
        ]);
        for (final request in adapter.requests) {
          expect(request.method, 'GET');
          expect(request.connectTimeout, const Duration(seconds: 10));
          expect(request.sendTimeout, const Duration(seconds: 10));
          expect(request.receiveTimeout, const Duration(seconds: 30));
          expect(request.responseType, ResponseType.bytes);
          expect(request.followRedirects, isFalse);
          expect(request.maxRedirects, 0);
          expect(request.validateStatus(500), isTrue);
          expect(request.headers[Headers.acceptHeader], 'application/json');
          expect(request.headers['Authorization'], 'Bearer <SESSION_COOKIE>');
        }
        expect(adapter.requests[0].headers, isNot(contains('X-LEB2-USER-ID')));
        expect(adapter.requests[1].headers, isNot(contains('X-LEB2-USER-ID')));
        expect(adapter.requests[2].headers['X-LEB2-USER-ID'], '2001');
      },
    );

    test('preserves an opaque cookie exactly', () async {
      const cookie = '  opaque=value; another=value  ';
      final adapter = CallbackHttpClientAdapter((options, _, _) {
        expect(options.headers['Authorization'], 'Bearer $cookie');
        return jsonResponse(const <int>[]);
      });

      await _client(
        adapter,
        credentials: MemoryCredentialStore(sessionCookie: cookie),
      ).getSemesters();
    });

    test('missing credentials reject before the adapter', () async {
      final adapter = CallbackHttpClientAdapter(
        (_, _, _) => throw StateError('Adapter must not run.'),
      );

      await expectLater(
        _client(
          adapter,
          credentials: MemoryCredentialStore(sessionCookie: null),
        ).getSemesters(),
        throwsA(
          _transportFailure(BackendTransportFailureKind.missingCredential),
        ),
      );
      expect(adapter.requests, isEmpty);
    });

    test('credential read failures reject safely before the adapter', () async {
      final adapter = CallbackHttpClientAdapter(
        (_, _, _) => throw StateError('Adapter must not run.'),
      );

      await expectLater(
        _client(
          adapter,
          credentials: MemoryCredentialStore(
            readFailure: StateError('contains <SESSION_COOKIE>'),
          ),
        ).getSemesters(),
        throwsA(
          _transportFailure(
            BackendTransportFailureKind.credentialAccessFailed,
          ).having(
            (error) => error.toString(),
            'redacted output',
            isNot(contains('<SESSION_COOKIE>')),
          ),
        ),
      );
      expect(adapter.requests, isEmpty);
    });

    test('rejects non-positive or out-of-range request IDs', () {
      final adapter = CallbackHttpClientAdapter(
        (_, _, _) => jsonResponse(const <int>[]),
      );
      final client = _client(adapter);

      expect(
        () => client.getCourses(semesterId: 0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => client.getSemesterSnapshot(semesterId: 101, userId: -1),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => client.getSemesterSnapshot(semesterId: 2147483648, userId: 1),
        throwsA(isA<ArgumentError>()),
      );
      expect(adapter.requests, isEmpty);
    });
  });

  group('successful response mapping', () {
    test('maps semesters and courses into separate domain models', () async {
      final adapter = CallbackHttpClientAdapter((options, _, _) {
        return options.path == '/Semester'
            ? _fixtureResponse('semesters_success.json')
            : _fixtureResponse('classes_success.json');
      });
      final client = _client(adapter);

      final semesters = await client.getSemesters();
      final courses = await client.getCourses(semesterId: 101);

      expect(semesters.map((value) => value.id), [101, 102]);
      expect(courses.map((value) => (value.semesterId, value.id, value.name)), [
        (101, 3001, 'Example Course'),
        (101, 3002, 'Another Course'),
      ]);
      expect(semesters.toString(), isNot(contains('Example Course')));
      expect(adapter.requests, hasLength(2));
    });

    test(
      'maps all snapshot fields and preserves source date strings',
      () async {
        final source = _fixtureObject('snapshot_success.json');
        final activity =
            ((source['classes'] as List<Object?>).first
                    as Map<String, dynamic>)['activities']
                as List<Object?>;
        final activityObject = activity.first as Map<String, dynamic>;
        activityObject['activitySubmissionSubmittedAt'] = {
          'date': '2026-07-30T10:11:12',
          'timezoneType': 3,
          'timezone': 'opaque-zone',
        };
        activityObject['fileActivities'] = [
          {
            'z': 1,
            'a': {'second': true, 'first': <Object?>[]},
          },
        ];
        activityObject['questions'] = [7, 8];
        activityObject['submissions'] = [
          {'z': null, 'a': 'value'},
        ];
        final adapter = CallbackHttpClientAdapter(
          (_, _, _) => jsonResponse(source),
        );

        final snapshot = await _client(
          adapter,
        ).getSemesterSnapshot(semesterId: 101, userId: 2001);
        final mapped = snapshot.courses.first.activities.single;

        expect(snapshot.semesterId, 101);
        expect(snapshot.courses, hasLength(2));
        expect(snapshot.courses.last.activities, isEmpty);
        expect(mapped.semesterId, 101);
        expect(mapped.id, 1001);
        expect(mapped.userId, 2001);
        expect(mapped.classId, 3001);
        expect(mapped.advStarred, 0);
        expect(mapped.groupType, 'individual');
        expect(mapped.type, 'ASM');
        expect(mapped.peerAssessment, 0);
        expect(mapped.isAllowRepeat, 0);
        expect(mapped.title, 'Example assignment');
        expect(mapped.description, '<p>Example description</p>');
        expect(mapped.startDate, '2026-07-01T09:00:00');
        expect(mapped.dueDate, '2026-07-31T23:59:00');
        expect(mapped.editGroupMode, '');
        expect(mapped.createdAt, '2026-06-30T12:00:00');
        expect(mapped.user, 2001);
        expect(mapped.activitySubmissionId, isNull);
        expect(mapped.classUserId, 4001);
        expect(mapped.activityGroupId, isNull);
        expect(mapped.activityGroupName, isNull);
        expect(
          mapped.activitySubmissionSubmittedAt?.date,
          '2026-07-30T10:11:12',
        );
        expect(mapped.activitySubmissionSubmittedAt?.timezoneType, 3);
        expect(mapped.activitySubmissionSubmittedAt?.timezone, 'opaque-zone');
        expect(mapped.dueDateExceed, isFalse);
        expect(mapped.quizSubmissionIsSubmitted, isFalse);
        expect(mapped.countGroupMember, 1);
        expect(mapped.activitySubmissionIsLate, isFalse);
        expect(
          mapped.fileActivitiesJson,
          '[{"a":{"first":[],"second":true},"z":1}]',
        );
        expect(mapped.questions, [7, 8]);
        expect(mapped.submissionsJson, '[{"a":"value","z":null}]');
        expect(mapped.lastDueDateNotificationDate, isNull);
        expect(mapped.lastStatusChangeNotificationDate, isNull);
        expect(mapped.previousSubmissionStatus, isNull);
      },
    );

    test('accepts the documented space-separated submission date', () async {
      final source = _fixtureObject('snapshot_success.json');
      _firstActivity(source)['activitySubmissionSubmittedAt'] = {
        'date': '2026-07-20 14:30:00',
        'timezoneType': 3,
        'timezone': 'Asia/Bangkok',
      };
      final adapter = CallbackHttpClientAdapter(
        (_, _, _) => jsonResponse(source),
      );

      final snapshot = await _client(
        adapter,
      ).getSemesterSnapshot(semesterId: 101, userId: 2001);
      final submittedAt = snapshot
          .courses
          .first
          .activities
          .single
          .activitySubmissionSubmittedAt;

      expect(submittedAt?.date, '2026-07-20 14:30:00');
      expect(submittedAt?.timezoneType, 3);
      expect(submittedAt?.timezone, 'Asia/Bangkok');
    });

    test('maps exact empty response semantics', () async {
      final adapter = CallbackHttpClientAdapter((options, _, _) {
        if (options.path == '/Semester' || options.path.startsWith('/Class/')) {
          return jsonResponse(const <Object?>[]);
        }
        return _fixtureResponse('snapshot_empty.json');
      });
      final client = _client(adapter);

      expect(await client.getSemesters(), isEmpty);
      expect(await client.getCourses(semesterId: 101), isEmpty);
      final snapshot = await client.getSemesterSnapshot(
        semesterId: 101,
        userId: 2001,
      );
      expect(snapshot.semesterId, 101);
      expect(snapshot.courses, isEmpty);
    });

    test(
      'ignores unknown response keys after validating contracted fields',
      () async {
        final source = _fixtureObject('snapshot_success.json');
        source['futureSnapshotField'] = {'private': 'ignored'};
        _firstCourse(source)['futureCourseField'] = 42;
        _firstActivity(source)['futureActivityField'] = <Object?>[];
        final adapter = CallbackHttpClientAdapter(
          (_, _, _) => jsonResponse(source),
        );

        final snapshot = await _client(
          adapter,
        ).getSemesterSnapshot(semesterId: 101, userId: 2001);

        expect(snapshot.courses.first.activities.single.id, 1001);
        expect(adapter.requests, hasLength(1));
      },
    );
  });

  group('response validation', () {
    test('rejects semester and course identity or label violations', () async {
      final cases = <Object>[
        [101, 101],
        [0],
        [
          {'id': 3001, 'name': 'Course'},
          {'id': 3001, 'name': 'Duplicate'},
        ],
        [
          {'id': 3001, 'name': '   '},
        ],
        [
          {'id': 1.5, 'name': 'Wrong integer type'},
        ],
      ];

      for (var index = 0; index < cases.length; index += 1) {
        final adapter = CallbackHttpClientAdapter(
          (_, _, _) => jsonResponse(cases[index]),
        );
        final client = _client(adapter);
        final operation = index < 2
            ? client.getSemesters()
            : client.getCourses(semesterId: 101);

        await expectLater(
          operation,
          throwsA(
            isA<BackendTransportException>().having(
              (error) => error.kind,
              'kind',
              BackendTransportFailureKind.invalidResponse,
            ),
          ),
        );
        expect(adapter.requests, hasLength(1));
      }
    });

    test(
      'rejects snapshot identity, containment, label, and date violations',
      () async {
        final mutations = <void Function(Map<String, dynamic>)>[
          (json) => json['semesterId'] = 102,
          (json) => _firstCourse(json)['id'] = 0,
          (json) => (json['classes'] as List<Object?>).add(
            Map<String, dynamic>.from(_firstCourse(json)),
          ),
          (json) => _firstCourse(json)['name'] = ' ',
          (json) => _firstActivity(json)['id'] = 0,
          (json) => _firstActivity(json)['classId'] = 9999,
          (json) => _firstActivity(json)['title'] = '',
          (json) => _firstActivity(json)['createdAt'] = 'not-a-date',
          (json) => _firstActivity(json)['dueDate'] = '2026/07/31',
          (json) => _firstActivity(json)['dueDate'] = '2026-07-31 23:59:00',
          (json) => _firstActivity(json)['id'] = 1.5,
          (json) => _firstActivity(json).remove('activityGroupName'),
          (json) => _firstActivity(json)['fileActivities'] = [1],
          (json) => _firstActivity(json)['questions'] = [1.5],
          (json) => _firstActivity(json)['submissions'] = ['wrong'],
          (json) => _firstActivity(json)['previousSubmissionStatus'] = 0,
          (json) => _firstActivity(json)['lastDueDateNotificationDate'] = 'bad',
          (json) => _firstActivity(json)['activitySubmissionSubmittedAt'] = {
            'date': 'bad',
            'timezoneType': 3,
            'timezone': 'opaque',
          },
        ];

        for (final mutate in mutations) {
          final source = _fixtureObject('snapshot_success.json');
          mutate(source);
          final adapter = CallbackHttpClientAdapter(
            (_, _, _) => jsonResponse(source),
          );

          await expectLater(
            _client(adapter).getSemesterSnapshot(semesterId: 101, userId: 2001),
            throwsA(
              _transportFailure(BackendTransportFailureKind.invalidResponse),
            ),
          );
          expect(adapter.requests, hasLength(1));
        }
      },
    );

    test('rejects duplicate activity IDs across snapshot courses', () async {
      final source = _fixtureObject('snapshot_success.json');
      final classes = source['classes'] as List<Object?>;
      final duplicate = Map<String, dynamic>.from(_firstActivity(source))
        ..['classId'] = 3002;
      (classes[1] as Map<String, dynamic>)['activities'] = [duplicate];
      final adapter = CallbackHttpClientAdapter(
        (_, _, _) => jsonResponse(source),
      );

      await expectLater(
        _client(adapter).getSemesterSnapshot(semesterId: 101, userId: 2001),
        throwsA(_transportFailure(BackendTransportFailureKind.invalidResponse)),
      );
      expect(adapter.requests, hasLength(1));
    });

    test('accepts JSON parameters and application structured JSON', () async {
      for (final contentType in [
        'application/json; charset=utf-8',
        'Application/vnd.leb2+JSON; charset="utf-8"',
      ]) {
        final adapter = CallbackHttpClientAdapter(
          (_, _, _) => jsonResponse(const <int>[101], contentType: contentType),
        );
        expect((await _client(adapter).getSemesters()).single.id, 101);
      }
    });

    test(
      'rejects a structured JSON suffix with an empty subtype prefix',
      () async {
        final adapter = CallbackHttpClientAdapter(
          (_, _, _) =>
              jsonResponse(const <int>[101], contentType: 'application/+json'),
        );

        final failure = await _captureTransportFailure(
          _client(adapter).getSemesters(),
        );

        expect(failure.kind, BackendTransportFailureKind.invalidResponse);
        expect(
          failure.invalidResponseReason,
          BackendInvalidResponseReason.unsupportedContentType,
        );
        expect(adapter.requests, hasLength(1));
      },
    );

    test(
      'rejects missing, multiple, malformed, and unsupported content types',
      () async {
        final headers = <Map<String, List<String>>>[
          const {},
          const {
            Headers.contentTypeHeader: ['application/json', 'application/json'],
          },
          const {
            Headers.contentTypeHeader: ['application/json; charset'],
          },
          const {
            Headers.contentTypeHeader: ['text/html'],
          },
          const {
            Headers.contentTypeHeader: ['text/plain'],
          },
        ];

        for (final responseHeaders in headers) {
          final adapter = CallbackHttpClientAdapter(
            (_, _, _) =>
                byteResponse(utf8.encode('[101]'), headers: responseHeaders),
          );
          await expectLater(
            _client(adapter).getSemesters(),
            throwsA(
              _transportFailure(BackendTransportFailureKind.invalidResponse),
            ),
          );
          expect(adapter.requests, hasLength(1));
        }
      },
    );

    test('rejects invalid response bytes and top-level shapes', () async {
      final responses = <ResponseBody>[
        byteResponse([0xC3, 0x28]),
        byteResponse(utf8.encode('{not-json')),
        byteResponse(const []),
        byteResponse(utf8.encode('null')),
        byteResponse(utf8.encode('{"id":101}')),
        byteResponse(
          utf8.encode('<html>logged out</html>'),
          headers: const {
            Headers.contentTypeHeader: ['text/html'],
          },
        ),
      ];

      for (final response in responses) {
        final adapter = CallbackHttpClientAdapter((_, _, _) => response);
        await expectLater(
          _client(adapter).getSemesters(),
          throwsA(
            _transportFailure(BackendTransportFailureKind.invalidResponse),
          ),
        );
        expect(adapter.requests, hasLength(1));
      }
    });

    test('does not retry a malformed response', () async {
      final adapter = CallbackHttpClientAdapter(
        (_, _, _) => byteResponse(utf8.encode('{broken')),
      );

      await expectLater(
        _client(adapter).getSemesters(),
        throwsA(_transportFailure(BackendTransportFailureKind.invalidResponse)),
      );
      expect(adapter.requests, hasLength(1));
    });
  });

  group('cancellation and transport failures', () {
    test('cancellation before dispatch never invokes the adapter', () async {
      final cancellation = BackendRequestCancellation()
        ..cancel()
        ..cancel();
      final adapter = CallbackHttpClientAdapter(
        (_, _, _) => throw StateError('Adapter must not run.'),
      );

      await expectLater(
        _client(adapter).getSemesters(cancellation: cancellation),
        throwsA(_transportFailure(BackendTransportFailureKind.cancelled)),
      );
      expect(adapter.requests, isEmpty);
    });

    test('in-flight cancellation maps deterministically', () async {
      final started = Completer<void>();
      final adapter = CallbackHttpClientAdapter((
        options,
        _,
        cancelFuture,
      ) async {
        started.complete();
        await cancelFuture;
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
          error: StateError('sensitive adapter cancellation'),
        );
      });
      final cancellation = BackendRequestCancellation();
      final operation = _client(
        adapter,
      ).getSemesters(cancellation: cancellation);
      await started.future;
      cancellation.cancel();

      await expectLater(
        operation,
        throwsA(
          _transportFailure(BackendTransportFailureKind.cancelled).having(
            (error) => error.toString(),
            'redacted output',
            isNot(contains('sensitive adapter cancellation')),
          ),
        ),
      );
      expect(adapter.requests, hasLength(1));
    });

    test(
      'terminal requests detach from a reusable cancellation handle',
      () async {
        final didCancel = <bool>[];
        var requestIndex = 0;
        final adapter = CallbackHttpClientAdapter((options, _, cancelFuture) {
          final index = requestIndex++;
          didCancel.add(false);
          unawaited(
            cancelFuture!.then((_) {
              didCancel[index] = true;
            }),
          );

          return switch (index) {
            0 => jsonResponse(const <int>[101]),
            1 => throw DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
            ),
            2 => throw DioException(
              requestOptions: options,
              type: DioExceptionType.cancel,
            ),
            _ => throw StateError('Unexpected request.'),
          };
        });
        final client = _client(adapter);
        final cancellation = BackendRequestCancellation();

        expect(
          (await client.getSemesters(cancellation: cancellation)).single.id,
          101,
        );
        await expectLater(
          client.getSemesters(cancellation: cancellation),
          throwsA(
            _transportFailure(BackendTransportFailureKind.connectionError),
          ),
        );
        await expectLater(
          client.getSemesters(cancellation: cancellation),
          throwsA(_transportFailure(BackendTransportFailureKind.cancelled)),
        );

        cancellation.cancel();
        await Future<void>.delayed(Duration.zero);

        expect(didCancel, [false, false, false]);
      },
    );

    test(
      'late cancellation reaches only the request that remains active',
      () async {
        final secondStarted = Completer<void>();
        final didCancel = <bool>[false, false];
        var requestIndex = 0;
        final adapter = CallbackHttpClientAdapter((
          options,
          _,
          cancelFuture,
        ) async {
          final index = requestIndex++;
          unawaited(
            cancelFuture!.then((_) {
              didCancel[index] = true;
            }),
          );
          if (index == 0) {
            return jsonResponse(const <int>[101]);
          }
          secondStarted.complete();
          await cancelFuture;
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
          );
        });
        final client = _client(adapter);
        final cancellation = BackendRequestCancellation();

        await client.getSemesters(cancellation: cancellation);
        final activeRequest = client.getSemesters(cancellation: cancellation);
        final activeExpectation = expectLater(
          activeRequest,
          throwsA(_transportFailure(BackendTransportFailureKind.cancelled)),
        );
        await secondStarted.future;

        cancellation
          ..cancel()
          ..cancel();
        await activeExpectation;

        expect(didCancel, [false, true]);
      },
    );

    test('one handle cancels every concurrently active request once', () async {
      final bothStarted = Completer<void>();
      final cancellationCount = <int>[0, 0];
      var requestIndex = 0;
      final adapter = CallbackHttpClientAdapter((
        options,
        _,
        cancelFuture,
      ) async {
        final index = requestIndex++;
        unawaited(
          cancelFuture!.then((_) {
            cancellationCount[index] += 1;
          }),
        );
        if (requestIndex == 2) {
          bothStarted.complete();
        }
        await cancelFuture;
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
        );
      });
      final client = _client(adapter);
      final cancellation = BackendRequestCancellation();
      final firstExpectation = expectLater(
        client.getSemesters(cancellation: cancellation),
        throwsA(_transportFailure(BackendTransportFailureKind.cancelled)),
      );
      final secondExpectation = expectLater(
        client.getSemesters(cancellation: cancellation),
        throwsA(_transportFailure(BackendTransportFailureKind.cancelled)),
      );
      await bothStarted.future;

      cancellation
        ..cancel()
        ..cancel();
      await Future.wait([firstExpectation, secondExpectation]);

      expect(cancellationCount, [1, 1]);
    });

    test('terminal event observes a detached request listener', () async {
      var requestCancelled = false;
      final cancellation = BackendRequestCancellation();
      final adapter = CallbackHttpClientAdapter((_, _, cancelFuture) {
        unawaited(
          cancelFuture!.then((_) {
            requestCancelled = true;
          }),
        );
        return jsonResponse(const <int>[101]);
      });
      final client = _client(adapter, eventSink: (_) => cancellation.cancel());

      await client.getSemesters(cancellation: cancellation);
      await Future<void>.delayed(Duration.zero);

      expect(requestCancelled, isFalse);
    });

    test('maps every Dio timeout and transport category distinctly', () async {
      final cases = <(DioExceptionType, BackendTransportFailureKind)>[
        (
          DioExceptionType.connectionTimeout,
          BackendTransportFailureKind.connectionTimeout,
        ),
        (DioExceptionType.sendTimeout, BackendTransportFailureKind.sendTimeout),
        (
          DioExceptionType.receiveTimeout,
          BackendTransportFailureKind.receiveTimeout,
        ),
        (
          DioExceptionType.transformTimeout,
          BackendTransportFailureKind.transformTimeout,
        ),
        (
          DioExceptionType.connectionError,
          BackendTransportFailureKind.connectionError,
        ),
        (
          DioExceptionType.badCertificate,
          BackendTransportFailureKind.badCertificate,
        ),
        (DioExceptionType.unknown, BackendTransportFailureKind.unknownFailure),
      ];

      for (final (dioType, expectedKind) in cases) {
        final adapter = CallbackHttpClientAdapter((options, _, _) {
          throw DioException(
            requestOptions: options,
            type: dioType,
            error: StateError('sensitive transport detail'),
          );
        });

        await expectLater(
          _client(adapter).getSemesters(),
          throwsA(
            _transportFailure(expectedKind).having(
              (error) => error.toString(),
              'redacted output',
              isNot(contains('sensitive transport detail')),
            ),
          ),
        );
        expect(adapter.requests, hasLength(1));
      }
    });
  });

  group('backend error evidence', () {
    test(
      'preserves SESSION_EXPIRED status, code, retry, and bearer evidence',
      () async {
        final adapter = CallbackHttpClientAdapter(
          (_, _, _) => _fixtureResponse(
            'session_expired.json',
            statusCode: 401,
            headers: const {
              'retry-after': ['120'],
              'www-authenticate': ['Bearer'],
            },
          ),
        );

        final failure = await _captureTransportFailure(
          _client(adapter).getSemesters(),
        );
        expect(failure.kind, BackendTransportFailureKind.httpResponse);
        expect(failure.httpError?.statusCode, 401);
        expect(failure.httpError?.responseCode, 'SESSION_EXPIRED');
        expect(failure.httpError?.retryAfter, const Duration(minutes: 2));
        expect(failure.httpError?.hasBearerChallenge, isTrue);
        expect(failure.toString(), isNot(contains('expired or is invalid')));
        expect(adapter.requests, hasLength(1));
      },
    );

    test(
      'keeps AUTHENTICATION_REQUIRED distinct from SESSION_EXPIRED',
      () async {
        final adapter = CallbackHttpClientAdapter(
          (_, _, _) => _fixtureResponse(
            'authentication_required.json',
            statusCode: 401,
            headers: const {
              'www-authenticate': ['Bearer realm="LEB2"'],
            },
          ),
        );

        final failure = await _captureTransportFailure(
          _client(adapter).getSemesters(),
        );
        expect(failure.httpError?.responseCode, 'AUTHENTICATION_REQUIRED');
        expect(
          failure.httpError?.responseCode,
          isNot(equals('SESSION_EXPIRED')),
        );
        expect(failure.httpError?.hasBearerChallenge, isTrue);
      },
    );

    test('parses the verified validation error envelope', () async {
      final adapter = CallbackHttpClientAdapter(
        (_, _, _) => _fixtureResponse('validation_error.json', statusCode: 400),
      );

      final failure = await _captureTransportFailure(
        _client(adapter).getSemesters(),
      );
      expect(failure.kind, BackendTransportFailureKind.httpResponse);
      expect(
        failure.httpError?.envelopeKind,
        BackendErrorEnvelopeKind.validation,
      );
      expect(failure.httpError?.responseCode, 'INVALID_REQUEST');
    });

    test(
      'rejects non-200 responses without a verified error envelope',
      () async {
        final cases = <ResponseBody>[
          jsonResponse(const <String, Object?>{}, statusCode: 500),
          jsonResponse({
            'message': 'missing required fields',
            'responseCode': 'UNEXPECTED_ERROR',
          }, statusCode: 500),
          byteResponse(
            const [],
            statusCode: 204,
            headers: const {
              Headers.contentTypeHeader: ['application/json'],
            },
          ),
        ];

        for (final response in cases) {
          final adapter = CallbackHttpClientAdapter((_, _, _) => response);
          final failure = await _captureTransportFailure(
            _client(adapter).getSemesters(),
          );
          expect(failure.kind, BackendTransportFailureKind.invalidResponse);
          expect(adapter.requests, hasLength(1));
        }
      },
    );

    test('malformed or multiple Retry-After values are discarded', () async {
      for (final values in [
        ['invalid'],
        ['120', '240'],
      ]) {
        final adapter = CallbackHttpClientAdapter(
          (_, _, _) => _fixtureResponse(
            'client_throttle_active.json',
            statusCode: 429,
            headers: {'retry-after': values},
          ),
        );
        final failure = await _captureTransportFailure(
          _client(adapter).getSemesters(),
        );
        expect(failure.httpError?.retryAfter, isNull);
      }
    });
  });

  group('safe transport events', () {
    test('development emits bounded success and failure metadata', () async {
      final events = <BackendTransportEvent>[];
      final adapter = CallbackHttpClientAdapter(
        (_, _, _) => _fixtureResponse('semesters_success.json'),
      );
      final client = _client(adapter, eventSink: events.add);

      await client.getSemesters();

      expect(events, hasLength(1));
      expect(events.single.method, BackendTransportMethod.get);
      expect(events.single.route, BackendTransportRoute.semesters);
      expect(events.single.statusCode, 200);
      expect(events.single.outcome, BackendTransportOutcome.success);
      final output = events.single.toString();
      for (final sensitiveValue in [
        '<SESSION_COOKIE>',
        'Authorization',
        '2001',
        'Example assignment',
        'Example description',
        '<TRACE_ID>',
        '/Semester',
      ]) {
        expect(output, isNot(contains(sensitiveValue)));
      }
    });

    test(
      'development failure events never receive transport evidence',
      () async {
        final events = <BackendTransportEvent>[];
        final adapter = CallbackHttpClientAdapter(
          (_, _, _) => _fixtureResponse(
            'session_expired.json',
            statusCode: 401,
            headers: const {
              'www-authenticate': ['Bearer'],
            },
          ),
        );

        await expectLater(
          _client(adapter, eventSink: events.add).getSemesters(),
          throwsA(_transportFailure(BackendTransportFailureKind.httpResponse)),
        );

        expect(events, hasLength(1));
        expect(events.single.statusCode, 401);
        expect(events.single.outcome, BackendTransportOutcome.httpResponse);
        final output = events.single.toString();
        expect(output, isNot(contains('SESSION_EXPIRED')));
        expect(output, isNot(contains('<TRACE_ID>')));
        expect(output, isNot(contains('Bearer')));
      },
    );

    test('production emits no event even when a sink is supplied', () async {
      final events = <BackendTransportEvent>[];
      final adapter = CallbackHttpClientAdapter(
        (_, _, _) => jsonResponse(const <int>[]),
      );
      final client = _client(
        adapter,
        environment: 'production',
        eventSink: events.add,
      );

      await client.getSemesters();
      expect(events, isEmpty);
    });

    test(
      'a throwing development sink cannot change request behavior',
      () async {
        final adapter = CallbackHttpClientAdapter(
          (_, _, _) => jsonResponse(const <int>[101]),
        );
        final client = _client(
          adapter,
          eventSink: (_) => throw StateError('sink failure'),
        );

        expect((await client.getSemesters()).single.id, 101);
      },
    );
  });
}

DioBackendApiClient _client(
  CallbackHttpClientAdapter adapter, {
  MemoryCredentialStore? credentials,
  String environment = 'development',
  String backendBaseUrl = _baseUrl,
  BackendTransportEventSink? eventSink,
}) {
  return DioBackendApiClient(
    configuration: AppConfiguration.parse(
      appEnvironment: environment,
      backendBaseUrl: backendBaseUrl,
    ),
    credentialStore: credentials ?? MemoryCredentialStore(),
    httpClientAdapter: adapter,
    eventSink: eventSink ?? (_) {},
    utcNow: () => DateTime.utc(2026, 7, 24, 12),
  );
}

Map<String, dynamic> _fixtureObject(String name) {
  return jsonDecode(_fixtureSource(name)) as Map<String, dynamic>;
}

String _fixtureSource(String name) {
  return File('test/fixtures/backend_api/$name').readAsStringSync();
}

ResponseBody _fixtureResponse(
  String name, {
  int statusCode = 200,
  Map<String, List<String>> headers = const {},
}) {
  return jsonResponse(
    _fixtureSource(name),
    statusCode: statusCode,
    headers: headers,
  );
}

Map<String, dynamic> _firstCourse(Map<String, dynamic> snapshot) {
  return (snapshot['classes'] as List<Object?>).first as Map<String, dynamic>;
}

Map<String, dynamic> _firstActivity(Map<String, dynamic> snapshot) {
  return (_firstCourse(snapshot)['activities'] as List<Object?>).first
      as Map<String, dynamic>;
}

TypeMatcher<BackendTransportException> _transportFailure(
  BackendTransportFailureKind kind,
) {
  return isA<BackendTransportException>().having(
    (error) => error.kind,
    'kind',
    kind,
  );
}

Future<BackendTransportException> _captureTransportFailure(
  Future<Object?> operation,
) async {
  try {
    await operation;
  } on BackendTransportException catch (error) {
    return error;
  }
  fail('Expected BackendTransportException.');
}
