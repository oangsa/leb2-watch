// Hallmark · macrostructure: Control Ledger · theme: Cobalt
// Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V5

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/design_system/app_breakpoints.dart';
import '../../../app/design_system/app_tokens.dart';
import '../../../app/design_system/widgets/app_page_header.dart';
import '../../../app/design_system/widgets/app_state_view.dart';
import '../../../app/design_system/widgets/app_status_banner.dart';
import '../../../core/network/domain/learning_material_models.dart';
import '../../background_sync/domain/background_scheduler.dart';
import '../../assignments/attachments/application/attachment_download_service.dart';
import '../../assignments/attachments/domain/attachment_download.dart';
import '../../semesters/semester_label.dart';
import '../application/course_materials_prefetch_service.dart';
import '../application/course_materials_service.dart';
import '../application/course_preferences_service.dart';
import '../data/course_preferences_store.dart';

const _courseLedgerMaxWidth = 920.0;

class CoursePreferencesPage extends StatefulWidget {
  const CoursePreferencesPage({
    required this.service,
    required this.onChooseSemester,
    this.materialsService,
    this.downloadService,
    this.prefetchService,
    this.backgroundSettingsService,
    super.key,
  });

  final CoursePreferencesService service;
  final VoidCallback onChooseSemester;
  final CourseMaterialsService? materialsService;
  final AttachmentDownloadService? downloadService;
  final CourseMaterialsPrefetcher? prefetchService;
  final BackgroundMonitoringSettingsService? backgroundSettingsService;

  @override
  State<CoursePreferencesPage> createState() => _CoursePreferencesPageState();
}

class _CoursePreferencesPageState extends State<CoursePreferencesPage> {
  StreamSubscription<ActiveCourseCatalog>? _subscription;
  StreamSubscription<BackgroundMonitoringSettings>?
  _backgroundSettingsSubscription;
  ActiveCourseCatalog? _catalog;
  BackgroundMonitoringSettings? _backgroundSettings;
  final Map<CourseKey, _PendingPreference> _pending = {};
  final ValueNotifier<int> _settingsRevision = ValueNotifier(0);
  bool _loading = true;
  bool _streamFailed = false;
  bool _globalWriting = false;
  bool _prefetching = false;
  int? _selectedCourseId;
  String? _writeFailureMessage;
  int _subscriptionGeneration = 0;
  Timer? _prefetchDebounce;

  @override
  void initState() {
    super.initState();
    _subscribe();
    _subscribeBackgroundSettings();
  }

  @override
  void didUpdateWidget(CoursePreferencesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service)) {
      _subscribe();
    }
    if (!identical(
      oldWidget.backgroundSettingsService,
      widget.backgroundSettingsService,
    )) {
      _subscribeBackgroundSettings();
    }
    if (!identical(oldWidget.prefetchService, widget.prefetchService) &&
        _catalog != null) {
      _schedulePrefetch(_catalog!);
    }
  }

  @override
  void dispose() {
    _subscriptionGeneration += 1;
    unawaited(_subscription?.cancel());
    unawaited(_backgroundSettingsSubscription?.cancel());
    _prefetchDebounce?.cancel();
    _settingsRevision.dispose();
    super.dispose();
  }

  void _subscribeBackgroundSettings() {
    unawaited(_backgroundSettingsSubscription?.cancel());
    _backgroundSettingsSubscription = null;
    final service = widget.backgroundSettingsService;
    if (service == null) {
      setState(() => _backgroundSettings = null);
      return;
    }
    _backgroundSettingsSubscription = service.watchSettings().listen(
      (settings) {
        if (!mounted) {
          return;
        }
        setState(() => _backgroundSettings = settings);
        _settingsRevision.value += 1;
      },
      onError: (Object _, StackTrace _) {
        if (mounted) {
          setState(() => _backgroundSettings = null);
        }
      },
    );
  }

  void _subscribe() {
    final generation = ++_subscriptionGeneration;
    unawaited(_subscription?.cancel());
    setState(() {
      _loading = true;
      _streamFailed = false;
    });
    _subscription = widget.service.watchCatalog().listen(
      (catalog) {
        if (!mounted || generation != _subscriptionGeneration) {
          return;
        }
        final currentKeys = catalog.courses.map((course) => course.key).toSet();
        final selectedCourseStillExists = catalog.courses.any(
          (course) => course.key.courseId == _selectedCourseId,
        );
        _pending.removeWhere((key, pending) {
          if (!currentKeys.contains(key)) {
            return true;
          }
          final preference = catalog.courses
              .firstWhere((course) => course.key == key)
              .preference;
          return pending.matches(preference);
        });
        setState(() {
          _catalog = catalog;
          _loading = false;
          _streamFailed = false;
          if (!selectedCourseStillExists) {
            _selectedCourseId = catalog.courses.isEmpty
                ? null
                : catalog.courses.first.key.courseId;
          }
        });
        _settingsRevision.value += 1;
        _schedulePrefetch(catalog);
      },
      onError: (Object _, StackTrace _) {
        if (!mounted || generation != _subscriptionGeneration) {
          return;
        }
        setState(() {
          _loading = false;
          _streamFailed = true;
        });
      },
    );
  }

  Future<void> _setNotificationsMuted(CourseSummary course, bool muted) async {
    await _write(
      course.key,
      pending: _PendingPreference.notificationsMuted(muted),
      action: () =>
          widget.service.setNotificationsMuted(course.key, muted: muted),
    );
  }

  Future<void> _setBackgroundMonitoring(
    CourseSummary course,
    bool enabled,
  ) async {
    await _write(
      course.key,
      pending: _PendingPreference.backgroundMonitoring(enabled),
      action: () => widget.service.setBackgroundMonitoringEnabled(
        course.key,
        enabled: enabled,
      ),
    );
  }

  Future<void> _muteAll(ActiveCourseCatalog catalog) async {
    await _writeAll(
      catalog.courses.where((course) => !course.preference.notificationsMuted),
      pending: (course) => const _PendingPreference.notificationsMuted(true),
      action: (course) =>
          widget.service.setNotificationsMuted(course.key, muted: true),
    );
  }

  Future<void> _disableAllBackgroundMonitoring(
    ActiveCourseCatalog catalog,
  ) async {
    await _writeAll(
      catalog.courses.where(
        (course) => course.preference.backgroundMonitoringEnabled,
      ),
      pending: (course) => const _PendingPreference.backgroundMonitoring(false),
      action: (course) => widget.service.setBackgroundMonitoringEnabled(
        course.key,
        enabled: false,
      ),
    );
  }

  Future<void> _writeAll(
    Iterable<CourseSummary> courses, {
    required _PendingPreference Function(CourseSummary course) pending,
    required Future<CoursePreferenceUpdateResult> Function(CourseSummary course)
    action,
  }) async {
    if (_globalWriting || _pending.isNotEmpty) {
      return;
    }
    setState(() => _globalWriting = true);
    _settingsRevision.value += 1;
    for (final course in courses) {
      final saved = await _write(
        course.key,
        pending: pending(course),
        action: () => action(course),
      );
      if (!saved || !mounted) {
        break;
      }
    }
    if (mounted) {
      setState(() => _globalWriting = false);
      _settingsRevision.value += 1;
    }
  }

  Future<bool> _write(
    CourseKey key, {
    required _PendingPreference pending,
    required Future<CoursePreferenceUpdateResult> Function() action,
  }) async {
    if (_pending.containsKey(key)) {
      return false;
    }
    setState(() {
      _pending[key] = pending;
      _writeFailureMessage = null;
    });
    _settingsRevision.value += 1;

    final result = await action();
    if (!mounted) {
      return false;
    }
    switch (result) {
      case CoursePreferenceUpdateSuccess():
        return true;
      case CoursePreferenceUpdateStale():
        setState(() {
          _pending.remove(key);
          _writeFailureMessage =
              'The course changed before this saved. Try again.';
        });
        _settingsRevision.value += 1;
        return false;
      case CoursePreferenceUpdateFailure():
        setState(() {
          _pending.remove(key);
          _writeFailureMessage =
              'Not saved. Your previous setting is '
              'still in use; try again.';
        });
        _settingsRevision.value += 1;
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final catalog = _catalog;
    if (_loading && catalog == null) {
      return const AppStateView.loading(
        title: 'Loading saved courses',
        message: '',
      );
    }
    if (_streamFailed) {
      return AppStateView.error(
        title: 'Saved courses unavailable',
        message: 'Could not read courses. Nothing changed.',
        actionLabel: 'Retry',
        onAction: _subscribe,
      );
    }
    if (catalog == null || !catalog.hasActiveSemester) {
      return AppStateView.empty(
        title: 'Choose a semester first',
        message: 'Select a semester to see courses.',
        actionLabel: 'Choose semester',
        onAction: widget.onChooseSemester,
      );
    }
    if (catalog.isEmpty) {
      return const AppStateView.empty(
        title: 'No saved courses yet',
        message: 'Sync this semester to see courses.',
      );
    }
    return _buildLedger(context, catalog);
  }

  Widget _buildLedger(BuildContext context, ActiveCourseCatalog catalog) {
    final horizontalPadding =
        AppBreakpoints.of(context) == AppWindowClass.compact
        ? AppSpacing.md
        : AppSpacing.lg;
    final selectedCourse = _selectedCourse(catalog);
    final controlsDisabled = _globalWriting || _pending.isNotEmpty;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _courseLedgerMaxWidth),
          child: ListView(
            key: const Key('course-preferences-list'),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              AppSpacing.md,
              horizontalPadding,
              AppSpacing.lg,
            ),
            children: [
              AppPageHeader(
                title: 'Courses',
                semesterLabel: formatSemesterLabel(
                  name: catalog.activeSemesterName,
                  id: catalog.activeSemesterId,
                ),
                supportingText: _updatesLabel,
                trailing: IconButton(
                  key: const Key('course-settings-button'),
                  tooltip: 'Course settings',
                  onPressed: () => _openSettings(catalog),
                  icon: const Icon(Icons.settings_outlined),
                ),
              ),
              if (_prefetching) ...[
                const SizedBox(height: AppSpacing.sm),
                Semantics(
                  label: 'Caching course files',
                  liveRegion: true,
                  child: const LinearProgressIndicator(
                    key: Key('course-materials-prefetch-progress'),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              DropdownButtonFormField<int>(
                key: Key(
                  'course-preference-selector-${selectedCourse.key.courseId}',
                ),
                initialValue: selectedCourse.key.courseId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Course'),
                items: [
                  for (final course in catalog.courses)
                    DropdownMenuItem(
                      value: course.key.courseId,
                      child: Text(course.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: controlsDisabled
                    ? null
                    : (value) => setState(() => _selectedCourseId = value),
              ),
              if (_writeFailureMessage != null) ...[
                const SizedBox(height: AppSpacing.md),
                AppStatusBanner.stale(
                  key: const Key('course-preference-write-error'),
                  message: _writeFailureMessage!,
                ),
              ],
              if (widget.materialsService != null) ...[
                const SizedBox(height: AppSpacing.md),
                _CourseMaterialsSection(
                  key: Key('course-materials-${selectedCourse.key.courseId}'),
                  course: selectedCourse,
                  service: widget.materialsService!,
                  downloadService: widget.downloadService,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  CourseSummary _selectedCourse(ActiveCourseCatalog catalog) {
    return catalog.courses.firstWhere(
      (course) => course.key.courseId == _selectedCourseId,
      orElse: () => catalog.courses.first,
    );
  }

  String get _updatesLabel {
    final settings = _backgroundSettings;
    if (settings == null) {
      return 'Updates follow assignment checks';
    }
    if (!settings.enabled) {
      return 'Automatic updates off';
    }
    return 'Updates every ${settings.daytimeCadence.minutes} min';
  }

  void _schedulePrefetch(ActiveCourseCatalog catalog) {
    if (widget.prefetchService == null) {
      return;
    }
    _prefetchDebounce?.cancel();
    _prefetchDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_prefetch(catalog));
    });
  }

  Future<void> _prefetch(ActiveCourseCatalog catalog) async {
    final service = widget.prefetchService;
    if (service == null || _prefetching) {
      return;
    }
    setState(() => _prefetching = true);
    try {
      await service.prefetch(
        courses: catalog.courses.map((course) => course.key),
      );
    } on Object {
      // Course files remain manually downloadable when pre-caching is
      // unavailable; the next assignment check retries it.
    }
    if (mounted) {
      setState(() => _prefetching = false);
    }
  }

  Future<void> _openSettings(ActiveCourseCatalog fallbackCatalog) async {
    await showDialog<void>(
      context: context,
      builder: (_) {
        return ValueListenableBuilder<int>(
          valueListenable: _settingsRevision,
          builder: (_, _, _) {
            final catalog = _catalog ?? fallbackCatalog;
            final course = _selectedCourse(catalog);
            final controlsDisabled = _globalWriting || _pending.isNotEmpty;
            final allMuted = catalog.courses.every(
              (course) => course.preference.notificationsMuted,
            );
            final allBackgroundDisabled = catalog.courses.every(
              (course) => !course.preference.backgroundMonitoringEnabled,
            );
            return _CourseSettingsDialog(
              course: course,
              writing: controlsDisabled,
              muteAllEnabled: !controlsDisabled && !allMuted,
              disableAllBackgroundEnabled:
                  !controlsDisabled && !allBackgroundDisabled,
              onMuteAll: () => _muteAll(catalog),
              onDisableAllBackground: () =>
                  _disableAllBackgroundMonitoring(catalog),
              onNotificationsMuted: (value) =>
                  _setNotificationsMuted(course, value),
              onBackgroundMonitoring: (value) =>
                  _setBackgroundMonitoring(course, value),
            );
          },
        );
      },
    );
  }
}

class _CourseMaterialsSection extends StatefulWidget {
  const _CourseMaterialsSection({
    required this.course,
    required this.service,
    required this.downloadService,
    super.key,
  });

  final CourseSummary course;
  final CourseMaterialsService service;
  final AttachmentDownloadService? downloadService;

  @override
  State<_CourseMaterialsSection> createState() =>
      _CourseMaterialsSectionState();
}

class _CourseMaterialsSectionState extends State<_CourseMaterialsSection> {
  CourseMaterialsCatalog? _catalog;
  bool _loading = true;
  bool _busy = false;
  String? _loadError;
  String? _downloadMessage;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_CourseMaterialsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.course.key != widget.course.key ||
        !identical(oldWidget.service, widget.service)) {
      _load();
    }
  }

  void _load() {
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _loadError = null;
      _downloadMessage = null;
    });
    unawaited(_read(generation));
  }

  Future<void> _read(int generation) async {
    try {
      final catalog = await widget.service.read(widget.course.key);
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        _catalog = catalog;
        _loading = false;
        _loadError = null;
      });
    } on Object {
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        _catalog = null;
        _loading = false;
        _loadError = 'Course files unavailable.';
      });
    }
  }

  Future<void> _downloadOne(
    CourseMaterialsCatalog catalog,
    LearningMaterial material,
    LearningMaterialFile file,
  ) async {
    final downloader = widget.downloadService;
    if (downloader == null || _busy) {
      return;
    }
    await _download(
      () => downloader.downloadLearningMaterialOne(
        semesterId: catalog.semesterId,
        classId: catalog.classId,
        materialId: material.id,
        attachmentId: file.id,
        userId: catalog.userId,
      ),
    );
  }

  Future<void> _downloadAll(
    CourseMaterialsCatalog catalog,
    LearningMaterial material,
  ) async {
    final downloader = widget.downloadService;
    if (downloader == null || _busy) {
      return;
    }
    await _download(
      () => downloader.downloadLearningMaterialAll(
        semesterId: catalog.semesterId,
        classId: catalog.classId,
        materialId: material.id,
        userId: catalog.userId,
      ),
    );
  }

  Future<void> _download(
    Future<AttachmentDownloadResult> Function() request,
  ) async {
    setState(() {
      _busy = true;
      _downloadMessage = null;
    });
    final result = await request();
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _downloadMessage = switch (result) {
        AttachmentDownloadSaved(:final path) => 'Saved to $path',
        AttachmentDownloadFailed(:final message) => message,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final catalog = _catalog;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Course files for ${widget.course.name}',
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(AppRadii.panel),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Course files',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  if (_busy)
                    const SizedBox(
                      key: Key('course-materials-progress'),
                      width: AppSpacing.md,
                      height: AppSpacing.md,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_loading)
                const Text('Loading files')
              else if (_loadError != null)
                AppStatusBanner.stale(
                  key: const Key('course-materials-error'),
                  message: _loadError!,
                  actionLabel: 'Retry',
                  onAction: _load,
                )
              else if (catalog == null || catalog.materials.isEmpty)
                Text(
                  'No files',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                )
              else
                ..._materialWidgets(context, catalog),
              if (_downloadMessage != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _downloadMessage!,
                    key: const Key('course-materials-download-message'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _materialWidgets(
    BuildContext context,
    CourseMaterialsCatalog catalog,
  ) {
    final theme = Theme.of(context);
    final widgets = <Widget>[];
    for (var index = 0; index < catalog.materials.length; index += 1) {
      final material = catalog.materials[index];
      if (index > 0) {
        widgets.add(const Divider(height: AppSpacing.lg));
      }
      widgets.add(
        Text(
          material.title,
          style: theme.textTheme.titleMedium,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );
      if (material.fileMaterials.isEmpty) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'No files',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
        continue;
      }
      widgets.add(const SizedBox(height: AppSpacing.xs));
      for (final file in material.fileMaterials) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: Key(
                  'download-learning-material-${material.id}-${file.id}',
                ),
                onPressed: widget.downloadService == null || _busy
                    ? null
                    : () => _downloadOne(catalog, material, file),
                icon: const Icon(Icons.download_outlined),
                label: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    file.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
        );
      }
      if (material.fileMaterials.length > 1) {
        widgets.add(
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: Key('download-learning-material-all-${material.id}'),
              onPressed: widget.downloadService == null || _busy
                  ? null
                  : () => _downloadAll(catalog, material),
              icon: const Icon(Icons.archive_outlined),
              label: const Text('Download all'),
            ),
          ),
        );
      }
    }
    return widgets;
  }
}

class _CourseSettingsDialog extends StatelessWidget {
  const _CourseSettingsDialog({
    required this.course,
    required this.writing,
    required this.muteAllEnabled,
    required this.disableAllBackgroundEnabled,
    required this.onMuteAll,
    required this.onDisableAllBackground,
    required this.onNotificationsMuted,
    required this.onBackgroundMonitoring,
  });

  final CourseSummary course;
  final bool writing;
  final bool muteAllEnabled;
  final bool disableAllBackgroundEnabled;
  final VoidCallback onMuteAll;
  final VoidCallback onDisableAllBackground;
  final ValueChanged<bool> onNotificationsMuted;
  final ValueChanged<bool> onBackgroundMonitoring;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Course settings'),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _GlobalCourseControls(
                writing: writing,
                muteAllEnabled: muteAllEnabled,
                disableAllBackgroundEnabled: disableAllBackgroundEnabled,
                onMuteAll: onMuteAll,
                onDisableAllBackground: onDisableAllBackground,
              ),
              const SizedBox(height: AppSpacing.md),
              _CoursePreferenceRow(
                key: Key('course-preference-row-${course.key.courseId}'),
                course: course,
                writing: writing,
                onNotificationsMuted: onNotificationsMuted,
                onBackgroundMonitoring: onBackgroundMonitoring,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _GlobalCourseControls extends StatelessWidget {
  const _GlobalCourseControls({
    required this.writing,
    required this.muteAllEnabled,
    required this.disableAllBackgroundEnabled,
    required this.onMuteAll,
    required this.onDisableAllBackground,
  });

  final bool writing;
  final bool muteAllEnabled;
  final bool disableAllBackgroundEnabled;
  final VoidCallback onMuteAll;
  final VoidCallback onDisableAllBackground;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'All course settings',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              TextButton.icon(
                key: const Key('course-mute-all'),
                onPressed: muteAllEnabled ? onMuteAll : null,
                icon: const Icon(Icons.notifications_off_outlined),
                label: const Text('Mute all'),
              ),
              TextButton.icon(
                key: const Key('course-background-disable-all'),
                onPressed: disableAllBackgroundEnabled
                    ? onDisableAllBackground
                    : null,
                icon: const Icon(Icons.sync_disabled_rounded),
                label: const Text('Stop all checks'),
              ),
            ],
          ),
          if (writing) ...[
            const SizedBox(height: AppSpacing.xs),
            const LinearProgressIndicator(
              key: Key('course-global-preference-progress'),
            ),
          ],
        ],
      ),
    );
  }
}

class _CoursePreferenceRow extends StatelessWidget {
  const _CoursePreferenceRow({
    required this.course,
    required this.writing,
    required this.onNotificationsMuted,
    required this.onBackgroundMonitoring,
    super.key,
  });

  final CourseSummary course;
  final bool writing;
  final ValueChanged<bool> onNotificationsMuted;
  final ValueChanged<bool> onBackgroundMonitoring;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '${course.name}, course ${course.key.courseId}',
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(AppRadii.panel),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(course.name, style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Semantics(
                label:
                    '${course.postBaselineActivityCount} new activities, '
                    'discovered after the first successful sync; '
                    '${course.notReportedExceededDeadlineCount} upcoming '
                    'deadlines, not reported past at the last saved sync',
                child: ExcludeSemantics(
                  child: Text(
                    '${course.postBaselineActivityCount} new · '
                    '${course.notReportedExceededDeadlineCount} due',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: AppTypography.labelWeight,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              _CoursePreferenceSwitch(
                key: Key('course-mute-${course.key.courseId}'),
                label: 'Mute notifications',
                description: 'Alerts for this course.',
                value: course.preference.notificationsMuted,
                onChanged: writing ? null : onNotificationsMuted,
              ),
              _CoursePreferenceSwitch(
                key: Key('course-background-${course.key.courseId}'),
                label: 'Background monitoring',
                description: 'Checks for updates while closed.',
                value: course.preference.backgroundMonitoringEnabled,
                onChanged: writing ? null : onBackgroundMonitoring,
              ),
              if (writing)
                Semantics(
                  label: 'Saving course settings',
                  liveRegion: true,
                  child: const LinearProgressIndicator(
                    key: Key('course-preference-progress'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoursePreferenceSwitch extends StatelessWidget {
  const _CoursePreferenceSwitch({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final change = onChanged;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '$label. $description',
      toggled: value,
      enabled: change != null,
      onTap: change == null ? null : () => change(!value),
      child: SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: Text(description),
        value: value,
        onChanged: change,
      ),
    );
  }
}

sealed class _PendingPreference {
  const _PendingPreference();

  const factory _PendingPreference.notificationsMuted(bool value) =
      _PendingNotificationsMuted;

  const factory _PendingPreference.backgroundMonitoring(bool value) =
      _PendingBackgroundMonitoring;

  bool matches(CoursePreference preference);
}

final class _PendingNotificationsMuted extends _PendingPreference {
  const _PendingNotificationsMuted(this.value);

  final bool value;

  @override
  bool matches(CoursePreference preference) =>
      preference.notificationsMuted == value;
}

final class _PendingBackgroundMonitoring extends _PendingPreference {
  const _PendingBackgroundMonitoring(this.value);

  final bool value;

  @override
  bool matches(CoursePreference preference) =>
      preference.backgroundMonitoringEnabled == value;
}
