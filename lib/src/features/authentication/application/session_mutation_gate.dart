import 'dart:async';
import 'dart:io';
import 'dart:math';

typedef SessionMutationLockFileProvider = Future<File> Function();
typedef SessionMutationOwnerFileDelete = Future<void> Function(File file);
typedef SessionMutationReleaseBarrier = Future<void> Function();

const _ownerDeleteAttempts = 3;
const _ownerDeleteRetryDelay = Duration(milliseconds: 5);

abstract interface class SessionMutationGate {
  Future<T> runExclusive<T>(
    Future<T> Function() action, {
    bool Function()? isCancelled,
  });
}

final class FileSessionMutationGate implements SessionMutationGate {
  factory FileSessionMutationGate({
    required SessionMutationLockFileProvider lockFileProvider,
    Duration acquireTimeout = const Duration(seconds: 5),
    Duration pollInterval = const Duration(milliseconds: 25),
    SessionMutationOwnerFileDelete? testingOwnerFileDelete,
    SessionMutationReleaseBarrier? testingBeforeOwnerMarkerRelease,
  }) {
    return FileSessionMutationGate._(
      lockFileProvider,
      acquireTimeout,
      pollInterval,
      testingOwnerFileDelete ?? ((file) => file.delete()),
      testingBeforeOwnerMarkerRelease,
    );
  }

  FileSessionMutationGate._(
    this._lockFileProvider,
    this.acquireTimeout,
    this.pollInterval,
    this._ownerFileDelete,
    this._beforeOwnerMarkerRelease,
  );

  final SessionMutationLockFileProvider _lockFileProvider;
  final Duration acquireTimeout;
  final Duration pollInterval;
  final SessionMutationOwnerFileDelete _ownerFileDelete;
  final SessionMutationReleaseBarrier? _beforeOwnerMarkerRelease;
  final Random _random = Random.secure();

  @override
  Future<T> runExclusive<T>(
    Future<T> Function() action, {
    bool Function()? isCancelled,
  }) async {
    final lease = await _acquire(isCancelled);
    try {
      _throwIfCancelled(isCancelled);
      return await action();
    } finally {
      await lease.release();
    }
  }

  Future<_SessionMutationLease> _acquire(bool Function()? isCancelled) async {
    _throwIfCancelled(isCancelled);
    final lockFile = await _resolveLockFile();
    final ownerFile = File('${lockFile.path}.owner');
    final owner = '$pid-${_newToken()}';
    final stopwatch = Stopwatch()..start();
    while (true) {
      _throwIfCancelled(isCancelled);
      _throwIfTimedOut(stopwatch);

      final claimed = await _tryCreateOwner(ownerFile, owner);
      if (claimed) {
        final lease = await _lockClaimedFile(
          lockFile: lockFile,
          ownerFile: ownerFile,
          owner: owner,
        );
        if (lease != null) {
          return lease;
        }
      } else {
        final lease = await _tryRecoverPriorProcessOwner(
          lockFile: lockFile,
          ownerFile: ownerFile,
          owner: owner,
        );
        if (lease != null) {
          return lease;
        }
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  Future<bool> _tryCreateOwner(File ownerFile, String owner) async {
    var created = false;
    try {
      await ownerFile.create(exclusive: true);
      created = true;
      await ownerFile.writeAsString(owner, flush: true);
      return true;
    } on FileSystemException {
      if (created) {
        await _deleteOwnerIfCurrent(ownerFile, owner);
        throw const SessionMutationGateException(
          SessionMutationGateFailureReason.unavailable,
        );
      }
      return false;
    } on Object {
      if (created) {
        await _deleteOwnerIfCurrent(ownerFile, owner);
      }
      throw const SessionMutationGateException(
        SessionMutationGateFailureReason.unavailable,
      );
    }
  }

  Future<_SessionMutationLease?> _lockClaimedFile({
    required File lockFile,
    required File ownerFile,
    required String owner,
  }) async {
    final handle = await _openLockFile(lockFile);
    try {
      await handle.lock(FileLock.exclusive);
    } on FileSystemException catch (error) {
      await handle.close();
      if (!_isLockBusy(error)) {
        await _deleteOwnerIfCurrent(ownerFile, owner);
        throw const SessionMutationGateException(
          SessionMutationGateFailureReason.unavailable,
        );
      }
      return null;
    }

    if (await _readOwner(ownerFile) != owner) {
      await handle.unlock();
      await handle.close();
      return null;
    }
    return _SessionMutationLease(
      handle,
      ownerFile,
      owner,
      ownerFileDelete: _ownerFileDelete,
      beforeOwnerMarkerRelease: _beforeOwnerMarkerRelease,
    );
  }

  Future<_SessionMutationLease?> _tryRecoverPriorProcessOwner({
    required File lockFile,
    required File ownerFile,
    required String owner,
  }) async {
    final observedOwner = await _readOwner(ownerFile);
    if (observedOwner == null || _ownerPid(observedOwner) == pid) {
      return null;
    }

    final handle = await _openLockFile(lockFile);
    try {
      await handle.lock(FileLock.exclusive);
    } on FileSystemException catch (error) {
      await handle.close();
      if (_isLockBusy(error)) {
        return null;
      }
      throw const SessionMutationGateException(
        SessionMutationGateFailureReason.unavailable,
      );
    }

    if (await _readOwner(ownerFile) != observedOwner) {
      await handle.unlock();
      await handle.close();
      return null;
    }
    try {
      await ownerFile.writeAsString(owner, flush: true);
    } on Object {
      await handle.unlock();
      await handle.close();
      throw const SessionMutationGateException(
        SessionMutationGateFailureReason.unavailable,
      );
    }
    return _SessionMutationLease(
      handle,
      ownerFile,
      owner,
      ownerFileDelete: _ownerFileDelete,
      beforeOwnerMarkerRelease: _beforeOwnerMarkerRelease,
    );
  }

  Future<RandomAccessFile> _openLockFile(File lockFile) async {
    try {
      return await lockFile.open(mode: FileMode.append);
    } on Object {
      throw const SessionMutationGateException(
        SessionMutationGateFailureReason.unavailable,
      );
    }
  }

  Future<String?> _readOwner(File ownerFile) async {
    try {
      if (!await ownerFile.exists()) {
        return null;
      }
      return await ownerFile.readAsString();
    } on FileSystemException {
      return null;
    } on Object {
      throw const SessionMutationGateException(
        SessionMutationGateFailureReason.unavailable,
      );
    }
  }

  int? _ownerPid(String owner) => int.tryParse(owner.split('-').first);

  String _newToken() {
    final values = List<int>.generate(24, (_) => _random.nextInt(256));
    return values
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<void> _deleteOwnerIfCurrent(File ownerFile, String owner) async {
    try {
      if (await _readOwner(ownerFile) == owner) {
        await ownerFile.delete();
      }
    } on Object {
      // The fixed acquisition failure remains authoritative.
    }
  }

  Future<File> _resolveLockFile() async {
    try {
      final file = await _lockFileProvider();
      await file.parent.create(recursive: true);
      return file;
    } on Object {
      throw const SessionMutationGateException(
        SessionMutationGateFailureReason.unavailable,
      );
    }
  }

  void _throwIfCancelled(bool Function()? isCancelled) {
    if (!(isCancelled?.call() ?? false)) {
      return;
    }
    throw const SessionMutationGateException(
      SessionMutationGateFailureReason.cancelled,
    );
  }

  void _throwIfTimedOut(Stopwatch stopwatch) {
    if (stopwatch.elapsed < acquireTimeout) {
      return;
    }
    throw const SessionMutationGateException(
      SessionMutationGateFailureReason.busy,
    );
  }

  bool _isLockBusy(FileSystemException error) {
    return switch (error.osError?.errorCode) {
      11 || 13 || 33 || 35 => true,
      _ => false,
    };
  }

  @override
  String toString() => 'FileSessionMutationGate(redacted: true)';
}

enum SessionMutationGateFailureReason { busy, cancelled, unavailable }

final class SessionMutationGateException implements Exception {
  const SessionMutationGateException(this.reason);

  final SessionMutationGateFailureReason reason;

  @override
  String toString() =>
      'SessionMutationGateException(reason: ${reason.name}, redacted: true)';
}

final class _SessionMutationLease {
  _SessionMutationLease(
    this._handle,
    this._ownerFile,
    this._owner, {
    required this._ownerFileDelete,
    this._beforeOwnerMarkerRelease,
  });

  final RandomAccessFile _handle;
  final File _ownerFile;
  final String _owner;
  final SessionMutationOwnerFileDelete _ownerFileDelete;
  final SessionMutationReleaseBarrier? _beforeOwnerMarkerRelease;
  bool _advisoryReleased = false;
  bool _releaseBarrierPassed = false;
  bool _released = false;

  Future<void> release() async {
    if (_released) {
      return;
    }
    await _releaseAdvisoryLock();
    await _passReleaseBarrier();
    await _releaseOwnerMarker();
    _released = true;
  }

  Future<void> _releaseAdvisoryLock() async {
    if (_advisoryReleased) {
      return;
    }
    try {
      await _handle.unlock();
      await _handle.close();
      _advisoryReleased = true;
    } on Object {
      try {
        await _handle.close();
      } on Object {
        // The fixed release failure remains authoritative.
      }
      throw const SessionMutationGateException(
        SessionMutationGateFailureReason.unavailable,
      );
    }
  }

  Future<void> _passReleaseBarrier() async {
    if (_releaseBarrierPassed) {
      return;
    }
    try {
      await _beforeOwnerMarkerRelease?.call();
      _releaseBarrierPassed = true;
    } on Object {
      throw const SessionMutationGateException(
        SessionMutationGateFailureReason.unavailable,
      );
    }
  }

  Future<void> _releaseOwnerMarker() async {
    for (var attempt = 0; attempt < _ownerDeleteAttempts; attempt += 1) {
      try {
        if (!await _ownerFile.exists() ||
            await _ownerFile.readAsString() != _owner) {
          return;
        }
        await _ownerFileDelete(_ownerFile);
        return;
      } on Object {
        if (attempt == _ownerDeleteAttempts - 1) {
          throw const SessionMutationGateException(
            SessionMutationGateFailureReason.unavailable,
          );
        }
        await Future<void>.delayed(_ownerDeleteRetryDelay);
      }
    }
  }
}
