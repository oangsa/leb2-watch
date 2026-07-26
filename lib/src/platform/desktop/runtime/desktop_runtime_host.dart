import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_dependencies.dart';
import '../../background/desktop/desktop_background_scheduler_platform.dart';
import '../autostart/desktop_autostart_factory.dart';
import '../tray/tray_manager_desktop_tray_platform.dart';
import '../window/window_manager_desktop_window_platform.dart';
import 'desktop_runtime_coordinator.dart';

bool get isDesktopRuntimeTarget {
  if (kIsWeb) {
    return false;
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    _ => false,
  };
}

final class DesktopRuntimeHost extends ConsumerStatefulWidget {
  const DesktopRuntimeHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<DesktopRuntimeHost> createState() => _DesktopRuntimeHostState();
}

final class _DesktopRuntimeHostState extends ConsumerState<DesktopRuntimeHost> {
  DesktopRuntimeCoordinator? _coordinator;
  Completer<DesktopCloseDecision>? _closeDecision;

  @override
  void initState() {
    super.initState();
    if (isDesktopRuntimeTarget) {
      unawaited(_initialize());
    }
  }

  Future<void> _initialize() async {
    final window = WindowManagerDesktopWindowPlatform();
    try {
      final scheduler = ref.read(backgroundSchedulerPlatformProvider);
      if (scheduler is! DesktopBackgroundSyncBinding) {
        await window.allowClose();
        return;
      }
      final desktopBinding = scheduler as DesktopBackgroundSyncBinding;
      final runner = await ref.read(backgroundSyncRunnerProvider.future);
      if (!mounted) {
        return;
      }
      desktopBinding.bindSyncInvoker(runner.run);
      final settings = await ref.read(
        backgroundMonitoringSettingsServiceProvider.future,
      );
      if (!mounted) {
        return;
      }
      final coordinator = DesktopRuntimeCoordinator(
        tray: TrayManagerDesktopTrayPlatform(
          operatingSystem: detectDesktopOperatingSystem(),
        ),
        window: window,
        closePrompt: _WidgetClosePrompt(_showCloseExplanation),
        monitoringSettings: settings,
        autostart: ref.read(desktopAutostartServiceProvider),
        syncInvoker: runner.run,
        disposeProcessScheduler: scheduler.dispose,
      );
      _coordinator = coordinator;
      await coordinator.initialize();
    } on Object {
      // If composition fails, retain conventional window close behavior. The
      // local-first UI itself remains available.
      try {
        await window.allowClose();
      } on Object {
        // There is no additional safe fallback at this layer.
      }
    }
  }

  Future<DesktopCloseDecision> _showCloseExplanation() {
    if (!mounted) {
      return Future.value(DesktopCloseDecision.quit);
    }
    final current = _closeDecision;
    if (current != null) {
      return current.future;
    }
    final decision = Completer<DesktopCloseDecision>();
    setState(() {
      _closeDecision = decision;
    });
    return decision.future;
  }

  void _completeCloseDecision(DesktopCloseDecision decision) {
    final pending = _closeDecision;
    if (pending == null) {
      return;
    }
    setState(() {
      _closeDecision = null;
    });
    if (!pending.isCompleted) {
      pending.complete(decision);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showPrompt = _closeDecision != null;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (showPrompt) ...[
          const ModalBarrier(dismissible: false, color: Colors.black54),
          Center(
            child: DesktopCloseExplanationDialog(
              onKeepRunning: () {
                _completeCloseDecision(DesktopCloseDecision.keepRunning);
              },
              onQuit: () {
                _completeCloseDecision(DesktopCloseDecision.quit);
              },
            ),
          ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    final pending = _closeDecision;
    if (pending != null && !pending.isCompleted) {
      pending.complete(DesktopCloseDecision.quit);
    }
    _coordinator?.dispose();
    super.dispose();
  }
}

final class DesktopCloseExplanationDialog extends StatelessWidget {
  const DesktopCloseExplanationDialog({
    required this.onKeepRunning,
    required this.onQuit,
    super.key,
  });

  final VoidCallback onKeepRunning;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: 'Close behavior explanation',
      child: AlertDialog(
        title: const Text('Keep monitoring?'),
        content: const Text(desktopCloseExplanation),
        actions: [
          TextButton(onPressed: onQuit, child: const Text('Quit')),
          FilledButton(
            onPressed: onKeepRunning,
            child: const Text('Keep running'),
          ),
        ],
      ),
    );
  }
}

final class _WidgetClosePrompt implements DesktopClosePrompt {
  const _WidgetClosePrompt(this._show);

  final Future<DesktopCloseDecision> Function() _show;

  @override
  String get message => desktopCloseExplanation;

  @override
  Future<DesktopCloseDecision> show() => _show();
}
