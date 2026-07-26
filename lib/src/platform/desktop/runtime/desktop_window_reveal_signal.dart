import 'dart:async';

final class DesktopWindowRevealSignal {
  final StreamController<void> _requests = StreamController<void>.broadcast(
    sync: true,
  );

  Stream<void> get requests => _requests.stream;

  void requestReveal() {
    if (!_requests.isClosed) {
      _requests.add(null);
    }
  }

  Future<void> dispose() => _requests.close();
}
