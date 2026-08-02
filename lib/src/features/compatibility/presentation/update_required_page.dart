import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/design_system/app_tokens.dart';
import '../../../core/network/backend_compatibility.dart';

class UpdateRequiredPage extends StatefulWidget {
  const UpdateRequiredPage({required this.snapshot, super.key});

  final BackendCompatibilitySnapshot snapshot;

  @override
  State<UpdateRequiredPage> createState() => _UpdateRequiredPageState();
}

class _UpdateRequiredPageState extends State<UpdateRequiredPage> {
  String? _launchError;

  Future<void> _download() async {
    final url = widget.snapshot.metadata?.downloadUrl;
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

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
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
                              ? 'This backend contract is not supported by LEB2 Watch.'
                              : 'This version of LEB2 Watch is no longer compatible with the server.',
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
