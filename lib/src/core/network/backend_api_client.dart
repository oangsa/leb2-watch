import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:leb2_watch/src/core/config/app_configuration.dart';
import 'package:leb2_watch/src/core/network/backend_transport_event.dart';
import 'package:leb2_watch/src/core/network/backend_transport_failure.dart';
import 'package:leb2_watch/src/core/network/retry_after_parser.dart';
import 'package:leb2_watch/src/core/network/transport/backend_dtos.dart';
import 'package:leb2_watch/src/core/security/credential_store.dart';

import 'domain/backend_models.dart';

part 'dio_backend_api_client.dart';

abstract interface class BackendApiClient {
  Future<List<Semester>> getSemesters({
    BackendRequestCancellation? cancellation,
  });

  Future<List<Course>> getCourses({
    required int semesterId,
    BackendRequestCancellation? cancellation,
  });

  Future<AssignmentSnapshot> getSemesterSnapshot({
    required int semesterId,
    required int userId,
    BackendRequestCancellation? cancellation,
  });
}

abstract interface class BackendSessionClient {
  Future<List<Semester>> verifySessionCookie({
    required String candidateCookie,
    BackendRequestCancellation? cancellation,
  });

  Future<BackendUserIdentity> authenticateUser({
    required String username,
    required String password,
    BackendRequestCancellation? cancellation,
  });

  Future<BackendSessionCookie> acquireSessionCookie({
    required String username,
    required String password,
    BackendRequestCancellation? cancellation,
  });
}

final class BackendUserIdentity {
  const BackendUserIdentity({required this.id});

  final int id;

  @override
  String toString() => 'BackendUserIdentity(redacted: true)';
}

final class BackendSessionCookie {
  const BackendSessionCookie(this.value);

  final String value;

  @override
  String toString() => 'BackendSessionCookie(redacted: true)';
}

final class BackendRequestCancellation {
  final Set<void Function()> _listeners = <void Function()>{};
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) {
      return;
    }

    _isCancelled = true;
    final listeners = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  void Function() _registerListener(void Function() listener) {
    if (_isCancelled) {
      listener();
      return () {};
    }

    _listeners.add(listener);
    var isDisposed = false;
    return () {
      if (isDisposed) {
        return;
      }
      isDisposed = true;
      _listeners.remove(listener);
    };
  }

  @override
  String toString() => 'BackendRequestCancellation(redacted: true)';
}
