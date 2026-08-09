import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_dependencies.dart';
import '../../../features/assignments/sync/assignment_sync_service.dart';
import '../../../features/notifications/application/desktop_deadline_reminder_delivery_coordinator.dart';
import '../../background/desktop/desktop_background_scheduler_platform.dart';
import '../autostart/desktop_autostart_factory.dart';
import '../tray/tray_manager_desktop_tray_platform.dart';
import '../window/window_manager_desktop_window_platform.dart';
import 'desktop_runtime_coordinator.dart';
import 'desktop_window_reveal_signal.dart';

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

/// Owns the process-lifetime desktop driver while its database-backed provider
/// is replaced. Replacement is ordered so the old driver is disposed before
/// the new driver starts.
final class DesktopDeadlineReminderRuntimeBinding<T extends Object> {
  factory DesktopDeadlineReminderRuntimeBinding({
    required Future<void> Function(T driver) start,
    required void Function(T driver) dispose,
  }) => DesktopDeadlineReminderRuntimeBinding._(start, dispose);

  DesktopDeadlineReminderRuntimeBinding._(this._start, this._dispose);

  final Future<void> Function(T driver) _start;
  final void Function(T driver) _dispose;

  T? _current;
  bool _closed = false;

  Future<void> replace(T? next) async {
    if (_closed) {
      if (next != null) {
        _safeDispose(next);
      }
      return;
    }
    if (identical(_current, next)) {
      return;
    }

    final previous = _current;
    _current = null;
    if (previous != null) {
      _safeDispose(previous);
    }
    if (next == null) {
      return;
    }

    _current = next;
    try {
      await _start(next);
    } on Object {
      if (identical(_current, next)) {
        _current = null;
        _safeDispose(next);
      }
    }
  }

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    final current = _current;
    _current = null;
    if (current != null) {
      _safeDispose(current);
    }
  }

  void _safeDispose(T driver) {
    try {
      _dispose(driver);
    } on Object {
      // Process teardown and provider replacement must remain recoverable.
    }
  }
}

final class DesktopRuntimeHost extends ConsumerStatefulWidget {
  const DesktopRuntimeHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<DesktopRuntimeHost> createState() => _DesktopRuntimeHostState();
}

final class _DesktopRuntimeHostState extends ConsumerState<DesktopRuntimeHost> {
  DesktopRuntimeCoordinator? _coordinator;
  DesktopWindowRevealSubscription? _windowRevealSubscription;
  ProviderSubscription<AsyncValue<DesktopDeadlineReminderDeliveryCoordinator?>>?
  _deadlineDeliverySubscription;
  DesktopDeadlineReminderRuntimeBinding<
    DesktopDeadlineReminderDeliveryCoordinator
  >?
  _deadlineDeliveryBinding;
  Completer<DesktopCloseDecision>? _closeDecision;
  bool _windowRevealPending = false;

  @override
  void initState() {
    super.initState();
    if (isDesktopRuntimeTarget) {
      _windowRevealSubscription = DesktopWindowRevealSubscription(
        signal: ref.read(desktopWindowRevealSignalProvider),
        onReveal: _revealWindow,
      );
      final deadlineDeliveryBinding =
          DesktopDeadlineReminderRuntimeBinding<
            DesktopDeadlineReminderDeliveryCoordinator
          >(
            start: (coordinator) => coordinator.start(),
            dispose: (coordinator) => coordinator.dispose(),
          );
      _deadlineDeliveryBinding = deadlineDeliveryBinding;
      _deadlineDeliverySubscription = ref.listenManual(
        desktopDeadlineReminderDeliveryCoordinatorProvider,
        (_, next) {
          next.when(
            data: (coordinator) {
              unawaited(deadlineDeliveryBinding.replace(coordinator));
            },
            error: (_, _) {
              unawaited(deadlineDeliveryBinding.replace(null));
            },
            loading: () {
              unawaited(deadlineDeliveryBinding.replace(null));
            },
          );
        },
        fireImmediately: true,
      );
      unawaited(_initialize());
    }
  }

  Future<void> _initialize() async {
    final window = WindowManagerDesktopWindowPlatform();
    DesktopRuntimeCoordinator? coordinator;
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
      final reconciler = await ref.read(
        backgroundScheduleReconcilerProvider.future,
      );
      if (!mounted) {
        return;
      }
      // Each timer tick re-registers, so the desktop cadence follows the
      // daytime/night window without the app being reopened.
      desktopBinding.bindSyncInvoker(({required SyncReason reason}) async {
        final result = await runner.run(reason: reason);
        try {
          await reconciler.reconcilePeriodicSync(executionAllowed: true);
        } on Object {
          // The next tick re-arms; the completed run still stands.
        }
        return result;
      });
      final settings = await ref.read(
        backgroundMonitoringSettingsServiceProvider.future,
      );
      if (!mounted) {
        return;
      }
      coordinator = DesktopRuntimeCoordinator(
        tray: TrayManagerDesktopTrayPlatform(
          operatingSystem: detectDesktopOperatingSystem(),
        ),
        window: window,
        closePrompt: _WidgetClosePrompt(_showCloseExplanation),
        monitoringSettings: settings,
        autostart: ref.read(desktopAutostartServiceProvider),
        syncInvoker: runner.run,
        disposeProcessScheduler: () {
          _deadlineDeliveryBinding?.close();
          scheduler.dispose();
        },
      );
      await coordinator.initialize();
      if (!mounted) {
        coordinator.dispose();
        return;
      }
      _coordinator = coordinator;
      if (_windowRevealPending) {
        _windowRevealPending = false;
        await coordinator.openWindow();
      }
    } on Object {
      coordinator?.dispose();
      // If composition fails, retain conventional window close behavior. The
      // local-first UI itself remains available.
      try {
        await window.allowClose();
      } on Object {
        // There is no additional safe fallback at this layer.
      }
    }
  }

  Future<void> _revealWindow() async {
    final coordinator = _coordinator;
    if (coordinator == null) {
      _windowRevealPending = true;
      return;
    }
    await coordinator.openWindow();
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
    _windowRevealSubscription?.dispose();
    _deadlineDeliverySubscription?.close();
    _deadlineDeliveryBinding?.close();
    _windowRevealPending = false;
    final pending = _closeDecision;
    if (pending != null && !pending.isCompleted) {
      pending.complete(DesktopCloseDecision.quit);
    }
    _coordinator?.dispose();
    super.dispose();
  }
}

final class DesktopWindowRevealSubscription {
  DesktopWindowRevealSubscription({
    required DesktopWindowRevealSignal signal,
    required Future<void> Function() onReveal,
  }) {
    _subscription = signal.requests.listen((_) {
      unawaited(onReveal());
    });
  }

  late final StreamSubscription<void> _subscription;
  bool _disposed = false;

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    unawaited(_subscription.cancel());
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
