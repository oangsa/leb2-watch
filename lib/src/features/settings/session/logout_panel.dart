import 'package:flutter/material.dart';

import '../../authentication/application/logout_service.dart';

class LogoutPanel extends StatefulWidget {
  const LogoutPanel({
    required this.service,
    required this.onCompleted,
    super.key,
  });

  final LogoutService service;
  final VoidCallback onCompleted;

  @override
  State<LogoutPanel> createState() => _LogoutPanelState();
}

class _LogoutPanelState extends State<LogoutPanel> {
  bool _pending = false;
  String? _message;
  bool _isError = false;

  Future<void> _confirm() async {
    if (_pending) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('confirm-logout'),
        title: const Text('Log out?'),
        content: const Text(
          'Frees this access key for another device. Cached assignments '
          'stay here.',
        ),
        actions: [
          TextButton(
            key: const Key('cancel-logout'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-logout-action'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run();
    }
  }

  Future<void> _run() async {
    if (_pending) {
      return;
    }
    setState(() {
      _pending = true;
      _message = null;
    });
    final result = await widget.service.logout();
    if (!mounted) {
      return;
    }
    switch (result) {
      case LogoutSuccess():
        setState(() => _pending = false);
        widget.onCompleted();
      case LogoutFailure(:final kind):
        setState(() {
          _pending = false;
          _isError = true;
          _message = _failureMessage(kind);
        });
    }
  }

  String _failureMessage(LogoutFailureKind kind) => switch (kind) {
    LogoutFailureKind.noSavedAccessKey => 'No saved access key on this device.',
    LogoutFailureKind.secureStorageUnavailable =>
      'Secure storage unavailable. Nothing changed.',
    LogoutFailureKind.networkUnavailable ||
    LogoutFailureKind.requestTimeout ||
    LogoutFailureKind.backendUnavailable ||
    LogoutFailureKind.rateLimited =>
      'Could not reach the backend. Nothing changed.',
    LogoutFailureKind.invalidResponse =>
      'Unexpected backend response. Nothing changed.',
    LogoutFailureKind.deviceIdentityMissing ||
    LogoutFailureKind.deviceIdentityInvalid =>
      'Invalid device identifier. Nothing changed.',
    LogoutFailureKind.deviceNotBound =>
      'Key is not bound to this device. Nothing changed.',
    LogoutFailureKind.deviceMismatch =>
      'Key is bound to another device. Log out there, or ask your operator to reset it.',
    LogoutFailureKind.clientVersionRequired ||
    LogoutFailureKind.clientVersionInvalid =>
      'Invalid client version. Nothing changed.',
    LogoutFailureKind.clientUpdateRequired =>
      'Install the latest APK before logging out.',
    LogoutFailureKind.localCleanupUncertain =>
      'Device released, but local cleanup is incomplete. Retry it.',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: const Key('logout-action'),
          leading: const Icon(Icons.logout),
          title: const Text('Log out'),
          subtitle: const Text(
            'Clears saved secrets. Cached assignments stay.',
          ),
          enabled: !_pending,
          onTap: _confirm,
        ),
        if (_pending)
          Semantics(
            liveRegion: true,
            child: ListTile(
              key: Key('logout-progress'),
              title: Text('Releasing device binding'),
              leading: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        if (_message != null)
          Semantics(
            liveRegion: true,
            child: ListTile(
              key: const Key('logout-result'),
              title: Text(_isError ? 'Logout incomplete' : 'Logout complete'),
              subtitle: Text(_message!),
              isThreeLine: true,
            ),
          ),
      ],
    );
  }
}
