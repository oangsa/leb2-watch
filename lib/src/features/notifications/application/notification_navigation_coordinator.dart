import 'dart:async';

import '../../../app/routing/app_flow.dart';
import '../../assignments/detail/domain/assignment_detail_key.dart';
import '../domain/local_notification_models.dart';
import '../domain/local_notification_service.dart';

final class NotificationNavigationCoordinator {
  NotificationNavigationCoordinator(
    LocalNotificationService notifications,
    this._flowController,
    this._openAssignment,
  ) {
    _subscription = notifications.responses.listen(
      _receive,
      onError: (_, _) {},
    );
    _flowController.addListener(_deliverIfReady);
  }

  final AppFlowController _flowController;
  final void Function(AssignmentDetailKey key) _openAssignment;
  late final StreamSubscription<LocalNotificationTarget> _subscription;

  AssignmentDetailKey? _pending;
  bool _disposed = false;

  void _receive(LocalNotificationTarget target) {
    if (_disposed) {
      return;
    }
    _pending = switch (target) {
      AssignmentNotificationTarget(:final key) => key,
    };
    _deliverIfReady();
  }

  void _deliverIfReady() {
    if (_disposed || _flowController.stage != AppFlowStage.ready) {
      return;
    }
    final target = _pending;
    if (target == null) {
      return;
    }
    _pending = null;
    _openAssignment(target);
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _pending = null;
    _flowController.removeListener(_deliverIfReady);
    unawaited(_subscription.cancel());
  }
}
