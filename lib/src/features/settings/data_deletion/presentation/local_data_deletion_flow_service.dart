import '../../../../app/routing/app_flow.dart';
import '../domain/local_data_deletion.dart';

/// Applies navigation only after the device cleanup result is complete.
///
/// This object owns presentation flow, not storage cleanup. Updating the flow
/// before returning also survives provider invalidation that unmounts the
/// settings page near the end of delete-all.
final class FlowNavigatingLocalDataDeletionService
    implements LocalDataDeletionService {
  FlowNavigatingLocalDataDeletionService(this._delegate, this._flow);

  final LocalDataDeletionService _delegate;
  final AppFlowController _flow;

  @override
  Future<LocalDataDeletionResult> deleteCachedAssignments() =>
      _run(_delegate.deleteCachedAssignments);

  @override
  Future<LocalDataDeletionResult> deleteSavedCredentials() =>
      _run(_delegate.deleteSavedCredentials);

  @override
  Future<LocalDataDeletionResult> deleteAll() => _run(_delegate.deleteAll);

  Future<LocalDataDeletionResult> _run(
    Future<LocalDataDeletionResult> Function() operation,
  ) async {
    final result = await operation();
    if (result.isComplete) {
      _flow.updateStage(switch (result.operation) {
        LocalDataDeletionOperation.cachedAssignments =>
          AppFlowStage.semesterSelection,
        LocalDataDeletionOperation.savedCredentials =>
          AppFlowStage.authentication,
        LocalDataDeletionOperation.allLocalData => AppFlowStage.onboarding,
      });
    }
    return result;
  }
}
