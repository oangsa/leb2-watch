import '../../core/database/app_database_manager.dart';
import '../../core/database/app_database.dart';
import '../../core/database/local_database_storage.dart';
import '../../core/security/credential_store.dart';
import '../routing/app_flow.dart';

final class AppStartupFlowException implements Exception {
  const AppStartupFlowException();

  @override
  String toString() => 'AppStartupFlowException(redacted: true)';
}

Future<AppFlowStage> resolveInitialAppFlowStage({
  required LocalDatabaseStorage databaseStorage,
  required CredentialStore credentialStore,
}) async {
  final manager = AppDatabaseManager(databaseStorage);
  AppFlowStage? resolvedStage;
  var resolutionFailed = false;

  try {
    final database = await manager.open();
    final settings = await database
        .select(database.appSettings)
        .getSingleOrNull();
    if (!_provesPriorVerifiedSession(settings)) {
      resolvedStage = AppFlowStage.onboarding;
    } else {
      final credentialPresence = await _readCredentialPresence(credentialStore);
      resolvedStage = switch (credentialPresence) {
        _CredentialPresence.absent => AppFlowStage.authentication,
        _CredentialPresence.present || _CredentialPresence.unavailable =>
          settings!.activeSemesterId == null
              ? AppFlowStage.semesterSelection
              : AppFlowStage.ready,
      };
    }
  } on Object {
    resolutionFailed = true;
  }

  try {
    await manager.close();
  } on Object {
    throw const AppStartupFlowException();
  }

  if (resolutionFailed || resolvedStage == null) {
    throw const AppStartupFlowException();
  }
  return resolvedStage;
}

bool _provesPriorVerifiedSession(AppSetting? settings) {
  if (settings == null ||
      settings.sessionRevision <= 0 ||
      settings.leb2UserId == null) {
    return false;
  }
  return settings.sessionLifecycle == 'active' ||
      settings.sessionLifecycle == 'expired';
}

Future<_CredentialPresence> _readCredentialPresence(
  CredentialStore credentialStore,
) async {
  try {
    final cookie = await credentialStore.readSessionCookie();
    return cookie == null
        ? _CredentialPresence.absent
        : _CredentialPresence.present;
  } on Object {
    return _CredentialPresence.unavailable;
  }
}

enum _CredentialPresence { present, absent, unavailable }
