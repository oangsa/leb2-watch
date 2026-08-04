import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/design_system/app_tokens.dart';
import '../../../core/network/backend_compatibility.dart';
import '../../../core/network/backend_compatibility_controller.dart';

class UpdateRequiredPage extends StatefulWidget {
  const UpdateRequiredPage({
    required this.snapshot,
    required this.onRetry,
    this.controller,
    super.key,
  });

  final BackendCompatibilitySnapshot snapshot;
  final Future<BackendCompatibilitySnapshot?> Function() onRetry;
  final BackendCompatibilityController? controller;

  @override
  State<UpdateRequiredPage> createState() => _UpdateRequiredPageState();
}

class _UpdateRequiredPageState extends State<UpdateRequiredPage> {
  late BackendCompatibilitySnapshot _snapshot = widget.snapshot;
  String? _launchError;
  String? _retryError;
  var _retrying = false;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_updateFromController);
  }

  @override
  void didUpdateWidget(covariant UpdateRequiredPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    oldWidget.controller?.removeListener(_updateFromController);
    widget.controller?.addListener(_updateFromController);
    if (!identical(oldWidget.snapshot, widget.snapshot)) {
      _snapshot = widget.snapshot;
      if (_snapshot.metadata != null) {
        _retryError = null;
      }
    }
  }

  void _updateFromController() {
    final controller = widget.controller;
    if (controller == null || !mounted) {
      return;
    }
    setState(() {
      _snapshot = controller.snapshot;
      if (_snapshot.metadata != null) {
        _retryError = null;
      }
    });
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_updateFromController);
    super.dispose();
  }

  Future<void> _download() async {
    final url = _snapshot.metadata?.downloadUrl;
    if (url == null) {
      return;
    }
    try {
      final launched = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        setState(() => _launchError = 'Could not open the update page.');
      }
    } on Object {
      if (mounted) {
        setState(() => _launchError = 'Could not open the update page.');
      }
    }
  }

  Future<void> _retryMetadata() async {
    if (_retrying) {
      return;
    }
    setState(() {
      _retrying = true;
      _retryError = null;
    });
    BackendCompatibilitySnapshot? snapshot;
    try {
      snapshot = await widget.onRetry();
    } on Object {
      snapshot = null;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _retrying = false;
      if (snapshot == null) {
        _retryError = 'Could not load update details. Try again.';
      } else {
        _snapshot = snapshot;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final metadata = snapshot.metadata;
    final unsupported =
        snapshot.state == BackendCompatibilityState.backendContractUnsupported;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Semantics(
                container: true,
                liveRegion: true,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          unsupported
                              ? Icons.cloud_off_outlined
                              : Icons.system_update_outlined,
                          size: 48,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          unsupported
                              ? 'Backend contract unsupported'
                              : 'Update required',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          unsupported
                              ? 'This backend is not supported.'
                              : 'This version is too old.',
                        ),
                        if (snapshot.installedClientVersion != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'Installed: ${snapshot.installedClientVersion!.coreVersion}',
                          ),
                        ],
                        if (metadata != null) ...[
                          Text(
                            'Minimum: ${metadata.minimumClientVersion.coreVersion}',
                          ),
                          const SizedBox(height: AppSpacing.md),
                          FilledButton(
                            key: const Key('download-update'),
                            onPressed: _download,
                            child: const Text('Download update'),
                          ),
                        ],
                        if (metadata == null) ...[
                          const SizedBox(height: AppSpacing.md),
                          const Text('Update details unavailable.'),
                          const SizedBox(height: AppSpacing.sm),
                          OutlinedButton(
                            key: const Key('retry-update-information'),
                            onPressed: _retrying ? null : _retryMetadata,
                            child: _retrying
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Retry update information'),
                          ),
                        ],
                        if (_retryError != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            _retryError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        if (_launchError != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            _launchError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
