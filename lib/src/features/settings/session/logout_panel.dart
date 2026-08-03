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
          'Cached assignment data stays on this device. Logging out releases '
          'this access key from the current device so the same LEB2 account '
          'can connect elsewhere. The key can never move to another account.',
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
    LogoutFailureKind.noSavedAccessKey =>
      'No saved access key was found on this device.',
    LogoutFailureKind.secureStorageUnavailable =>
      'Secure storage is unavailable. Local secrets were not changed.',
    LogoutFailureKind.networkUnavailable ||
    LogoutFailureKind.requestTimeout ||
    LogoutFailureKind.backendUnavailable ||
    LogoutFailureKind.rateLimited =>
      'Logout could not reach the backend. Local secrets were not changed.',
    LogoutFailureKind.invalidResponse =>
      'The backend returned an unexpected logout response. Local secrets were not changed.',
    LogoutFailureKind.deviceIdentityMissing ||
    LogoutFailureKind.deviceIdentityInvalid =>
      'This device could not provide a valid device identifier. Local secrets were not changed.',
    LogoutFailureKind.deviceNotBound =>
      'This access key is not bound to this device. Local secrets were not changed.',
    LogoutFailureKind.deviceMismatch =>
      'This access key is bound to another device. Log out there first or ask your backend operator to reset the binding.',
    LogoutFailureKind.clientVersionRequired ||
    LogoutFailureKind.clientVersionInvalid =>
      'This app could not provide a valid client version. Local secrets were not changed.',
    LogoutFailureKind.clientUpdateRequired =>
      'Install the latest APK before logging out.',
    LogoutFailureKind.localCleanupUncertain =>
      'The backend released the device, but local cleanup is incomplete. Retry cleanup before continuing.',
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
            'Release this device binding and clear saved secrets. Cached '
            'assignments remain available.',
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
