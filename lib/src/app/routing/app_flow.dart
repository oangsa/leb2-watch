import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppFlowStage { onboarding, authentication, semesterSelection, ready }

final appFlowControllerProvider = Provider<AppFlowController>((ref) {
  final controller = AppFlowController();
  ref.onDispose(controller.dispose);
  return controller;
});

final class AppFlowController extends ChangeNotifier {
  AppFlowController({AppFlowStage initialStage = AppFlowStage.onboarding})
    : _stage = initialStage;

  AppFlowStage _stage;

  AppFlowStage get stage => _stage;

  void updateStage(AppFlowStage stage) {
    if (_stage == stage) {
      return;
    }

    _stage = stage;
    notifyListeners();
  }
}
