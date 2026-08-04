import 'package:flutter/material.dart';

import '../../../../app/design_system/app_tokens.dart';
import '../domain/local_data_deletion.dart';

class LocalDataDeletionPanel extends StatefulWidget {
  const LocalDataDeletionPanel({
    required this.service,
    required this.onCompleted,
    super.key,
  });

  final LocalDataDeletionService service;
  final ValueChanged<LocalDataDeletionOperation> onCompleted;

  @override
  State<LocalDataDeletionPanel> createState() => _LocalDataDeletionPanelState();
}

class _LocalDataDeletionPanelState extends State<LocalDataDeletionPanel> {
  LocalDataDeletionOperation? _pending;
  LocalDataDeletionResult? _result;

  Future<void> _confirmAndDelete(LocalDataDeletionOperation operation) async {
    if (_pending != null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        key: Key('confirm-${operation.name}'),
        title: Text(_confirmationTitle(operation)),
        content: Text(_confirmationMessage(operation)),
        actions: [
          TextButton(
            key: const Key('cancel-local-data-deletion'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-local-data-deletion'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_confirmationAction(operation)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _run(operation);
  }

  Future<void> _run(LocalDataDeletionOperation operation) async {
    if (_pending != null) {
      return;
    }
    setState(() {
      _pending = operation;
      _result = null;
    });
    final result = switch (operation) {
      LocalDataDeletionOperation.cachedAssignments =>
        await widget.service.deleteCachedAssignments(),
      LocalDataDeletionOperation.savedCredentials =>
        await widget.service.deleteSavedCredentials(),
      LocalDataDeletionOperation.allLocalData =>
        await widget.service.deleteAll(),
    };
    if (!mounted) {
      return;
    }
    setState(() {
      _pending = null;
      _result = result;
    });
    if (result.isComplete) {
      widget.onCompleted(operation);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_pending != null)
          Semantics(
            liveRegion: true,
            child: const ListTile(
              key: Key('local-data-deletion-progress'),
              leading: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              title: Text('Removing local data'),
              subtitle: Text('Keep LEB2 Watch open until cleanup finishes.'),
            ),
          ),
        if (result != null) _DeletionResultView(result: result, onRetry: _run),
        ListTile(
          key: const Key('delete-cached-assignments'),
          leading: const Icon(Icons.delete_sweep_outlined),
          title: const Text('Delete cached assignments'),
          subtitle: const Text('Credentials and preferences stay.'),
          enabled: _pending == null,
          onTap: () =>
              _confirmAndDelete(LocalDataDeletionOperation.cachedAssignments),
        ),
        ListTile(
          key: const Key('delete-saved-credentials'),
          leading: const Icon(Icons.key_off_outlined),
          title: const Text('Delete saved credentials'),
          subtitle: const Text('Cached assignments stay.'),
          enabled: _pending == null,
          onTap: () =>
              _confirmAndDelete(LocalDataDeletionOperation.savedCredentials),
        ),
        ListTile(
          key: const Key('delete-all-local-data'),
          leading: Icon(
            Icons.delete_forever_outlined,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text(
            'Delete all local data',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          subtitle: const Text(
            'Removes everything, including credentials and settings.',
          ),
          enabled: _pending == null,
          onTap: () =>
              _confirmAndDelete(LocalDataDeletionOperation.allLocalData),
        ),
      ],
    );
  }

  String _confirmationTitle(LocalDataDeletionOperation operation) =>
      switch (operation) {
        LocalDataDeletionOperation.cachedAssignments =>
          'Delete cached assignments?',
        LocalDataDeletionOperation.savedCredentials =>
          'Delete saved credentials?',
        LocalDataDeletionOperation.allLocalData => 'Delete all local data?',
      };

  String _confirmationMessage(LocalDataDeletionOperation operation) =>
      switch (operation) {
        LocalDataDeletionOperation.cachedAssignments =>
          'Assignments, courses, semesters, and sync history go. '
              'Credentials and preferences stay.',
        LocalDataDeletionOperation.savedCredentials =>
          'The session and saved credentials go. Cached assignments stay.',
        LocalDataDeletionOperation.allLocalData =>
          'Every LEB2 Watch item on this device goes. If cleanup fails, '
              'you stay here and can '
              'retry.',
      };

  String _confirmationAction(LocalDataDeletionOperation operation) =>
      switch (operation) {
        LocalDataDeletionOperation.cachedAssignments => 'Delete cache',
        LocalDataDeletionOperation.savedCredentials => 'Delete credentials',
        LocalDataDeletionOperation.allLocalData => 'Delete everything',
      };
}

class _DeletionResultView extends StatelessWidget {
  const _DeletionResultView({required this.result, required this.onRetry});

  final LocalDataDeletionResult result;
  final ValueChanged<LocalDataDeletionOperation> onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = result.failedSteps;
    final scheme = Theme.of(context).colorScheme;
    final background = result.isComplete
        ? scheme.secondaryContainer
        : scheme.errorContainer;
    final foreground = result.isComplete
        ? scheme.onSecondaryContainer
        : scheme.onErrorContainer;
    return Semantics(
      key: const Key('local-data-deletion-result'),
      container: true,
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.all(AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.isComplete
                  ? 'Cleanup done.'
                  : 'Some items could not be removed.',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(color: foreground),
            ),
            if (failed.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Retry: '
                '${failed.map(_stepLabel).join(', ')}.',
                style: TextStyle(color: foreground),
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton.tonal(
                key: const Key('retry-local-data-deletion'),
                onPressed: () => onRetry(result.operation),
                child: const Text('Retry cleanup'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _stepLabel(LocalDataDeletionStep step) => switch (step) {
    LocalDataDeletionStep.activeOperations =>
      'active synchronization and notifications',
    LocalDataDeletionStep.backgroundWork => 'background work',
    LocalDataDeletionStep.desktopAutostart => 'start at login',
    LocalDataDeletionStep.notifications => 'notifications',
    LocalDataDeletionStep.credentials => 'secure credentials',
    LocalDataDeletionStep.deviceIdentity => 'installation identity',
    LocalDataDeletionStep.databaseContent => 'local database content',
    LocalDataDeletionStep.databaseFiles => 'local database files',
    LocalDataDeletionStep.cacheFiles => 'app cache',
    LocalDataDeletionStep.providerReset => 'local app state',
  };
}
