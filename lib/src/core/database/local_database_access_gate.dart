import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as path;

const _activeDirectoryName = '.leb2_watch_database_access';
const _deletingDirectoryName = '.leb2_watch_database_deleting';
const _ownerFilePrefix = 'owner-';
const _leaseFilePrefix = 'lease-';
final _ownerFilePattern = RegExp(r'^owner-([0-9]+)$');
final _leaseFilePattern = RegExp(r'^lease-([0-9]+)-([0-9a-f]{48})$');

enum LocalDatabaseAccessFailureReason {
  deletionInProgress,
  gateUnavailable,
  quiescenceTimedOut,
}

final class LocalDatabaseAccessException implements Exception {
  const LocalDatabaseAccessException(this.reason);

  final LocalDatabaseAccessFailureReason reason;

  @override
  String toString() =>
      'LocalDatabaseAccessException(reason: ${reason.name}, redacted: true)';
}

/// Coordinates database opens and physical deletion across Dart isolates.
///
/// An open owns a uniquely named lease file. Deletion atomically renames the
/// directory containing those leases, so pre-existing opens are captured and
/// later opens cannot enter until the gate is released.
final class LocalDatabaseAccessGate {
  LocalDatabaseAccessGate(this._supportDirectory);

  final Directory _supportDirectory;
  final Random _random = Random.secure();

  Directory get _activeDirectory =>
      Directory(path.join(_supportDirectory.path, _activeDirectoryName));

  Directory get _deletingDirectory =>
      Directory(path.join(_supportDirectory.path, _deletingDirectoryName));

  Future<LocalDatabaseAccessLease> acquireLease() async {
    try {
      await _supportDirectory.create(recursive: true);
      if (await _deletingDirectory.exists()) {
        await _recoverAfterProcessRestart();
        if (await _deletingDirectory.exists()) {
          throw const LocalDatabaseAccessException(
            LocalDatabaseAccessFailureReason.deletionInProgress,
          );
        }
      }
      await _activeDirectory.create();
      await _pruneStaleActiveArtifacts();
      if (await _hasOwnerMarker()) {
        throw const LocalDatabaseAccessException(
          LocalDatabaseAccessFailureReason.deletionInProgress,
        );
      }
      if (await _deletingDirectory.exists()) {
        throw const LocalDatabaseAccessException(
          LocalDatabaseAccessFailureReason.deletionInProgress,
        );
      }

      final token = _newToken();
      final lease = LocalDatabaseAccessLease(
        token: token,
        activeDirectory: _activeDirectory,
        deletingDirectory: _deletingDirectory,
      );
      await lease._create();
      if (await _deletingDirectory.exists()) {
        await lease.release();
        throw const LocalDatabaseAccessException(
          LocalDatabaseAccessFailureReason.deletionInProgress,
        );
      }
      return lease;
    } on LocalDatabaseAccessException {
      rethrow;
    } on Object {
      throw const LocalDatabaseAccessException(
        LocalDatabaseAccessFailureReason.gateUnavailable,
      );
    }
  }

  Future<LocalDatabaseDeletionGate> beginDeletion() async {
    try {
      await _supportDirectory.create(recursive: true);
      if (await _deletingDirectory.exists()) {
        throw const LocalDatabaseAccessException(
          LocalDatabaseAccessFailureReason.deletionInProgress,
        );
      }
      await _activeDirectory.create();
      await _pruneStaleActiveArtifacts();
      if (await _hasOwnerMarker()) {
        throw const LocalDatabaseAccessException(
          LocalDatabaseAccessFailureReason.deletionInProgress,
        );
      }
      await File(
        path.join(_activeDirectory.path, '$_ownerFilePrefix$pid'),
      ).create(exclusive: true);
      await _activeDirectory.rename(_deletingDirectory.path);
      return LocalDatabaseDeletionGate(
        activeDirectory: _activeDirectory,
        deletingDirectory: _deletingDirectory,
      );
    } on LocalDatabaseAccessException {
      rethrow;
    } on Object {
      throw const LocalDatabaseAccessException(
        LocalDatabaseAccessFailureReason.gateUnavailable,
      );
    }
  }

  String _newToken() {
    final values = List<int>.generate(24, (_) => _random.nextInt(256));
    return values
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<void> _pruneStaleActiveArtifacts() async {
    await for (final entry in _activeDirectory.list(followLinks: false)) {
      if (entry is! File) {
        continue;
      }
      final name = path.basename(entry.path);
      final leaseOwnerPid = _leaseOwnerPid(name);
      final deletionOwnerPid = _deletionOwnerPid(name);
      if ((leaseOwnerPid != null && leaseOwnerPid != pid) ||
          (deletionOwnerPid != null && deletionOwnerPid != pid)) {
        await entry.delete();
      }
    }
  }

  Future<bool> _hasOwnerMarker() async => !await _activeDirectory
      .list(followLinks: false)
      .where(
        (entry) =>
            entry is File &&
            path.basename(entry.path).startsWith(_ownerFilePrefix),
      )
      .isEmpty;

  Future<void> _recoverAfterProcessRestart() async {
    final owners = await _deletingDirectory
        .list(followLinks: false)
        .where(
          (entry) =>
              entry is File &&
              path.basename(entry.path).startsWith(_ownerFilePrefix),
        )
        .toList();
    if (owners.length != 1) {
      return;
    }
    final ownerName = path.basename(owners.single.path);
    final ownerPid = _deletionOwnerPid(ownerName);
    if (ownerPid == null || ownerPid == pid) {
      return;
    }

    await for (final entry in _deletingDirectory.list(followLinks: false)) {
      final name = path.basename(entry.path);
      final isOwnedLease = _leaseOwnerPid(name) == ownerPid;
      final isOwnerMarker = name == '$_ownerFilePrefix$ownerPid';
      if (entry is File && (isOwnedLease || isOwnerMarker)) {
        await entry.delete();
      }
    }
    if (await _activeDirectory.exists() &&
        await _activeDirectory.list().isEmpty) {
      await _activeDirectory.delete();
    }
    if (!await _activeDirectory.exists()) {
      await _deletingDirectory.rename(_activeDirectory.path);
    }
  }
}

int? _deletionOwnerPid(String fileName) {
  final match = _ownerFilePattern.firstMatch(fileName);
  return match == null ? null : int.tryParse(match.group(1)!);
}

int? _leaseOwnerPid(String fileName) {
  final match = _leaseFilePattern.firstMatch(fileName);
  return match == null ? null : int.tryParse(match.group(1)!);
}

final class LocalDatabaseAccessLease {
  LocalDatabaseAccessLease({
    required String token,
    required Directory activeDirectory,
    required Directory deletingDirectory,
  }) : this._(token, activeDirectory, deletingDirectory);

  LocalDatabaseAccessLease._(
    this._token,
    this._activeDirectory,
    this._deletingDirectory,
  );

  final String _token;
  final Directory _activeDirectory;
  final Directory _deletingDirectory;
  bool _released = false;

  String get _fileName => '$_leaseFilePrefix$pid-$_token';

  Future<void> _create() async {
    await File(
      path.join(_activeDirectory.path, _fileName),
    ).create(exclusive: true);
  }

  Future<void> release() async {
    if (_released) {
      return;
    }
    _released = true;
    for (final directory in [_activeDirectory, _deletingDirectory]) {
      final file = File(path.join(directory.path, _fileName));
      if (await file.exists()) {
        try {
          await file.delete();
        } on FileSystemException {
          // The directory may have been renamed between exists and delete.
        }
      }
    }
  }
}

final class LocalDatabaseDeletionGate {
  LocalDatabaseDeletionGate({
    required Directory activeDirectory,
    required Directory deletingDirectory,
  }) : this._(activeDirectory, deletingDirectory);

  LocalDatabaseDeletionGate._(this._activeDirectory, this._deletingDirectory);

  final Directory _activeDirectory;
  final Directory _deletingDirectory;
  bool _released = false;

  Future<void> waitForQuiescence({
    Duration timeout = const Duration(seconds: 10),
    Duration pollInterval = const Duration(milliseconds: 25),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final hasNoLeases = await _deletingDirectory
          .list(followLinks: false)
          .where(
            (entry) => path.basename(entry.path).startsWith(_leaseFilePrefix),
          )
          .isEmpty;
      if (hasNoLeases) {
        return;
      }
      if (!DateTime.now().isBefore(deadline)) {
        throw const LocalDatabaseAccessException(
          LocalDatabaseAccessFailureReason.quiescenceTimedOut,
        );
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  Future<void> release() async {
    if (_released) {
      return;
    }
    _released = true;
    try {
      if (await _activeDirectory.exists()) {
        final remaining = await _activeDirectory.list().isEmpty;
        if (!remaining) {
          throw const LocalDatabaseAccessException(
            LocalDatabaseAccessFailureReason.gateUnavailable,
          );
        }
        await _activeDirectory.delete();
      }
      if (await _deletingDirectory.exists()) {
        await for (final entry in _deletingDirectory.list(followLinks: false)) {
          if (entry is File &&
              path.basename(entry.path).startsWith(_ownerFilePrefix)) {
            await entry.delete();
          }
        }
        await _deletingDirectory.rename(_activeDirectory.path);
      } else {
        await _activeDirectory.create();
      }
    } on LocalDatabaseAccessException {
      rethrow;
    } on Object {
      throw const LocalDatabaseAccessException(
        LocalDatabaseAccessFailureReason.gateUnavailable,
      );
    }
  }
}
