import 'dart:async';
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

final class BackendRequestCancellation {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  void cancel() {
    if (!isCancelled) {
      _cancelled.complete();
    }
  }

  Future<void> get _whenCancelled => _cancelled.future;

  @override
  String toString() => 'BackendRequestCancellation(redacted: true)';
}
