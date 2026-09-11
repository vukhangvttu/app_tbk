import 'dart:async';

enum AuthState {
  authenticated,
  unauthenticated,
}

class AuthStateManager {
  static final AuthStateManager _instance = AuthStateManager._internal();
  factory AuthStateManager() => _instance;
  AuthStateManager._internal();

  AuthState _currentState = AuthState.unauthenticated;
  AuthState get currentState => _currentState;

  // Stream để thông báo khi cần logout
  final _authStateController = StreamController<AuthState>.broadcast();
  Stream<AuthState> get authStateStream => _authStateController.stream;

  // Notify về việc cần logout
  void notifyAuthenticationFailed() {
    if (_currentState == AuthState.unauthenticated) {
      print('ℹ️ AuthStateManager: Đã ở trạng thái unauthenticated, bỏ qua notify trùng lặp.');
      return;
    }
    _currentState = AuthState.unauthenticated;
    _authStateController.add(AuthState.unauthenticated);
  }

  void notifyAuthenticationSuccess() {
    _currentState = AuthState.authenticated;
    _authStateController.add(AuthState.authenticated);
  }

  void dispose() {
    _authStateController.close();
  }
}